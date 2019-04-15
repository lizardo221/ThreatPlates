local ADDON_NAME, Addon = ...
local ThreatPlates = Addon.ThreatPlates

---------------------------------------------------------------------------------------------------
-- Imported functions and constants
---------------------------------------------------------------------------------------------------

-- Lua APIs
local pairs = pairs

-- WoW APIs
local InCombatLockdown = InCombatLockdown
local UnitPlayerControlled = UnitPlayerControlled
local UnitIsOtherPlayersPet = UnitIsOtherPlayersPet
local UnitIsBattlePet = UnitIsBattlePet
local UnitCanAttack, UnitIsTapDenied = UnitCanAttack, UnitIsTapDenied

-- ThreatPlates APIs
local TidyPlatesThreat = TidyPlatesThreat
local PlatesByUnit = Addon.PlatesByUnit
local TOTEMS = Addon.TOTEMS
local GetUnitVisibility = ThreatPlates.GetUnitVisibility
local SubscribeEvent, PublishEvent = Addon.EventService.Subscribe, Addon.EventService.Publish
local ActiveTheme = Addon.Theme

---------------------------------------------------------------------------------------------------
-- Local variables
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Element code
---------------------------------------------------------------------------------------------------
local Element = "Style"

---------------------------------------------------------------------------------------------------
-- Helper functions for styles and functions
---------------------------------------------------------------------------------------------------

local REACTION_MAPPING = {
  FRIENDLY = "Friendly",
  HOSTILE = "Enemy",
  NEUTRAL = "Neutral",
}

-- Mapping necessary - to removed it, config settings must be changed/migrated
-- Visibility        Scale / Alpha                  Threat System
local MAP_UNIT_TYPE_TO_TP_TYPE = {
  FriendlyPlayer   = "FriendlyPlayer",
  FriendlyNPC      = "FriendlyNPC",
  FriendlyTotem    = "Totem",
  FriendlyGuardian = "Guardian",
  FriendlyPet      = "Pet",
  EnemyPlayer      = "EnemyPlayer",
  EnemyNPC         = "EnemyNPC", -- / Boss / Elite = Normal / Boss / Elite
  EnemyTotem       = "Totem",
  EnemyGuardian    = "Guardian",
  EnemyPet         = "Pet",
  EnemyMinus       = "Minus", --                   = Minus
  NeutralNPC       = "Neutral", --                 = Neutral
  NeutralGuardian  = "Guardian",
  NeutralMinus     = "Minus" --                    = Minus
  --                  Tapped                       = Tapped
}

--local function GetUnitType(unit)
--  local faction = REACTION_MAPPING[unit.reaction]
--  local unit_class
--
--  -- not all combinations are possible in the game: Friendly Minus, Neutral Player/Totem/Pet
--  if unit.type == "PLAYER" then
--    unit_class = "Player"
--    unit.TP_DetailedUnitType = faction .. "Player"
--  elseif unit.TotemSettings then
--    unit_class = "Totem"
--    unit.TP_DetailedUnitType = "Totem"
--  elseif UnitIsOtherPlayersPet(unit.unitid) then -- player pets are also considered guardians, so this check has priority
--    unit_class = "Pet"
--    unit.TP_DetailedUnitType = "Pet"
--  elseif UnitPlayerControlled(unit.unitid) then
--    unit_class = "Guardian"
--    unit.TP_DetailedUnitType = "Guardian"
--  elseif unit.isMini then
--    unit_class = "Minus"
--    unit.TP_DetailedUnitType = "Minus"
--  else
--    unit_class = "NPC"
--    unit.TP_DetailedUnitType = (faction == "Neutral" and "Neutral") or (faction .. unit_class)
--  end
--
--  return faction, unit_class
--end

local function GetUnitType(unit)
  local faction = REACTION_MAPPING[unit.reaction]
  local unit_class

  -- not all combinations are possible in the game: Friendly Minus, Neutral Player/Totem/Pet
  if unit.type == "PLAYER" then
    unit_class = "Player"
  elseif unit.TotemSettings then
    unit_class = "Totem"
  elseif UnitIsOtherPlayersPet(unit.unitid) then -- player pets are also considered guardians, so this check has priority
    unit_class = "Pet"
  elseif UnitPlayerControlled(unit.unitid) then
    unit_class = "Guardian"
  elseif unit.isMini then
    unit_class = "Minus"
  else
    unit_class = "NPC"
  end

  unit.TP_DetailedUnitType = MAP_UNIT_TYPE_TO_TP_TYPE[faction .. unit_class]

  if unit.TP_DetailedUnitType == "EnemyNPC" then
    unit.TP_DetailedUnitType = (unit.isBoss and "Boss") or (unit.isElite and "Elite") or unit.TP_DetailedUnitType
  end

  if UnitIsTapDenied(unit.unitid) then
    unit.TP_DetailedUnitType = "Tapped"
  end

  return faction .. unit_class
end

local function ShowUnit(unit)
  -- If nameplate visibility is controlled by Wow itself (configured via CVars), this function is never used as
  -- nameplates aren't created in the first place (e.g. friendly NPCs, totems, guardians, pets, ...)
  local unit_type = GetUnitType(unit)
  local show, headline_view = GetUnitVisibility(unit_type)

  if not show then return false end

  local e, b, t = (unit.isElite or unit.isRare), unit.isBoss, UnitIsTapDenied(unit.unitid)
  local db_base = TidyPlatesThreat.db.profile
  local db = db_base.Visibility

  if (e and db.HideElite) or (b and db.HideBoss) or (t and db.HideTapped) then
    return false
  elseif db.HideNormal and not (e or b) then
    return false
  elseif UnitIsBattlePet(unit.unitid) then
    -- TODO: add configuration option for enable/disable
    return false
  elseif db.HideFriendlyInCombat and unit.reaction == "FRIENDLY" and InCombatLockdown() then
    return false
  end

--  if full_unit_type == "EnemyNPC" then
--    if b then
--      unit.TP_DetailedUnitType = "Boss"
--    elseif e then
--      unit.TP_DetailedUnitType = "Elite"
--    end
--  end

--  if t then
--    --unit.TP_DetailedUnitType = "Tapped"
--    show = not db.HideTapped
--  end

  db = db_base.HeadlineView
  if db.ForceHealthbarOnTarget and unit.isTarget then
    headline_view = false
  elseif db.ForceOutOfCombat and not InCombatLockdown() then
    headline_view = true
  elseif db.ForceNonAttackableUnits and unit.reaction ~= "FRIENDLY" and not UnitCanAttack("player", unit.unitid) then
    headline_view = true
  elseif unit.reaction == "FRIENDLY" and InCombatLockdown() then
    if db.ForceFriendlyInCombat == "NAME" then
      headline_view = true
    elseif db.ForceFriendlyInCombat == "HEALTHBAR" then
      headline_view = false
    end
  end

  return show, headline_view
end

-- Returns style based on threat (currently checks for in combat, should not do hat)
function Addon:GetThreatStyle(unit)
  -- style tank/dps only used for NPCs/non-player units
  if Addon:ShowThreatFeedback(unit) then
      return (Addon.PlayerRoleIsTank and "tank") or "dps"
  end

  return "normal"
end

-- Check if a unit is a totem or a custom nameplates (e.g., after UNIT_NAME_UPDATE)
-- Depends on:
--   * unit.name
local function UnitStyle_NameDependent(unit)
  local plate_style

  local db = TidyPlatesThreat.db.profile

  local totem_settings
  local unique_settings = db.uniqueSettings.map[unit.name]
  if unique_settings and unique_settings.useStyle then
    plate_style = (unique_settings.showNameplate and "unique") or (unique_settings.ShowHeadlineView and "NameOnly-Unique") or "etotem"
  else
    local totem_id = TOTEMS[unit.name]
    if totem_id then
      totem_settings = db.totemSettings[totem_id]
      if totem_settings.ShowNameplate then
        plate_style = (db.totemSettings.hideHealthbar and "etotem") or "totem"
      else
        plate_style = "empty"
      end
    end
  end

  -- Set these values to nil if not custom nameplate or totem
  unit.CustomPlateSettings = unique_settings
  unit.TotemSettings = totem_settings

  return plate_style
end

-- Depends on:
--   * unit.reaction
--   * unit.name
--   * unit.type
--   * unit.classification
--   * unit.isBoss, isRare, isElite, isMini
--   * unit.isTapped
--   * UnitReaction
--   * UnitThreatSituation
--   * UnitIsTapDenied
--   * UnitIsOtherPlayersPet
--   * UnitPlayerControlled
--   ...
function Addon:SetStyle(unit)
  local show, headline_view = ShowUnit(unit)

  if not show then
    return "empty", nil
  end

  -- Check if custom nameplate should be used for the unit:
  local style = UnitStyle_NameDependent(unit) or (headline_view and "NameOnly")

  --if not style and unit.reaction ~= "FRIENDLY" then
  if not style and Addon:ShowThreatFeedback(unit) then
    -- could call GetThreatStyle here, but that would at a tiny overhead
    -- style tank/dps only used for hostile (enemy, neutral) NPCs
    style = (Addon.PlayerRoleIsTank and "tank") or "dps"
  end

  return style or "normal"
end

local NAMEPLATE_STYLES_BY_THEME = {
  dps = "HEALTHBAR",
  tank = "HEALTHBAR",
  normal = "HEALTHBAR",
  totem = "HEALTHBAR",
  unique = "HEALTHBAR",
  empty = "NONE",
  etotem = "NONE",
  NameOnly = "NAME",
  ["NameOnly-Unique"] = "NAME",
}

local function CheckNameplateStyle(tp_frame)
  local unit = tp_frame.unit

  local stylename = Addon:SetStyle(unit)

  if tp_frame.stylename ~= stylename then
    local style = ActiveTheme[stylename]

    tp_frame.PlateStyle = NAMEPLATE_STYLES_BY_THEME[stylename]
    tp_frame.stylename = stylename
    tp_frame.style = style
    unit.style = stylename

    PublishEvent("StyleUpdate", tp_frame, style, stylename)
  end
end

local function UNIT_NAME_UPDATE(unitid)
  local tp_frame = PlatesByUnit[unitid]
  if tp_frame and tp_frame.Active then
    local stylename = UnitStyle_NameDependent(tp_frame.unit)

    if stylename and tp_frame.stylename ~= stylename then
      local style = ActiveTheme[stylename]

      tp_frame.PlateStyle = NAMEPLATE_STYLES_BY_THEME[stylename]
      tp_frame.stylename = stylename
      tp_frame.style = style
      tp_frame.unit.style = stylename

      tp_frame.PlateStyle = ((stylename == "NameOnly" or stylename == "NameOnly-Unique") and "NAME") or "HEALTHBAR"


      PublishEvent("StyleUpdate", tp_frame, style, stylename)
    end
  end
end

local function EnteringOrLeavingCombat()
  for _, tp_frame in pairs(PlatesByUnit) do
    if tp_frame.Active then
      CheckNameplateStyle(tp_frame)
    end
  end
  --  local tp_frame
  --  for plate, _ in pairs(PlatesVisible) do
  --    tp_frame = plate.TPFrame
  --    print ("Combat ended ", tp_frame.unit.unitid, "-", tp_frame.unit.InCombat)
  --    if tp_frame.unit.InCombat then
  --      PublishEvent("CombatEnded", tp_frame)
  --    end
  --  end

end

Addon.InitializeStyle = CheckNameplateStyle

SubscribeEvent(Element, "FactionUpdate", CheckNameplateStyle)
SubscribeEvent(Element, "ThreatUpdate", CheckNameplateStyle)
SubscribeEvent(Element, "UNIT_NAME_UPDATE", UNIT_NAME_UPDATE)
SubscribeEvent(Element, "PLAYER_REGEN_ENABLED", EnteringOrLeavingCombat)
SubscribeEvent(Element, "PLAYER_REGEN_DISABLED", EnteringOrLeavingCombat)