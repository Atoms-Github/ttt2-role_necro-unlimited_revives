if SERVER then
	AddCSLuaFile()

	resource.AddFile("materials/gui/ttt/icon_defi_necro.vmt")
end

local DEFI_IDLE = 0
local DEFI_BUSY = 1
local DEFI_CHARGE = 2

local DEFI_ERROR_NO_SPACE = 1
local DEFI_ERROR_TOO_FAST = 2
local DEFI_ERROR_LOST_TARGET = 3
local DEFI_ERROR_NO_VALID_PLY = 4
local DEFI_ERROR_ALREADY_REVIVING = 5
local DEFI_ERROR_FAILED = 6
local DEFI_ERROR_ZOMBIE = 7
local DEFI_ERROR_PLAYER_ALIVE = 8

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.ViewModelFOV = 78
	SWEP.DrawCrosshair = false
	SWEP.ViewModelFlip = false

	SWEP.EquipMenuData = {
		type = "item_weapon",
		name = "necro_defi_name",
		desc = "necro_defi_desc"
	}

	SWEP.Icon = "vgui/ttt/icon_defi_necro"
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = nil
SWEP.notBuyable = true

SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/v_c4.mdl"
SWEP.WorldModel = "models/weapons/w_c4.mdl"

SWEP.AutoSpawnable = false
SWEP.NoSights = true

SWEP.HoldType = "pistol"
SWEP.LimitedStock = true

SWEP.Primary.Recoil = 0
SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 1
SWEP.Primary.Ammo = "none"

SWEP.Secondary.Recoil = 0
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 0.5

SWEP.Charge = 0
SWEP.Timer = -1

SWEP.AllowDrop = false

if SERVER then
	util.AddNetworkString("RequestNecroRevivalStatus")
	util.AddNetworkString("ReceiveNecroRevivalStatus")

	function SWEP:OnDrop()
		self.BaseClass.OnDrop(self)

		self:CancelRevival()
		self:Remove()
	end

	function SWEP:SetState(state)
		self:SetNWInt("defi_state", state or DEFI_IDLE)
	end

	function SWEP:Reset()
		self:SetState(DEFI_IDLE)

		self.defiTarget = nil
		self.defiBone = nil
		self.defiStart = 0

		self.defiTimer = nil
	end

	function SWEP:Error(type)
		self:SetState(DEFI_CHARGE)

		self.defiTarget = nil
		self.defiTimer = "defi_reset_timer_" .. self:EntIndex()

		if timer.Exists(self.defiTimer) then return end

		timer.Create(self.defiTimer, GetConVar("ttt2_necrodefi_error_time"):GetFloat(), 1, function()
			if not IsValid(self) then return end

			self:Reset()
		end)

		self:Message(type)
	end

	function SWEP:Message(type)
		local owner = self:GetOwner()

		if type == DEFI_ERROR_NO_SPACE then
			LANG.Msg(owner, "necrodefi_error_no_space", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_TOO_FAST then
			LANG.Msg(owner, "necrodefi_error_too_fast", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_LOST_TARGET then
			LANG.Msg(owner, "necrodefi_error_lost_target", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_NO_VALID_PLY then
			LANG.Msg(owner, "necrodefi_error_no_valid_ply", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_ALREADY_REVIVING then
			LANG.Msg(owner, "necrodefi_error_already_reviving", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_FAILED then
			LANG.Msg(owner, "necrodefi_error_failed", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_ZOMBIE then
			LANG.Msg(owner, "necrodefi_error_zombie", nil, MSG_MSTACK_WARN)
		elseif type == DEFI_ERROR_PLAYER_ALIVE then
			LANG.Msg(owner, "necrodefi_error_player_alive", nil, MSG_MSTACK_WARN)
		end
	end

	function SWEP:BeginRevival(ragdoll, bone)
		local ply = CORPSE.GetPlayer(ragdoll)
		local owner = self:GetOwner()

		if not IsValid(ply) then
			self:Error(DEFI_ERROR_NO_VALID_PLY)

			return
		end

		if ply:IsReviving() then
			self:Error(DEFI_ERROR_ALREADY_REVIVING)

			return
		end

		if ply:IsActive() and not (SpecDM and not ply:IsGhost()) then
			self:Error(DEFI_ERROR_PLAYER_ALIVE)

			return
		end

		local reviveTime = GetConVar("ttt2_necrodefi_revive_time"):GetFloat()

		self:SetState(DEFI_BUSY)
		self:SetStartTime(CurTime())
		self:SetReviveTime(reviveTime)

		-- start revival
		ply:Revive(
			reviveTime,
			function(p)
				AddZombie(p, owner)
			end,
			function(p)
				return not p:IsActive() or (SpecDM and p:IsGhost())
			end,
			true,
			REVIVAL_BLOCK_ALL
		)
		ply:SendRevivalReason("revived_by_necromancer", {name = self:GetOwner():Nick()})

		self.defiTarget = ragdoll
		self.defiBone = bone
	end

	function SWEP:FinishRevival()
		self:Reset()

		self:SetClip1(self:Clip1() - 1)

		if self:Clip1() < 1 then
			self:Remove()

			RunConsoleCommand("lastinv")
		end
	end

	function SWEP:CancelRevival()
		local ply = CORPSE.GetPlayer(self.defiTarget)

		self:Reset()

		if not IsValid(ply) then return end

		ply:CancelRevival()
		ply:SendRevivalReason(nil)
	end

	function SWEP:SetStartTime(time)
		self:SetNWFloat("defi_start_time", time or 0)
	end

	function SWEP:SetReviveTime(time)
		self:SetNWFloat("defi_revive_time", time or 0)
	end

	function SWEP:Think()
		if self:GetState() ~= DEFI_BUSY then return end

		local owner = self:GetOwner()
		local target = CORPSE.GetPlayer(self.defiTarget)

		if CurTime() >= self:GetStartTime() + GetConVar("ttt2_necrodefi_revive_time"):GetFloat() - 0.01 then
			self:FinishRevival()
		elseif not owner:KeyDown(IN_ATTACK) or owner:GetEyeTrace(MASK_SHOT_HULL).Entity ~= self.defiTarget then
			self:CancelRevival()
			self:Error(DEFI_ERROR_LOST_TARGET)
		elseif target:IsActive() and not (SpecDM and not target:IsGhost()) then
			self:CancelRevival()
			self:Error(DEFI_ERROR_PLAYER_ALIVE)
		end
	end

	function SWEP:Initialize()
		local ammo = 1
		local playerAlive = 0

		local plys = player.GetAll()

		for i = 1, #plys do
			local ply = plys[i]

			if not ply:GetForceSpec() then
				playerAlive = playerAlive + 1
			end
		end

		ammo = ammo + playerAlive * GetGlobalFloat("ttt2_necrodefi_ammo", 0.34)

		if ammo > 1 then
			ammo = ammo - 1
		end

		self:SetClip1(100)
	end

	function SWEP:PrimaryAttack()
		local owner = self:GetOwner()

		local trace = owner:GetEyeTrace(MASK_SHOT_HULL)
		local distance = trace.StartPos:Distance(trace.HitPos)
		local ent = trace.Entity

		if distance > 100 or not IsValid(ent)
			or ent:GetClass() ~= "prop_ragdoll"
			or not CORPSE.IsValidBody(ent)
		then return end

		local spawnPoint = plyspawn.MakeSpawnPointSafe(CORPSE.GetPlayer(ent), ent:GetPos())

		if self:GetState() ~= DEFI_IDLE then
			self:Error(DEFI_ERROR_TOO_FAST)

			return
		end


		if not spawnPoint then
			self:Error(DEFI_ERROR_NO_SPACE)
		else
			self:BeginRevival(ent, trace.PhysicsBone)
		end
	end

	net.Receive("RequestNecroRevivalStatus", function(_, requester)
		local ply = net.ReadEntity()

		if not IsValid(ply) then return end

		net.Start("ReceiveNecroRevivalStatus")
		net.WriteEntity(ply)
		net.WriteBool(ply:IsReviving())
		net.Send(requester)
	end)
end

-- do not play sound when swep is empty
function SWEP:DryFire()
	return false
end

function SWEP:GetState()
	return self:GetNWInt("defi_state", DEFI_IDLE)
end

function SWEP:GetStartTime()
	return self:GetNWFloat("defi_start_time", 0)
end

function SWEP:GetReviveTime()
	return self:GetNWFloat("defi_revive_time", 0)
end

if CLIENT then
	function SWEP:PrimaryAttack()

	end

	local colorGreen = Color(36, 160, 30)

	local function IsPlayerReviving(ply)
		if not ply.defi_lastRequest or ply.defi_lastRequest < CurTime() + 0.3 then
			net.Start("RequestNecroRevivalStatus")
			net.WriteEntity(ply)
			net.SendToServer()

			ply.defi_lastRequest = CurTime()
		end

		return ply.defi_isReviving or false
	end

	net.Receive("ReceiveNecroRevivalStatus", function()
		local ply = net.ReadEntity()

		if not IsValid(ply) then return end

		ply.defi_isReviving = net.ReadBool()
	end)

	hook.Add("TTTRenderEntityInfo", "ttt2_necro_defibrillator_display_info", function(tData)
		local ent = tData:GetEntity()
		local client = LocalPlayer()
		local activeWeapon = client:GetActiveWeapon()

		-- has to be a ragdoll
		if ent:GetClass() ~= "prop_ragdoll" or not CORPSE.IsValidBody(ent) then return end

		-- player has to hold a defibrillator
		if not IsValid(activeWeapon) or activeWeapon:GetClass() ~= "weapon_ttth_necrodefi" then return end

		-- ent has to be in usable range
		if tData:GetEntityDistance() > 100 then return end

		if activeWeapon:GetState() == DEFI_CHARGE then
			tData:AddDescriptionLine(
				LANG.TryTranslation("necrodefi_charging"),
				COLOR_ORANGE
			)

			tData:SetOutlineColor(COLOR_ORANGE)

			return
		end

		local ply = CORPSE.GetPlayer(ent)

		if activeWeapon:GetState() ~= DEFI_BUSY and IsValid(ply) and IsPlayerReviving(ply) then
			tData:AddDescriptionLine(
				LANG.TryTranslation("necrodefi_player_already_reviving"),
				COLOR_ORANGE
			)

			tData:SetOutlineColor(COLOR_ORANGE)

			return
		end

		tData:AddDescriptionLine(
			LANG.GetParamTranslation("necrodefi_hold_key_to_revive", {key = Key("+attack", "LEFT MOUSE")}),
			colorGreen
		)

		if activeWeapon:GetState() ~= DEFI_BUSY then return end

		local progress = math.min((CurTime() - activeWeapon:GetStartTime()) / activeWeapon:GetReviveTime(), 1.0)
		local timeLeft = activeWeapon:GetReviveTime() - (CurTime() - activeWeapon:GetStartTime())

		local x = 0.5 * ScrW()
		local y = 0.5 * ScrH()
		local w, h = 0.2 * ScrW(), 0.025 * ScrH()

		y = 0.95 * y

		surface.SetDrawColor(50, 50, 50, 220)
		surface.DrawRect(x - 0.5 * w, y - h, w, h)
		surface.SetDrawColor(clr(colorGreen))
		surface.DrawOutlinedRect(x - 0.5 * w, y - h, w, h)
		surface.SetDrawColor(clr(ColorAlpha(colorGreen, (0.5 + 0.15 * math.sin(CurTime() * 4)) * 255)))
		surface.DrawRect(x - 0.5 * w + 2, y - h + 2, w * progress - 4, h - 4)

		tData:AddDescriptionLine(
			LANG.GetParamTranslation("necrodefi_revive_progress", {time = math.Round(timeLeft, 1)}),
			colorGreen
		)

		tData:SetOutlineColor(colorGreen)
	end)
end
