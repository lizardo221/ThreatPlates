---------------------------------------------------------------------------------------------------
-- Auras Widget
---------------------------------------------------------------------------------------------------
local ADDON_NAME, Addon = ...
local ThreatPlates = Addon.ThreatPlates

local Widget = Addon.Widgets:NewWidget("Auras")

---------------------------------------------------------------------------------------------------
-- Imported functions and constants
---------------------------------------------------------------------------------------------------

-- Lua APIs
local GetTime = GetTime
local pairs = pairs
local floor, ceil, min = floor, ceil, min
local sort = sort
local tonumber = tonumber

-- WoW APIs
local GetFramerate = GetFramerate
local DebuffTypeColor = DebuffTypeColor
local UnitAuraWrapper, UnitIsUnit, UnitReaction = UnitAura, UnitIsUnit, UnitReaction
local GetNamePlates, GetNamePlateForUnit = C_NamePlate.GetNamePlates, C_NamePlate.GetNamePlateForUnit
local IsInInstance = IsInInstance

-- ThreatPlates APIs
local TidyPlatesThreat = TidyPlatesThreat
local Animations = Addon.Animations
local Font = Addon.Font
local UpdateCustomStyleAfterAuraTrigger = Addon.UpdateCustomStyleAfterAuraTrigger
local UnitStyle_AuraDependent = Addon.UnitStyle_AuraDependent
local CUSTOM_GLOW_FUNCTIONS, CUSTOM_GLOW_WRAPPER_FUNCTIONS = Addon.CUSTOM_GLOW_FUNCTIONS, Addon.CUSTOM_GLOW_WRAPPER_FUNCTIONS
local BackdropTemplate = Addon.BackdropTemplate
local MODE_FOR_STYLE, ANCHOR_POINT_TEXT = Addon.MODE_FOR_STYLE, Addon.ANCHOR_POINT_TEXT

local _G =_G
-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
-- GLOBALS: CreateFrame, UnitAffectingCombat

---------------------------------------------------------------------------------------------------
-- Auras Widget Functions
---------------------------------------------------------------------------------------------------

local AuraTooltip = CreateFrame("GameTooltip", "ThreatPlatesAuraTooltip", UIParent, "GameTooltipTemplate")

local GRID_LAYOUT = {
  LEFT = {
    BOTTOM =  { "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT"   ,    1,  1},
    TOP    =  { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT",    "BOTTOMLEFT",    1, -1},
  },
  RIGHT = {
    BOTTOM =  { "BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOPRIGHT",    -1,  1},
    TOP    =  { "TOPRIGHT"   , "TOPLEFT",    "TOPRIGHT",    "BOTTOMRIGHT", -1, -1},
  },
}

Widget.TEXTURE_BORDER = Addon.ADDON_DIRECTORY .. "Artwork\\squareline"

-- Debuffs are color coded, with poison debuffs having a green border, magic debuffs a blue border, diseases a brown border,
-- urses a purple border, and physical debuffs a red border
Widget.AURA_TYPE = { Curse = 1, Disease = 2, Magic = 3, Poison = 4, }

local FLASH_DURATION = Addon.Animations.FLASH_DURATION
Widget.ANCHOR_POINT_SETPOINT = Addon.ANCHOR_POINT_SETPOINT
Widget.PRIORITY_FUNCTIONS = {
  None = function(aura) return 0 end,
  AtoZ = function(aura) return aura.name end,
  TimeLeft = function(aura) return aura.expiration - GetTime() end,
  Duration = function(aura) return aura.duration end,
  Creation = function(aura) return aura.expiration - aura.duration end,
}
Widget.UnitAuraList = {}

-- Aura Grids
local AURA_GRID_BUFFS, AURA_GRID_DEBUFFS, AURA_GRID_CROWDCONTROL = "Buffs", "Debuffs", "CrowdControl"
Widget.Buffs = {
  CenterAurasPositions = {},
}
Widget.Debuffs = {
  CenterAurasPositions = {}
}
Widget.CrowdControl = {
  CenterAurasPositions = {}
}

local LOC_CHARM = 1         -- Aura: Possess
local LOC_FEAR = 2          -- Mechanic: Fleeing
local LOC_POLYMORPH = 3     -- Aura: Change Model,
local LOC_STUN = 4          -- Aura: Stun
local LOC_INCAPACITATE = 5
local LOC_SLEEP = 6         -- Mechanic: Asleep
local LOC_DISORIENT = 7     -- Aura: Confuse
local LOC_BANISH = 8
local LOC_HORROR = 9

-- Polymorph: Aura: Pacify & Silence
-- Hex: Aura: Confuse

local PC_SNARE = 50         -- Mechanic: Snared
local PC_ROOT = 51          -- Mechanic: Rooted
local PC_DAZE = 52
local PC_GRIP = 53
local PC_DISARM = 54        -- Apply Aura: Disarm
local PC_PUSHBACK = 55      -- Apply Aura: Disarm
local PC_MODAGGRORANGE = 56 -- Apply Aura: Mod Aggro Range

local CC_SILENCE = 101

local CROWD_CONTROL_SPELLS_RETAIL = {
  ---------------------------------------------------------------------------------------------------
  -- Druid
  ---------------------------------------------------------------------------------------------------

  [339] = PC_ROOT,                -- Entangling Roots
  [5211] = LOC_STUN,              -- Mighty Bash (Talent)
  [61391] = PC_DAZE,              -- Typhoon (Talent)
  [102359] = PC_ROOT,             -- Mass Entanglement (Talent)
  [2637] = LOC_SLEEP,             -- Hibernate
  [45334] = LOC_SLEEP,            -- Immobilized from Wild Charge (Bear) (Blizzard)
  [50259] = LOC_SLEEP,            -- Dazed from Wild Charge (Cat)
  [81261] = CC_SILENCE,           -- Solar Beam
  [209753] = LOC_BANISH,          -- Cyclone (Honor)
  [209749] = PC_DISARM,           -- Faerie Swarm (Honor) & PC_SNARE
  [163505] = LOC_STUN,            -- Rake
  [203123] = LOC_STUN,            -- Maim
  [99] = LOC_INCAPACITATE,        -- Incapacitating Roar
  [202244] = LOC_INCAPACITATE,    -- Overrun (Honor)
  [127797] = PC_DAZE,             -- Ursol's Vortex
  [33786] = LOC_BANISH,           -- Cyclone (Honor)

  ---------------------------------------------------------------------------------------------------
  -- Death Knight
  ---------------------------------------------------------------------------------------------------

  [273977] = PC_SNARE,            -- Grip of the Dead (Talent)
  [45524] = PC_SNARE,             -- Chains of Ictggtse
  [111673] = LOC_CHARM,           -- Control Undead
  --[77606] = LOC_CHARM,            -- Dark Simulacrum (Honor) -- no CC aura
  [221562] = LOC_STUN,            -- Asphyxiate (Blood, Blizzard)
  [47476] = CC_SILENCE,           -- Strangulate (Honor)
  [108194] = LOC_STUN,            -- Asphyxiate (Unholy/Frost, Blizzard)
  [207167] = LOC_DISORIENT,       -- Blinding Sleet (Talent, Blizzard)
  [204085] = PC_ROOT,             -- Deathchill (Honor)
  [204206] = PC_SNARE,            -- Chilled from Chill Streasek (Honor)
  [233395] = PC_ROOT,             -- Frozen Center (Honor)
  [279303] = PC_SNARE,            -- Frost Breath from Frostwyrm's Fury (Talent)
  --[211793] = PC_SNARE,            -- Remorseless Winter - not shown because uptime to high
  [200646] = PC_SNARE,            -- Unholy Mutation (Honor)

  ---------------------------------------------------------------------------------------------------
  -- Demon Hunter
  ---------------------------------------------------------------------------------------------------

  [217832] = LOC_INCAPACITATE,     -- Imprison (Blizzard)
  [221527] = LOC_INCAPACITATE,     -- Imprison with PvP talent Detainment (Blizzard)
  [207685] = LOC_DISORIENT,        -- Sigil of Misery (Blizzard)
  [204490] = CC_SILENCE,           -- Sigil of Silence (Blizzard)
  [204843] = PC_SNARE,             -- Sigil of Chains
  [205630] = LOC_STUN,             -- Illidan's Grasp
  [208618] = LOC_STUN,             -- Illidan's Grasp Stun
  [179057] = LOC_STUN,             -- Chaos Nova (Blizzard)
  [200166] = LOC_STUN,             -- Metamorphosis (Blizzard)
  [198813] = PC_SNARE,             -- Vengeful Retreat
  [213405] = PC_SNARE,             -- Master of the Glaive (Talent)
  [211881] = LOC_STUN,             -- Fel Eruption (Talent, Blizzard)

  ---------------------------------------------------------------------------------------------------
  -- Hunter
  ---------------------------------------------------------------------------------------------------

  [5116] = PC_DAZE,             -- Concussive Shot
  [3355] = LOC_INCAPACITATE,    -- Freezing Trap (Blizzard)
  [24394] = LOC_STUN,           -- Intimidation (Blizzard)
  [117405] = PC_ROOT,           -- Binding Shot
  [202914] = CC_SILENCE,        -- Spider Sting (Honor)
  [135299] = PC_SNARE,          -- Tar Trap (Honor)
  --[147362] = CC_SILENCE,        -- Counter Shot
  [213691] = LOC_INCAPACITATE,  -- Scatter Shot (Honor)
  [186387] = PC_SNARE,          -- Bursting Shot
  [162480] = LOC_INCAPACITATE,  -- Steel Trap (Blizzard)
  [212638] = PC_ROOT,           -- Tracker's Net
  [190927] = PC_ROOT,           -- Harpoon
  [195645] = PC_SNARE,          -- Wing Clip
  [203337] = LOC_INCAPACITATE,  -- Freezing Trap with Diamond Ice
  --[187707] = CC_SILENCE,        -- Muzzle

  ---------------------------------------------------------------------------------------------------
  -- Mage
  ---------------------------------------------------------------------------------------------------

  [61780] = LOC_POLYMORPH,  -- Polymorph (Turkey)
  [161353] = LOC_POLYMORPH, -- Polymorph (Polar Bear Cub)
  [28272] = LOC_POLYMORPH,  -- Polymorph (Pig)
  [28271] = LOC_POLYMORPH,  -- Polymorph (Turtle)
  [161354] = LOC_POLYMORPH, -- Polymorph (Monkey)
  [118] = LOC_POLYMORPH,    -- Polymorph (Sheep)
  [126819] = LOC_POLYMORPH, -- Polymorph (Porcupine)
  [61305] = LOC_POLYMORPH,  -- Polymorph (Black Cat)
  [61721] = LOC_POLYMORPH,  -- Polymorph (Rabbit)
  [161372] = LOC_POLYMORPH, -- Polymorph (Peacock)
  [161355] = LOC_POLYMORPH, -- Polymorph (Penguin)
  [277787] = LOC_POLYMORPH, -- Polymorph (Direhorn)
  [277792] = LOC_POLYMORPH, -- Polymorph (Bumblebee)
  -- [2139] = CC_SILENCE,      -- Counterspell -- does not leave a debuff on target
  [122] = PC_ROOT,          -- Frost Nova (Blizzard)
  [82691] = LOC_STUN,       -- Ring of Frost (Talent, Blizzard)
  [31589] = PC_SNARE,       -- Slow
  [236299] = PC_SNARE,      -- Arcane Barrage with Chrono Shift (Talent)
  [31661] = LOC_DISORIENT,  -- Dragon's Breath (Blizzard)
  [2120] = PC_SNARE,        -- Flamestrike
  [157981] = PC_SNARE,      -- Blast Wave (Talent)
  -- [205708] = PC_SNARE,      -- Chilled
  [33395] = PC_ROOT,        -- Freeze (Blizzard)
  [212792] = PC_SNARE,      -- Cone of Cold
  [157997] = PC_ROOT,       -- Ice Nova (Talent)
  [228600] = PC_ROOT,       -- Glacial Spike (Talent, Blizzard)

  ---------------------------------------------------------------------------------------------------
  -- Paladin
  ---------------------------------------------------------------------------------------------------

  [20066] = LOC_INCAPACITATE,   -- Repentance (Blizzard)
  [853] = LOC_STUN,             -- Hammer of Justice (Blizzard)
  [105421] = LOC_DISORIENT,     -- Blinding Light (Blizzard)
  --[96231] = CC_SILENCE,       -- Rebuke
  [31935] = CC_SILENCE,         -- Avenger's Shield (Blizzard)
  [217824] = CC_SILENCE,        -- Shield of Virtue
  --[204242] = PC_SNARE,        -- Consecrated Ground - same aura as Consecration
  -- [205273] = PC_SNARE,       -- Wake of Ashes - from Artefact weapon
  [255937] = PC_SNARE,          -- Wake of Ashes - Talent
  [183218] = PC_SNARE,          -- Hand of Hindrance
  [10326] = LOC_FEAR,           -- Turn Evil

  ---------------------------------------------------------------------------------------------------
  -- Priest
  ---------------------------------------------------------------------------------------------------

  [8122] = LOC_FEAR,            -- Psychic Scream (Blizzard)
  [605] = LOC_CHARM,            -- Mind Control (Blizzard)
  [204263] = PC_SNARE,          -- Shining Force
  [9484] = LOC_POLYMORPH,       -- Shackle Undead (Blizzard)
  [200200] = LOC_STUN,          -- Censure for Holy Word: Chastise
  [200196] = LOC_INCAPACITATE,  -- Holy Word: Chastise (Blizzard)
  [205369] = LOC_STUN,          -- Mind Bomb (Blizzard)
  [15487] = CC_SILENCE,         -- Silence (Blizzard)
  [64044] = LOC_STUN,           -- Psychic Horror (Blizzard)
  --[15407] = PC_SNARE,           -- Mind Flay - not shown as very high uptime
  [87204] = LOC_FEAR,           -- Sin and Punishment, fear effect after dispell of Vampiric Touch ?87204

  ---------------------------------------------------------------------------------------------------
  -- Rogue
  ---------------------------------------------------------------------------------------------------

  [1833] = LOC_STUN,       -- Cheap Shot (Blizzard)
  [6770] = LOC_STUN,       -- Sap (Blizzard)
  [2094] = LOC_DISORIENT,  -- Blind
  [408] = LOC_STUN,        -- Kidney Shot (Blizzard)
  [212183] = LOC_STUN,     -- Smoke Bomb (Honor)
  [248744] = PC_SNARE,     -- Shiv (Honor)
  [1330] = CC_SILENCE,     -- Garrote (Blizzard)
  -- [3409] = LOC_STUN,    -- Crippling Poison - Not shown as 100% uptime
  [207777] = PC_DISARM,    -- Dismantle (Honor)
  [1776] = LOC_STUN,       -- Gouge (Blizzard)
  [185763] = PC_SNARE,     -- Pistol Shot
  [199804] = LOC_STUN,     -- Between the Eyes (Blizzard)
  [206760] = PC_SNARE,     -- Night Terrors

  ---------------------------------------------------------------------------------------------------
  -- Shaman
  ---------------------------------------------------------------------------------------------------

  [51514] = LOC_POLYMORPH,      -- Hex (Frog) (Blizzard)
  [210873] = LOC_POLYMORPH,     -- Hex (Compy) (Blizzard)
  [211004] = LOC_POLYMORPH,     -- Hex (Spider) (Blizzard)
  [211010] = LOC_POLYMORPH,     -- Hex (Snake) (Blizzard)
  [211015] = LOC_POLYMORPH,     -- Hex (Cockroach) (Blizzard)
  [269352] = LOC_POLYMORPH,     -- Hex (Skeletal Hatchling) (Blizzard)
  [277778] = LOC_POLYMORPH,     -- Hex (Zandalari Tendonripper) (Blizzard)
  [277784] = LOC_POLYMORPH,     -- Hex (Wicker Mongrel) (Blizzard)
  [118905] = LOC_STUN,          -- Static Charge from Capacitor Totem
  -- [57994] = CC_SILENCE,         -- Wind Shear
  [3600] = PC_SNARE,            -- Earthbind Totem
  [51490] = PC_SNARE,           -- Thunderstorm
  [204399] = LOC_STUN,          -- Stun aura from Earthfury (Honor)
  [196840] = PC_SNARE,          -- Frost Shock
  [204437] = LOC_STUN,          -- Lightning Lasso (Honor)
  -- [196834] = PC_SNARE,          -- Frostbrand - Not shown as ability is part of the rotation
  [197214] = LOC_INCAPACITATE,  -- Sundering
  -- [197385] = PC_SNARE,          -- Fury of Air - Not shown as too much uptime
  [64695] = PC_ROOT,            -- Earthgrab Totem (Blizzard)

  ---------------------------------------------------------------------------------------------------
  -- Warlock
  ---------------------------------------------------------------------------------------------------

  [6789] = LOC_INCAPACITATE,  -- Mortal Coil (Blizzard)s
  [118699] = LOC_FEAR,        -- Fear (Blizzard)
  [710] = LOC_BANISH,         -- Banish (Blizzard)
  [30283] = LOC_STUN,         -- Shadowfury (Blizzard)
  -- [19647] = LOC_STUN,         -- Spell Lock aura from Call Felhunter
  [1098] = LOC_CHARM,         -- Enslave Demon
  [6358] = LOC_DISORIENT,     -- Seduction from Command Demon (Apply Aura: Stun) (Blizzard)
  [278350] = PC_SNARE,        -- Vile Taint
  [196364] = CC_SILENCE,      -- Unstable Affliction, silence effect after dispell of Unstable Affliction
  [213688] = LOC_STUN,        -- Fel Cleave aura from Call Fel Lord (Honor)
  [233582] = PC_SNARE,        -- Entrenched in Flame
  [5484] = LOC_FEAR,          -- Howl of Terror

  ---------------------------------------------------------------------------------------------------
  -- Warrior
  ---------------------------------------------------------------------------------------------------

  [105771] = PC_ROOT,       -- Intercept - Charge
  [5246] = LOC_FEAR,        -- Intimidating Shout (Blizzard)
  [132169] = LOC_STUN,      -- Storm Bolt (Talent, Blizzard)
  --[6552] = CC_SILENCE,      -- Pummel -- does not leave a debuff on target
  [1715] = PC_SNARE,        -- Hamstring
  [236077] = PC_DISARM,      -- Disarm (PvP)
  [12323] = PC_SNARE,       -- Piercing Howl
  [132168] = LOC_STUN,      -- Shockwave (Blizzard)
  [118000] = LOC_STUN,      -- Dragon Roar (Talent, Blizzard)
  -- [6343] = PC_SNARE,        -- Thunder Clap
  -- [199042] = LOC_STUN,      -- Thunderstruck (PvP, Blizzard) -- Removed as CC as its uptime is to high.
  [199085] = LOC_STUN,      -- Warpath (PvP, Blizzard)

  ---------------------------------------------------------------------------------------------------
  -- Monk
  ---------------------------------------------------------------------------------------------------

  -- [116189] = PC_SNARE,      -- Provoke
  [115078] = LOC_STUN,      -- Paralysis (Blizzard)se
  -- [116705] = CC_SILENCE,    -- Spear Hand Strike
  [119381] = LOC_STUN,      -- Leg Sweep (Blizzard)
  [233759] = PC_DISARM,     -- Grapple Weapon
  -- [121253] = PC_SNARE,      -- Keg Smash - not shown as high uptime
  -- [196733] = PC_SNARE,      -- Special Delivery - not shown as high uptime
  [202274] = LOC_DISORIENT, -- Incendiary Brew from Incendiary Breath
  [202346] = LOC_STUN,      -- Double Barrel
  [198909] = LOC_DISORIENT, -- Song of Chi-Ji (Blizzard)
  [116095] = PC_SNARE,      -- Disable
  [123586] = PC_SNARE,      -- Flying Serpent Kick

  ---------------------------------------------------------------------------------------------------
  -- Racial Traits
  ---------------------------------------------------------------------------------------------------
  [255723] = LOC_STUN,      -- Bull Rush (Highmountain Tauren)
  [20549] = LOC_STUN,       -- War Stomp (Tauren)
  [260369] = PC_SNARE,      -- Arcane Pulse (Nightborne)
  [107079] = LOC_STUN,      -- Quaking Palm (Pandarian)
}

local CROWD_CONTROL_SPELLS_TBC_CLASSIC = {
  ---------------------------------------------------------------------------------------------------
  -- Druid
  ---------------------------------------------------------------------------------------------------

  [5211] = LOC_STUN,                       -- Bash
    [6798] = LOC_STUN,                       -- Rank 2
    [8983] = LOC_STUN,                       -- Rank 3
  [339] = PC_ROOT,                         -- Entangling Roots
    [1062] = PC_ROOT,                        -- Rank 2
    [5195] = PC_ROOT,                        -- Rank 3
    [5196] = PC_ROOT,                        -- Rank 4
    [9852] = PC_ROOT,                        -- Rank 5
    [9853] = PC_ROOT,                        -- Rank 6
    [26989] = PC_ROOT,                       -- Rank 7
  [19975] = PC_ROOT,                       -- Entangling Roots - Triggered By: Nature's Grasp
    [19974] = PC_ROOT,                       -- Rank 2
    [19973] = PC_ROOT,                       -- Rank 3
    [19972] = PC_ROOT,                       -- Rank 4
    [19971] = PC_ROOT,                       -- Rank 5
    [19970] = PC_ROOT,                       -- Rank 6
    [27010] = PC_ROOT,                       -- Rank 7
  [19675] = PC_ROOT,                       -- Feral Charge Effect - Triggered By: Feral Charge
  [45334] = PC_ROOT,                       -- Feral Charge Effect - Triggered By: Feral Charge
  [2637] = LOC_SLEEP,                      -- Hibernate
    [18657] = LOC_SLEEP,                     -- Rank 2
    [18658] = LOC_SLEEP,                     -- Rank 3
  [9005] = LOC_STUN,                       -- Pounce
    [9823] = LOC_STUN,                       -- Rank 2
    [9827] = LOC_STUN,                       -- Rank 3
    [27006] = LOC_STUN,                      -- Rank 4
  [2908] = PC_MODAGGRORANGE,               -- Soothe Animal
    [8955] = PC_MODAGGRORANGE,               -- Rank 2
    [9901] = PC_MODAGGRORANGE,               -- Rank 3
    [26995] = PC_MODAGGRORANGE,              -- Rank 3
  [16922] = LOC_STUN,                      -- Starfire Stun - Triggered By: Improved Starfire
  [33786] = LOC_BANISH,                    -- Cyclone


  ---------------------------------------------------------------------------------------------------
  -- Hunter
  ---------------------------------------------------------------------------------------------------

  [25999] = PC_ROOT,                       -- Boar Charge - Triggered By: Charge
  [7922] = LOC_STUN,                       -- Charge Stun - Triggered By: Charge
  [5116] = PC_SNARE,                       -- Concussive Shot
  [19306] = PC_ROOT,                       -- Counterattack
    [20909] = PC_ROOT,                       -- Rank 2
    [20910] = PC_ROOT,                       -- Rank 3
    [27067] = PC_ROOT,                       -- Rank 4
  [19185] = PC_ROOT,                       -- Entrapment - Triggered By: Entrapment
  [19410] = LOC_STUN,                      -- Improved Concussive Shot - Triggered By: Improved Concussive Shot
  [19229] = PC_ROOT,                       -- Improved Wing Clip - Triggered By: Improved Wing Clip
  [24394] = LOC_STUN,                      -- Intimidation - Triggered By: Intimidation
  [1513] = LOC_FEAR,                       -- Scare Beast
    [14326] = LOC_FEAR,                      -- Rank 2
    [14327] = LOC_FEAR,                      -- Rank 3
  [19503] = LOC_DISORIENT,                 -- Scatter Shot
  [2974] = PC_SNARE,                       -- Wing Clip
    [14267] = PC_SNARE,                      -- Rank 2
    [14268] = PC_SNARE,                      -- Rank 3
  [19386] = LOC_SLEEP,                     -- Wyvern Sting
    [24132] = LOC_SLEEP,                     -- Rank 2
    [24133] = LOC_SLEEP,                     -- Rank 3
    [27068] = LOC_SLEEP,                     -- Rank 4
  [3355] = LOC_INCAPACITATE,               -- Freezing Trap Effect
    [14308] = LOC_SLEEP,                     -- Rank 2
    [14309] = LOC_SLEEP,                     -- Rank 3

  ---------------------------------------------------------------------------------------------------
  -- Mage
  ---------------------------------------------------------------------------------------------------

  [6136] = PC_SNARE,                       -- Chilled - Triggered By: Frost Armor
  [7321] = PC_SNARE,                       -- Chilled - Triggered By: Ice Armor
  [120] = PC_SNARE,                        -- Cone of Cold
    [8492] = PC_SNARE,                       -- Rank 2
    [10159] = PC_SNARE,                      -- Rank 3
    [10160] = PC_SNARE,                      -- Rank 4
    [10161] = PC_SNARE,                      -- Rank 5
    [27087] = PC_SNARE,                      -- Rank 6
  [2139] = LOC_SLEEP,                      -- Counterspell
  [18469] = LOC_SLEEP,                     -- Counterspell - Silenced - Triggered By: Improved Counterspell
  [122] = PC_ROOT,                         -- Frost Nova
    [865] = PC_ROOT,                         -- Rank 2
    [6131] = PC_ROOT,                        -- Rank 3
    [10230] = PC_ROOT,                       -- Rank 4
    [27088] = PC_ROOT,                       -- Rank 5
  [11071] = PC_ROOT,                       -- Frostbite
    [12496] = PC_ROOT,                       -- Rank 2
    [12497] = PC_ROOT,                       -- Rank 3
  [12355] = LOC_STUN,                      -- Impact - Triggered By: Impact
  [28272] = LOC_POLYMORPH,                 -- Polymorph
  [118] = LOC_POLYMORPH,                   -- Polymorph
    [12824] = LOC_POLYMORPH,                 -- Rank 2
    [12825] = LOC_POLYMORPH,                 -- Rank 3
    [12826] = LOC_POLYMORPH,                 -- Rank 4
  [28271] = LOC_POLYMORPH,                 -- Polymorph: Turtle
  [28272] = LOC_POLYMORPH,                 -- Polymorph: Pig
  [11113] = PC_DAZE,                       -- Blast Wave
    [13018] = PC_DAZE,                       -- Rank 2
    [13019] = PC_DAZE,                       -- Rank 3
    [13020] = PC_DAZE,                       -- Rank 4
    [13021] = PC_DAZE,                       -- Rank 5
    [27133] = PC_DAZE,                       -- Rank 6
    [33933] = PC_DAZE,                       -- Rank 7
  [31661] = LOC_DISORIENT,                 -- Dragon's Breath
    [33041] = LOC_DISORIENT,                 -- Rank 2
    [33042] = LOC_DISORIENT,                 -- Rank 3
    [33043] = LOC_DISORIENT,                 -- Rank 4
  [31589] = PC_SNARE,                      -- Slow
  -- Frostbolt - not added as it has 100% uptime

  ---------------------------------------------------------------------------------------------------
  -- Paladin
  ---------------------------------------------------------------------------------------------------

  [853] = LOC_STUN,                        -- Hammer of Justice
    [5588] = LOC_STUN,                       -- Rank 2
    [5589] = LOC_STUN,                       -- Rank 3
    [10308] = LOC_STUN,                      -- Rank 4
  [20066] = LOC_INCAPACITATE,              -- Repentance
  [20170] = LOC_STUN,                      -- Stun - Triggered By: Seal of Justice
  [31935] = PC_DAZE,                       -- Avenger's Shield
    [32699] = PC_DAZE,                       -- Rank 2
    [32700] = PC_DAZE,                       -- Rank 3


  ---------------------------------------------------------------------------------------------------
  -- Priest
  ---------------------------------------------------------------------------------------------------

  [15269] = LOC_STUN,                      -- Blackout - Triggered By: Blackout
  [605] = LOC_CHARM,                       -- Mind Control
    [10911] = LOC_CHARM,                     -- Rank 2
    [10912] = LOC_CHARM,                     -- Rank 3
  [453] = PC_MODAGGRORANGE,                -- Mind Soothe
    [8192] = PC_MODAGGRORANGE,               -- Rank 2
    [10953] = PC_MODAGGRORANGE,              -- Rank 3
    [25596] = PC_MODAGGRORANGE,              -- Rank 4
  [8122] = LOC_FEAR,                       -- Psychic Scream
    [8124] = LOC_FEAR,                       -- Rank 2
    [10888] = LOC_FEAR,                      -- Rank 3
    [10890] = LOC_FEAR,                      -- Rank 4
  [9484] = LOC_INCAPACITATE,               -- Shackle Undead
    [9485] = LOC_INCAPACITATE,               -- Rank 2
    [10955] = LOC_INCAPACITATE,              -- Rank 3
  [15487] = LOC_SLEEP,                     -- Silence
  [44041] = PC_ROOT,                       -- Chastise
    [44043] = PC_ROOT,                       -- Rank 2
    [44044] = PC_ROOT,                       -- Rank 3
    [44045] = PC_ROOT,                       -- Rank 4
    [44046] = PC_ROOT,                       -- Rank 5
    [44047] = PC_ROOT,                       -- Rank 6


  ---------------------------------------------------------------------------------------------------
  -- Rogue
  ---------------------------------------------------------------------------------------------------

  [2094] = LOC_DISORIENT,                  -- Blind
  [1833] = LOC_STUN,                       -- Cheap Shot
  [1725] = LOC_DISORIENT,                  -- Distract
  [1776] = LOC_INCAPACITATE,               -- Gouge
    [1777] = LOC_INCAPACITATE,               -- Rank 2
    [8629] = LOC_INCAPACITATE,               -- Rank 3
    [11285] = LOC_INCAPACITATE,              -- Rank 4
    [11286] = LOC_INCAPACITATE,              -- Rank 5
    [38764] = LOC_INCAPACITATE,              -- Rank 6
  [18425] = LOC_SLEEP,                     -- Kick - Silenced - Triggered By: Improved Kick
  [408] = LOC_STUN,                        -- Kidney Shot
    [8643] = LOC_STUN,                       -- Rank 2
  [5530] = LOC_STUN,                       -- Mace Stun Effect - Triggered By: Mace Specialization
  [14251] = PC_DISARM,                     -- Riposte
  [6770] = LOC_INCAPACITATE,               -- Sap
    [2070] = LOC_INCAPACITATE,               -- Rank 2
    [11297] = LOC_INCAPACITATE,              -- Rank 3
  [1330] = CC_SILENCE,                     -- Garrote - Silence - Triggered By: Garrote
  [26679] = PC_SNARE,                      -- Deadly Throw


  ---------------------------------------------------------------------------------------------------
  -- Shaman
  ---------------------------------------------------------------------------------------------------

  [8056] = PC_SNARE,                       -- Frost Shock
    [8058] = PC_SNARE,                       -- Rank 2
    [10472] = PC_SNARE,                      -- Rank 3
    [10473] = PC_SNARE,                      -- Rank 4
    [25464] = PC_SNARE,                      -- Rank 5


  ---------------------------------------------------------------------------------------------------
  -- Warlock
  ---------------------------------------------------------------------------------------------------

  [18118] = PC_SNARE,                      -- Aftermath - Triggered By: Aftermath
  [710] = LOC_BANISH,                      -- Banish
    [18647] = LOC_BANISH,                    -- Rank 2
  [18223] = PC_SNARE,                      -- Curse of Exhaustion
  [6789] = LOC_FEAR,                       -- Death Coil
    [17925] = LOC_FEAR,                      -- Rank 2
    [17926] = LOC_FEAR,                      -- Rank 3
    [27223] = LOC_FEAR,                      -- Rank 4
  [1098] = LOC_CHARM,                      -- Enslave Demon
    [11725] = LOC_CHARM,                     -- Rank 2
    [11726] = LOC_CHARM,                     -- Rank 3
  [5782] = LOC_FEAR,                       -- Fear
    [6213] = LOC_FEAR,                       -- Rank 2
    [6215] = LOC_FEAR,                       -- Rank 3
  [5484] = LOC_FEAR,                       -- Howl of Terror
    [17928] = LOC_FEAR,                      -- Rank 2
  [1122] = LOC_STUN,                       -- Inferno
  [6358] = LOC_CHARM,                      -- Seduction
  [24259] = LOC_SLEEP,                     -- Spell Lock - Triggered By: Spell Lock
  [30283] = LOC_STUN,                      -- Shadowfury
    [30413] = LOC_STUN,                      -- Rank 2
    [30414] = LOC_STUN,                      -- Rank 3
  [43523] = LOC_SLEEP,                     -- Unstable Affliction - Triggered by: Dispell of Unstable Affliction


  ---------------------------------------------------------------------------------------------------
  -- Warrior
  ---------------------------------------------------------------------------------------------------

  [12809] = LOC_STUN,                      -- Concussion Blow
  [676] = PC_DISARM,                       -- Disarm
  [1715] = PC_SNARE,                       -- Hamstring
    [7372] = PC_SNARE,                       -- Rank 2
    [7373] = PC_SNARE,                       -- Rank 3
    [25212] = PC_SNARE,                       -- Rank 4
  [23694] = PC_ROOT,                       -- Improved Hamstring - Triggered By: Improved Hamstring
  [20253] = LOC_STUN,                      -- Intercept Stun - Triggered By: Intercept
    [20614] = LOC_STUN,                      -- Rank 2
    [20615] = LOC_STUN,                      -- Rank 3
    [25273] = LOC_STUN,                      -- Rank 4
    [25274] = LOC_STUN,                      -- Rank 5
  [5246] = LOC_FEAR,                       -- Intimidating Shout
  [20511] = LOC_FEAR,                      -- Intimidating Shout - Triggered By: Intimidating Shout
  [12798] = LOC_STUN,                      -- Revenge Stun - Triggered By: Improved Revenge
  [18498] = LOC_SLEEP,                     -- Shield Bash - Silenced - Triggered By: Improved Shield Bash
  [12323] = PC_SNARE,                      -- Piercing Howl

  ---------------------------------------------------------------------------------------------------
  -- Racial Traits
  ---------------------------------------------------------------------------------------------------
  [20549] = LOC_STUN,       -- War Stomp (Tauren)

  ---------------------------------------------------------------------------------------------------
  -- Weapons & Items
  ---------------------------------------------------------------------------------------------------
  [34510] = LOC_STUN,       -- Deep Thunder and Stormherald (Weapon)
}

local CROWD_CONTROL_SPELLS_CLASSIC = {
  ---------------------------------------------------------------------------------------------------
  -- Druid
  ---------------------------------------------------------------------------------------------------

  [5211] = LOC_STUN,                       -- Bash
    [6798] = LOC_STUN,                       -- Rank 2
    [8983] = LOC_STUN,                       -- Rank 3
  [339] = PC_ROOT,                         -- Entangling Roots
    [1062] = PC_ROOT,                        -- Rank 2
    [5195] = PC_ROOT,                        -- Rank 3
    [5196] = PC_ROOT,                        -- Rank 4
    [9852] = PC_ROOT,                        -- Rank 5
    [9853] = PC_ROOT,                        -- Rank 6
  [19975] = PC_ROOT,                       -- Entangling Roots - Triggered By: Nature's Grasp
    [19974] = PC_ROOT,                       -- Rank 2
    [19973] = PC_ROOT,                       -- Rank 3
    [19972] = PC_ROOT,                       -- Rank 4
    [19971] = PC_ROOT,                       -- Rank 5
    [19970] = PC_ROOT,                       -- Rank 6
  [19675] = PC_ROOT,                       -- Feral Charge Effect - Triggered By: Feral Charge
  [2637] = LOC_SLEEP,                      -- Hibernate
    [18657] = LOC_SLEEP,                     -- Rank 2
    [18658] = LOC_SLEEP,                     -- Rank 3
  [9005] = LOC_STUN,                       -- Pounce
    [9823] = LOC_STUN,                       -- Rank 2
    [9827] = LOC_STUN,                       -- Rank 3
  [2908] = PC_MODAGGRORANGE,               -- Soothe Animal
    [8955] = PC_MODAGGRORANGE,               -- Rank 2
    [9901] = PC_MODAGGRORANGE,               -- Rank 3
  [16922] = LOC_STUN,                      -- Starfire Stun - Triggered By: Improved Starfire


  ---------------------------------------------------------------------------------------------------
  -- Hunter
  ---------------------------------------------------------------------------------------------------

  [25999] = PC_ROOT,                       -- Boar Charge - Triggered By: Charge
  [7922] = LOC_STUN,                       -- Charge Stun - Triggered By: Charge
  [5116] = PC_SNARE,                       -- Concussive Shot
  [19306] = PC_ROOT,                       -- Counterattack
    [20909] = PC_ROOT,                       -- Rank 2
    [20910] = PC_ROOT,                       -- Rank 3
  [19185] = PC_ROOT,                       -- Entrapment - Triggered By: Entrapment
  [19410] = LOC_STUN,                      -- Improved Concussive Shot - Triggered By: Improved Concussive Shot
  [19229] = PC_ROOT,                       -- Improved Wing Clip - Triggered By: Improved Wing Clip
  [24394] = LOC_STUN,                      -- Intimidation - Triggered By: Intimidation
  [1513] = LOC_FEAR,                       -- Scare Beast
    [14326] = LOC_FEAR,                      -- Rank 2
    [14327] = LOC_FEAR,                      -- Rank 3
  [19503] = LOC_DISORIENT,                 -- Scatter Shot
  [2974] = PC_SNARE,                       -- Wing Clip
    [14267] = PC_SNARE,                      -- Rank 2
    [14268] = PC_SNARE,                      -- Rank 3
  [19386] = LOC_SLEEP,                     -- Wyvern Sting
    [24132] = LOC_SLEEP,                     -- Rank 2
    [24133] = LOC_SLEEP,                     -- Rank 3
  [3355] = LOC_INCAPACITATE,               -- Freezing Trap Effect
  [14308] = LOC_SLEEP,                     -- Rank 2
  [14309] = LOC_SLEEP,                     -- Rank 3


  ---------------------------------------------------------------------------------------------------
  -- Mage
  ---------------------------------------------------------------------------------------------------

  [6136] = PC_SNARE,                       -- Chilled - Triggered By: Frost Armor
  [7321] = PC_SNARE,                       -- Chilled - Triggered By: Ice Armor
  [120] = PC_SNARE,                        -- Cone of Cold
    [8492] = PC_SNARE,                       -- Rank 2
    [10159] = PC_SNARE,                      -- Rank 3
    [10160] = PC_SNARE,                      -- Rank 4
    [10161] = PC_SNARE,                      -- Rank 5
  [2139] = LOC_SLEEP,                      -- Counterspell
  [18469] = LOC_SLEEP,                     -- Counterspell - Silenced - Triggered By: Improved Counterspell
  [122] = PC_ROOT,                         -- Frost Nova
    [865] = PC_ROOT,                         -- Rank 2
    [6131] = PC_ROOT,                        -- Rank 3
    [10230] = PC_ROOT,                       -- Rank 4
  [11071] = PC_ROOT,                       -- Frostbite
    [12496] = PC_ROOT,                       -- Rank 2
    [12497] = PC_ROOT,                       -- Rank 3
  [12355] = LOC_STUN,                      -- Impact - Triggered By: Impact
  [28272] = LOC_POLYMORPH,                 -- Polymorph
  [118] = LOC_POLYMORPH,                   -- Polymorph
    [12824] = LOC_POLYMORPH,                 -- Rank 2
    [12825] = LOC_POLYMORPH,                 -- Rank 3
    [12826] = LOC_POLYMORPH,                 -- Rank 4
  [28270] = LOC_POLYMORPH,                 -- Polymorph: Cow
  [28271] = LOC_POLYMORPH,                 -- Polymorph: Turtle
  [28272] = LOC_POLYMORPH,                 -- Polymorph: Pig
  [11113] = LOC_POLYMORPH,                 -- Blast Wave
    [13018] = LOC_POLYMORPH,                 -- Rank 2
    [13019] = LOC_POLYMORPH,                 -- Rank 3
    [13020] = LOC_POLYMORPH,                 -- Rank 4
    [13021] = LOC_POLYMORPH,                 -- Rank 5
  -- Frostbolt - not added as it has 100% uptime

  ---------------------------------------------------------------------------------------------------
  -- Paladin
  ---------------------------------------------------------------------------------------------------

  [853] = LOC_STUN,                        -- Hammer of Justice
    [5588] = LOC_STUN,                       -- Rank 2
    [5589] = LOC_STUN,                       -- Rank 3
    [10308] = LOC_STUN,                      -- Rank 4
  [20066] = LOC_INCAPACITATE,              -- Repentance
  [20170] = LOC_STUN,                      -- Stun - Triggered By: Seal of Justice


  ---------------------------------------------------------------------------------------------------
  -- Priest
  ---------------------------------------------------------------------------------------------------

  [15269] = LOC_STUN,                      -- Blackout - Triggered By: Blackout
  [605] = LOC_CHARM,                       -- Mind Control
    [10911] = LOC_CHARM,                     -- Rank 2
    [10912] = LOC_CHARM,                     -- Rank 3
  [453] = PC_MODAGGRORANGE,                -- Mind Soothe
    [8192] = PC_MODAGGRORANGE,               -- Rank 2
    [10953] = PC_MODAGGRORANGE,              -- Rank 3
  [8122] = LOC_FEAR,                       -- Psychic Scream
    [8124] = LOC_FEAR,                       -- Rank 2
    [10888] = LOC_FEAR,                      -- Rank 3
    [10890] = LOC_FEAR,                      -- Rank 4
  [9484] = LOC_INCAPACITATE,               -- Shackle Undead
    [9485] = LOC_INCAPACITATE,               -- Rank 2
    [10955] = LOC_INCAPACITATE,              -- Rank 3
  [15487] = LOC_SLEEP,                     -- Silence


  ---------------------------------------------------------------------------------------------------
  -- Rogue
  ---------------------------------------------------------------------------------------------------

  [2094] = LOC_DISORIENT,                  -- Blind
  [1833] = LOC_STUN,                       -- Cheap Shot
  [1725] = LOC_DISORIENT,                  -- Distract
  [1776] = LOC_INCAPACITATE,               -- Gouge
    [1777] = LOC_INCAPACITATE,               -- Rank 2
    [8629] = LOC_INCAPACITATE,               -- Rank 3
    [11285] = LOC_INCAPACITATE,              -- Rank 4
    [11286] = LOC_INCAPACITATE,              -- Rank 5
  [18425] = LOC_SLEEP,                     -- Kick - Silenced - Triggered By: Improved Kick
  [408] = LOC_STUN,                        -- Kidney Shot
    [8643] = LOC_STUN,                       -- Rank 2
  [5530] = LOC_STUN,                       -- Mace Stun Effect - Triggered By: Mace Specialization
  [14251] = PC_DISARM,                     -- Riposte
  [6770] = LOC_INCAPACITATE,               -- Sap
    [2070] = LOC_INCAPACITATE,               -- Rank 2
    [11297] = LOC_INCAPACITATE,              -- Rank 3


  ---------------------------------------------------------------------------------------------------
  -- Shaman
  ---------------------------------------------------------------------------------------------------

  [8056] = PC_SNARE,                       -- Frost Shock
    [8058] = PC_SNARE,                       -- Rank 2
    [10472] = PC_SNARE,                      -- Rank 3
    [10473] = PC_SNARE,                      -- Rank 4


  ---------------------------------------------------------------------------------------------------
  -- Warlock
  ---------------------------------------------------------------------------------------------------

  [18118] = PC_SNARE,                      -- Aftermath - Triggered By: Aftermath
  [710] = LOC_BANISH,                      -- Banish
    [18647] = LOC_BANISH,                    -- Rank 2
  [18223] = PC_SNARE,                      -- Curse of Exhaustion
  [6789] = LOC_FEAR,                       -- Death Coil
    [17925] = LOC_FEAR,                      -- Rank 2
    [17926] = LOC_FEAR,                      -- Rank 3
  [1098] = LOC_CHARM,                      -- Enslave Demon
    [11725] = LOC_CHARM,                     -- Rank 2
    [11726] = LOC_CHARM,                     -- Rank 3
  [5782] = LOC_FEAR,                       -- Fear
    [6213] = LOC_FEAR,                       -- Rank 2
    [6215] = LOC_FEAR,                       -- Rank 3
  [5484] = LOC_FEAR,                       -- Howl of Terror
    [17928] = LOC_FEAR,                      -- Rank 2
  [1122] = LOC_STUN,                       -- Inferno
  [6358] = LOC_CHARM,                      -- Seduction
  [24259] = LOC_SLEEP,                     -- Spell Lock - Triggered By: Spell Lock


  ---------------------------------------------------------------------------------------------------
  -- Warrior
  ---------------------------------------------------------------------------------------------------

  [12809] = LOC_STUN,                      -- Concussion Blow
  [676] = PC_DISARM,                       -- Disarm
  [1715] = PC_SNARE,                       -- Hamstring
    [7372] = PC_SNARE,                       -- Rank 2
    [7373] = PC_SNARE,                       -- Rank 3
  [23694] = PC_ROOT,                       -- Improved Hamstring - Triggered By: Improved Hamstring
  [20253] = LOC_STUN,                      -- Intercept Stun - Triggered By: Intercept
    [20614] = LOC_STUN,                      -- Rank 2
    [20615] = LOC_STUN,                      -- Rank 3
  [5246] = LOC_FEAR,                       -- Intimidating Shout
  [20511] = LOC_FEAR,                      -- Intimidating Shout - Triggered By: Intimidating Shout
  [12798] = LOC_STUN,                      -- Revenge Stun - Triggered By: Improved Revenge
  [18498] = LOC_SLEEP,                     -- Shield Bash - Silenced - Triggered By: Improved Shield Bash
  [12323] = PC_SNARE,                      -- Piercing Howl

  ---------------------------------------------------------------------------------------------------
  -- Racial Traits
  ---------------------------------------------------------------------------------------------------
  [20549] = LOC_STUN,       -- War Stomp (Tauren)
}

if Addon.IS_CLASSIC then
  Widget.CROWD_CONTROL_SPELLS = CROWD_CONTROL_SPELLS_CLASSIC
elseif Addon.IS_TBC_CLASSIC then
  Widget.CROWD_CONTROL_SPELLS = CROWD_CONTROL_SPELLS_TBC_CLASSIC
else
  Widget.CROWD_CONTROL_SPELLS = CROWD_CONTROL_SPELLS_RETAIL
end

---------------------------------------------------------------------------------------------------
-- Global attributes
---------------------------------------------------------------------------------------------------
local PLayerIsInInstance = false
--local PLayerIsInCombat = false

---------------------------------------------------------------------------------------------------
-- Cached configuration settings
---------------------------------------------------------------------------------------------------
local HideOmniCC, ShowDuration
local AuraHighlightEnabled, AuraHighlightStart, AuraHighlightStop, AuraHighlightStopPrevious, AuraHighlightOffset
local AuraHighlightColor = { 0, 0, 0, 0 }
local EnabledForStyle = {}

---------------------------------------------------------------------------------------------------
-- OnUpdate code - updates the auras remaining uptime and stacks and hides them after they expired
---------------------------------------------------------------------------------------------------

local function OnShowHookScript(widget_frame)
  widget_frame.Buffs.TimeSinceLastUpdate = 0
  widget_frame.Debuffs.TimeSinceLastUpdate = 0
  widget_frame.CrowdControl.TimeSinceLastUpdate = 0
end

---------------------------------------------------------------------------------------------------
-- Filtering and sorting functions
---------------------------------------------------------------------------------------------------

function Widget:GetColorForAura(aura)
	local db = self.db

  if aura.type and db.ShowAuraType then
    return DebuffTypeColor[aura.type]
  elseif aura.effect == "HARMFUL" then
    return db.DefaultDebuffColor
  else
    return db.DefaultBuffColor
	end
end

local function FilterNone(show_aura, spellfound, is_mine, show_only_mine)
  return show_aura
end

local function FilterAllowlist(show_aura, spellfound, is_mine, show_only_mine)
  if spellfound == "All" then
    return show_aura
  elseif spellfound == true then
    return (show_only_mine == nil and show_aura) or (show_aura and ((show_only_mine and is_mine) or show_only_mine == false))
  elseif spellfound == "My" then
    return show_aura and is_mine
  end

  return false
end

local function FilterBlocklist(show_aura, spellfound, is_mine, show_only_mine)
  -- blacklist all auras, i.e., default is show all auras (no matter who casted it)
  --   spellfound = true or All - blacklist this aura (from all casters)
  --   spellfound = My          - blacklist only my aura
  --   spellfound = nil         - show aura (spell not found in blacklist)
  --   spellfound = Not         - show aura (found entry not relevant, ignore it)

  if spellfound == "All" or spellfound == true then
    return false
  elseif spellfound == "My" then
    return not is_mine
  elseif spellfound == "Not" then
    return true
  end

  return show_aura
end

Widget.FILTER_FUNCTIONS = {
  all = FilterNone,
  blacklist = FilterBlocklist,
  whitelist = FilterAllowlist,
  None = FilterNone,
  Block = FilterBlocklist,
  Allow = FilterAllowlist,
}

if Addon.IS_CLASSIC or Addon.IS_TBC_CLASSIC then
  -- ShowBlizzard... is not supported in Classic
  function Widget:FilterFriendlyDebuffsBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllFriendly or
      -- (db.ShowBlizzardForFriendly and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer))) or
      (db.ShowDispellable and aura.StealOrPurge) or
      (db.ShowBoss and aura.BossDebuff) or
      (aura.type and db.FilterByType[self.AURA_TYPE[aura.type]])

    local spellfound = self.AuraFilterDebuffs[aura.name] or self.AuraFilterDebuffs[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end

  function Widget:FilterEnemyDebuffsBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllEnemy or
      (db.ShowOnlyMine and aura.CastByPlayer) --or
      -- (db.ShowBlizzardForEnemy and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer)))

    local spellfound = self.AuraFilterDebuffs[aura.name] or self.AuraFilterDebuffs[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer, db.ShowOnlyMine)
  end

  function Widget:FilterFriendlyCrowdControlBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllFriendly or
      --(db.ShowBlizzardForFriendly and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer))) or
      (db.ShowDispellable and aura.StealOrPurge) or
      (db.ShowBoss and aura.BossDebuff)

    local spellfound = self.AuraFilterCrowdControl[aura.name] or self.AuraFilterCrowdControl[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end

  function Widget:FilterEnemyCrowdControlBySpell(db, aura, AuraFilterFunction)
    local show_aura = true
      --db.ShowAllEnemy or
      --(db.ShowBlizzardForEnemy and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer)))

    local spellfound = self.AuraFilterCrowdControl[aura.name] or self.AuraFilterCrowdControl[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end
else
  function Widget:FilterFriendlyDebuffsBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllFriendly or
                      (db.ShowBlizzardForFriendly and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer))) or
                      (db.ShowDispellable and aura.StealOrPurge) or
                      (db.ShowBoss and aura.BossDebuff) or
                      (aura.type and db.FilterByType[self.AURA_TYPE[aura.type]])

    local spellfound = self.AuraFilterDebuffs[aura.name] or self.AuraFilterDebuffs[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end

  function Widget:FilterEnemyDebuffsBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllEnemy or
                      (db.ShowOnlyMine and aura.CastByPlayer) or
                      (db.ShowBlizzardForEnemy and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer)))

    local spellfound = self.AuraFilterDebuffs[aura.name] or self.AuraFilterDebuffs[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer, db.ShowOnlyMine)
  end

  function Widget:FilterFriendlyCrowdControlBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllFriendly or
                      (db.ShowBlizzardForFriendly and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer))) or
                      (db.ShowDispellable and aura.StealOrPurge) or
                      (db.ShowBoss and aura.BossDebuff)

    local spellfound = self.AuraFilterCrowdControl[aura.name] or self.AuraFilterCrowdControl[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end

  function Widget:FilterEnemyCrowdControlBySpell(db, aura, AuraFilterFunction)
    local show_aura = db.ShowAllEnemy or
                      (db.ShowBlizzardForEnemy and (aura.ShowAll or (aura.ShowPersonal and aura.CastByPlayer)))

    local spellfound = self.AuraFilterCrowdControl[aura.name] or self.AuraFilterCrowdControl[aura.spellid]

    return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
  end
end

function Widget:FilterFriendlyBuffsBySpell(db, aura, AuraFilterFunction, unit)
  local show_aura = db.ShowAllFriendly or
    (db.ShowOnFriendlyNPCs and unit.type == "NPC") or
    (db.ShowOnlyMine and aura.CastByPlayer) or
    (db.ShowPlayerCanApply and aura.PlayerCanApply)

  local spellfound = self.AuraFilterBuffs[aura.name] or self.AuraFilterBuffs[aura.spellid]

  return AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)
end

function Widget:FilterEnemyBuffsBySpell(db, aura, AuraFilterFunction, unit)
  local show_aura
  if aura.duration <= 0 and db.HideUnlimitedDuration then
    show_aura = false
  else
    show_aura = db.ShowAllEnemy or (db.ShowOnEnemyNPCs and unit.type == "NPC") or (db.ShowDispellable and aura.StealOrPurge) or
      (aura.type == "Magic" and db.ShowMagic)
  end

  --  local show_aura = db.ShowAllEnemy or (db.ShowOnEnemyNPCs and unit.type == "NPC") or (db.ShowDispellable and aura.StealOrPurge)
  local spellfound = self.AuraFilterBuffs[aura.name] or self.AuraFilterBuffs[aura.spellid]

  show_aura = AuraFilterFunction(show_aura, spellfound, aura.CastByPlayer)

  -- Checking unlimited auras after filter function results in the filter list not being able to overwrite
  -- the "Show Unlimited Buffs" settings
  if show_aura and (aura.duration <= 0) then
    show_aura =  db.ShowUnlimitedAlways or
      (db.ShowUnlimitedInCombat and unit.isInCombat) or
      (db.ShowUnlimitedInInstances and PLayerIsInInstance) or
      (db.ShowUnlimitedOnBosses and unit.IsBossOrRare)
    unit.HasUnlimitedAuras = true
  end

  return show_aura
end

Widget.AuraSortFunctionAtoZ = function(a, b)
  return a.priority < b.priority
end

Widget.AuraSortFunctionNum = function(a, b)
  if a.duration == 0 then
    return false
  elseif b.duration == 0 then
    return true
  end

  return a.priority < b.priority
end

-------------------------------------------------------------
-- Widget Object Functions
-------------------------------------------------------------

function Widget:UpdateUnitAuras(aura_grid_frame, unit, enabled_auras, enabled_cc, SpellFilter, SpellFilterCC, effect, filter_mode)
  --local aura_grid_frame = widget_frame[aura_type]
  --local enabled_auras = frame.AuraGrid[aura_type].ShowFriendly
  --local filter_mode = frame.AuraGrid[aura_type].FilterMode
  local aura_grid = aura_grid_frame.AuraGrid
  --print (filter_mode, aura_grid.db.FilterMode)

  local aura_frames = aura_grid_frame.AuraFrames
  -- If debuffs are disabled, but CCs are enabled, we should just hide debuffs, but still process all auras to be able to show CC debuffs
  if not (enabled_auras or enabled_cc) then 
    aura_grid_frame.ActiveAuras = 0
    aura_grid:HideNonActiveAuras(aura_grid_frame)
    aura_grid_frame:Hide()

    return
  end
  -- Show the aura grid (for debuffs) as it might be hidden when the nameplate was, e.g., used for friendly units where debuffs&CCs are disabled, 
  -- and then is re-used for enemy units where these are enabled.
  aura_grid_frame:Show()
  
  local UnitAuraList = self.UnitAuraList
  local db = self.db
  -- Optimization for auras sorting
  local sort_order = db.SortOrder
  if sort_order ~= "None" then
    UnitAuraList = {}
  end

  aura_grid_frame.Filter = effect -- Used for showning the correct tooltip
  local widget_frame = aura_grid_frame:GetParent()
  unit.HasUnlimitedAuras = false
  local unitid = unit.unitid

  local db_auras = (effect == "HARMFUL" and db.Debuffs) or db.Buffs
  local AuraFilterFunction = self.FILTER_FUNCTIONS[filter_mode]
  local AuraFilterFunctionCC = self.FILTER_FUNCTIONS[db.CrowdControl.FilterMode]
  local GetAuraPriority = self.PRIORITY_FUNCTIONS[sort_order]

  local aura_count = 1
  local CustomStyleAuraTrigger = false

  for i = 1, 40 do
    -- Auras are evaluated by an external function - pre-filtering before the icon grid is populated
    UnitAuraList[aura_count] = UnitAuraList[aura_count] or {}
    local aura = UnitAuraList[aura_count]

    -- TBC Classic, Retail:
    -- name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod, ...
    local _
    aura.name, aura.texture, aura.stacks, aura.type, aura.duration, aura.expiration, aura.caster,
      aura.StealOrPurge, aura.ShowPersonal, aura.spellid, aura.PlayerCanApply, aura.BossDebuff, _, aura.ShowAll =
      UnitAuraWrapper(unitid, i, effect)

    -- ShowPesonal: Debuffs  that are shown on Blizzards nameplate, no matter who casted them (and
    -- ShowAll: Debuffs
    if not aura.name then break end

    -- CastByPlayer is also used by aura trigger custom styles (only my auras)
    aura.CastByPlayer = (aura.caster == "player" or aura.caster == "pet" or aura.caster == "vehicle")
    if Addon.ActiveAuraTriggers then
      -- Do this to prevent calls to UnitStyle_AuraDependent after a aura trigger was found already
      CustomStyleAuraTrigger = CustomStyleAuraTrigger or UnitStyle_AuraDependent(unit, aura.spellid, aura.name, aura.CastByPlayer)
    end

    -- Workaround or hack, currently, for making aura-triggered custom nameplates work even on nameplates that do
    -- not show auras currently without a big overhead
    if not widget_frame.HideAuras then
      local show_aura = false

      --aura.unit = unitidf
      aura.Index = i
      aura.effect = effect
      aura.ShowAll = aura.ShowAll
      aura.CrowdControl = (enabled_cc and self.CROWD_CONTROL_SPELLS[aura.spellid])
      
      -- Store Order/Priority
      if aura.CrowdControl then
        show_aura = SpellFilterCC(self, db.CrowdControl, aura, AuraFilterFunctionCC)

        -- Show crowd control auras that are not shown in Blizard mode as normal debuffs
        if not show_aura and enabled_auras then
          aura.CrowdControl = false
          show_aura = SpellFilter(self, db_auras, aura, AuraFilterFunction)
        end
      elseif enabled_auras then
        show_aura = SpellFilter(self, db_auras, aura, AuraFilterFunction, unit)
      end

      if show_aura then
        aura.color = self:GetColorForAura(aura)
        aura.priority = GetAuraPriority(aura)

        aura_count = aura_count + 1
      end
    end
  end

  if widget_frame.HideAuras then return end

  aura_count = aura_count - 1
  local aura_count_cc = 0

  -- Show auras
  local aura_grid_max_auras = aura_grid.MaxAuras

  local aura_grid_cc = self.CrowdControl
  local aura_grid_cc_max_auras = aura_grid_cc.MaxAuras
  local aura_grid_frame_cc = widget_frame.CrowdControl
  local aura_frames_cc = aura_grid_frame_cc.AuraFrames

  if aura_count > 0 then
    -- Sort all auras
    if sort_order == "None" then
      -- invalidate all entries after storedAuraCount
      -- if number of auras to show was decreased, remove any overflow aura frames
      local i = aura_count + 1
      local aura = UnitAuraList[i]
      while aura do
        aura.priority = nil
        i = i + 1
        aura = UnitAuraList[i]
      end
    else
      UnitAuraList[aura_count + 1] = nil

      if sort_order == "AtoZ" then
        sort(UnitAuraList, self.AuraSortFunctionAtoZ)
      else
        sort(UnitAuraList, self.AuraSortFunctionNum)
      end
    end

    local index_start, index_end, index_step
    if db.SortReverse then
      index_start, index_end, index_step = aura_count, 1, -1
    else
      index_start, index_end, index_step = 1, aura_count, 1
    end

    aura_count = 0
    aura_count_cc = 0
    local aura_frame
    for index = index_start, index_end, index_step do
      local aura = UnitAuraList[index]

      if aura.spellid and aura.expiration then
        if aura.CrowdControl then
          -- Don't show CCs beyond MaxAuras, sorting should be correct here
          if aura_count_cc < aura_grid_cc_max_auras then
            aura_count_cc = aura_count_cc + 1
            aura_frame = aura_grid_cc:GetAuraFrame(aura_grid_frame_cc, aura_count_cc)
          end
        else
          if aura_count < aura_grid_max_auras then
            aura_count = aura_count + 1
            aura_frame = aura_grid:GetAuraFrame(aura_grid_frame, aura_count)
          end
        end

        if aura_frame then
          aura_frame.AuraName = aura.name
          aura_frame.AuraDuration = aura.duration
          aura_frame.AuraTexture = aura.texture
          aura_frame.AuraExpiration = aura.expiration
          aura_frame.AuraStacks = aura.stacks
          aura_frame.AuraColor = aura.color
          aura_frame.AuraStealOrPurge = aura.StealOrPurge

          -- Information for aura tooltips
          aura_frame.AuraIndex = aura.Index

          -- Call function to display the aura
          if aura.CrowdControl then
            aura_grid_cc:UpdateAuraInformation(aura_frame)
          else
            aura_grid:UpdateAuraInformation(aura_frame)
          end
        end

        -- Both aura areas (buffs/debuffs) and crowd control are filled up, no further processing necessary
        if aura_count >= aura_grid_max_auras and aura_count_cc >= aura_grid_cc_max_auras then
          break
        end

        aura_frame = nil
      end
    end
  end

  aura_grid_frame.ActiveAuras = aura_count
  -- Hide non-active aura slots
  aura_grid:HideNonActiveAuras(aura_grid_frame, true)

  if effect == "HARMFUL" then
    aura_grid_frame_cc.ActiveAuras = aura_count_cc
    -- If scanning debuffs, also hide non-active CC aura slots
    aura_grid_cc:HideNonActiveAuras(aura_grid_frame_cc)
  end
end

-- local function CenterAuraGrid(aura_grid, aura_grid_frame, db_aura_grid)
--   local auras_no = aura_grid_frame.ActiveAuras
--   if aura_grid.IconMode and auras_no > 0 then
--     local x_offset = 0
--     if db_aura_grid.CenterAuras then
--       -- Re-anchor the first frame, if auras should be centered
--       x_offset = (auras_no < aura_grid.Columns) and aura_grid.CenterAurasPositions[auras_no] or 0
--     end
--     local align_layout = aura_grid.AlignLayout
--     local aura_one = aura_grid_frame.AuraFrames[1]
--     aura_one:ClearAllPoints()
--     aura_one:SetPoint(align_layout[3], aura_grid_frame, (aura_grid.AuraWidgetOffset + x_offset) * align_layout[5], (aura_grid.AuraWidgetOffset + aura_grid.RowSpacing) * align_layout[6])
--   end
-- end

-- function Widget:ResizeAurasOfAuraGrid(aura_grid, aura_grid_frame)
--   local db_aura_grid = aura_grid.db
--   local aura_frame_list = aura_grid_frame.AuraFrames
--   local auras_no = aura_grid_frame.ActiveAuras

--   print ("No: ", auras_no)
--   local auras_no = aura_grid_frame.ActiveAuras
--   for index = 1, auras_no do
--     local aura_frame = aura_frame_list[index]
--     aura_frame:SetSize(db_aura_grid.IconWidth, db_aura_grid.IconHeight)

--     -- Need to do this because of different offset
--     local align_layout = aura_grid.AlignLayout
--     aura_frame:ClearAllPoints()
--     if index == 1 then
--       aura_frame:SetPoint(align_layout[3], aura_grid_frame, aura_grid.AuraWidgetOffset * align_layout[5], (aura_grid.AuraWidgetOffset + aura_grid.RowSpacing) * align_layout[6])
--     elseif (index - 1) % aura_grid.Columns == 0 then
--       aura_frame:SetPoint(align_layout[3], aura_frame_list[index - aura_grid.Columns], align_layout[4], 0, aura_grid.RowSpacing * align_layout[6])
--     else
--       aura_frame:SetPoint(align_layout[1], aura_frame_list[index - 1], align_layout[2], aura_grid.ColumnSpacing * align_layout[5], 0)
--     end
--   end

--   -- Re-center aura area as size has changed now
--   -- CenterAuraGrid(aura_grid, aura_grid_frame, db_aura_grid)
--   if aura_grid.IconMode and auras_no > 0 then
--     local x_offset = 0
--     if db_aura_grid.CenterAuras then
--       -- Re-anchor the first frame, if auras should be centered
--       x_offset = (auras_no < aura_grid.Columns) and aura_grid.CenterAurasPositions[auras_no] or 0
--     end
--     local align_layout = aura_grid.AlignLayout
--     local aura_one = aura_grid_frame.AuraFrames[1]
--     aura_one:ClearAllPoints()
--     aura_one:SetPoint(align_layout[3], aura_grid_frame, (aura_grid.AuraWidgetOffset + x_offset) * align_layout[5], (aura_grid.AuraWidgetOffset + aura_grid.RowSpacing) * align_layout[6])
--   end

--   aura_grid_frame:SetHeight(ceil(auras_no / aura_grid.Columns) * (aura_grid.AuraHeight + aura_grid.AuraWidgetOffset) +
--   aura_grid.RowSpacing + aura_grid.AuraWidgetOffset)
-- end

local function AnchorFrameForMode(db, frame, anchor_to)
  frame:ClearAllPoints()

  local anchor = db.Anchor or "CENTER"
  if db.InsideAnchor == false then
    local anchor_point_text = ANCHOR_POINT_TEXT[anchor]
    frame:SetPoint(anchor_point_text[2], anchor_to, anchor_point_text[1], db.HorizontalOffset or 0, db.VerticalOffset or 0)
  else -- db.InsideAnchor not defined in settings or true
    frame:SetPoint(anchor, anchor_to, anchor, db.HorizontalOffset or 0, db.VerticalOffset or 0)
  end
end

function Widget:UpdatePositionAuraGrid(widget_frame, aura_type, unit_style)
  local db = self.db

  local aura_grid = self[aura_type]
  local aura_grid_frame = widget_frame[aura_type]
  local auras_no = aura_grid_frame.ActiveAuras

  -- if not aura_grid_frame.TestBackground then
  --  aura_grid_frame.TestBackground = aura_grid_frame:CreateTexture(nil, "BACKGROUND")
  --  aura_grid_frame.TestBackground:SetAllPoints(aura_grid_frame)
  --  aura_grid_frame.TestBackground:SetTexture(Addon.LibSharedMedia:Fetch('statusbar', Addon.db.profile.AuraWidget.BackgroundTexture))
  --  aura_grid_frame.TestBackground:SetVertexColor(0,0,0,0.5)
  -- end

  local db_aura_grid = db[aura_type]
  local anchor_to_db = db_aura_grid.AnchorTo
  local anchor_to = (anchor_to_db == "Healthbar" and aura_grid_frame:GetParent()) or widget_frame[anchor_to_db]

  AnchorFrameForMode(db_aura_grid[MODE_FOR_STYLE[unit_style]], aura_grid_frame, anchor_to)
  if aura_grid.IconMode and auras_no > 0 then
    local x_offset = 0
    if db_aura_grid.CenterAuras then
      -- Re-anchor the first frame, if auras should be centered
      x_offset = (auras_no < aura_grid.Columns) and aura_grid.CenterAurasPositions[auras_no] or 0
    end
    local align_layout = aura_grid.AlignLayout
    local aura_one = aura_grid_frame.AuraFrames[1]
    aura_one:ClearAllPoints()
    aura_one:SetPoint(align_layout[3], aura_grid_frame, (aura_grid.AuraWidgetOffset + x_offset) * align_layout[5], (aura_grid.AuraWidgetOffset + aura_grid.RowSpacing) * align_layout[6])
  end

  aura_grid_frame:SetHeight(ceil(auras_no / aura_grid.Columns) * (aura_grid.AuraHeight + aura_grid.AuraWidgetOffset) +
    aura_grid.RowSpacing + aura_grid.AuraWidgetOffset)
end

function Widget:UpdateIconGrid(widget_frame, unit)
  local db = self.db
  local unitid = unit.unitid

  local unit_is_target
  if db.ShowTargetOnly then
    unit_is_target = UnitIsUnit("target", unitid)
    if unit_is_target then
      self.CurrentTarget = widget_frame
    elseif not Addon.ActiveAuraTriggers then
      -- Continue with aura scanning for non-target units if there are aura triggers that might change the nameplates style
      widget_frame:Hide()
      return
    end
  end

  local old_CustomStyleAura = unit.CustomStyleAura
  unit.CustomStyleAura = false
  widget_frame.HideAuras = not EnabledForStyle[unit.style] or (db.ShowTargetOnly and not unit.isTarget)

  local enabled_cc
  local unit_is_friendly = UnitReaction(unitid, "player") > 4
  if unit_is_friendly then -- friendly or better
    enabled_cc = db.CrowdControl.ShowFriendly

    local buff_aura_grid, debuff_aura_grid
    if db.SwitchAreaByReaction then
      buff_aura_grid, debuff_aura_grid = widget_frame.Debuffs, widget_frame.Buffs
    else
      buff_aura_grid, debuff_aura_grid = widget_frame.Buffs, widget_frame.Debuffs
    end

    self:UpdateUnitAuras(debuff_aura_grid, unit, db.Debuffs.ShowFriendly, enabled_cc, self.FilterFriendlyDebuffsBySpell, self.FilterFriendlyCrowdControlBySpell, "HARMFUL", db.Debuffs.FilterMode)
    self:UpdateUnitAuras(buff_aura_grid, unit, db.Buffs.ShowFriendly, false, self.FilterFriendlyBuffsBySpell, self.FilterFriendlyCrowdControlBySpell, "HELPFUL", db.Buffs.FilterMode)
  else
    enabled_cc = db.CrowdControl.ShowEnemy

    self:UpdateUnitAuras(widget_frame.Debuffs, unit, db.Debuffs.ShowEnemy, enabled_cc, self.FilterEnemyDebuffsBySpell, self.FilterEnemyCrowdControlBySpell, "HARMFUL", db.Debuffs.FilterMode)
    self:UpdateUnitAuras(widget_frame.Buffs, unit, db.Buffs.ShowEnemy, false, self.FilterEnemyBuffsBySpell, self.FilterEnemyCrowdControlBySpell, "HELPFUL", db.Buffs.FilterMode)
  end

  -- Set the style if a aura trigger for a custom nameplate was found or the aura trigger
  -- is no longer there
  if unit.CustomStyleAura or old_CustomStyleAura then
    UpdateCustomStyleAfterAuraTrigger(unit)
  end

  if widget_frame.HideAuras then
    widget_frame:Hide()
    return
  end

  if widget_frame.Buffs.ActiveAuras > 0 or widget_frame.Debuffs.ActiveAuras > 0 or widget_frame.CrowdControl.ActiveAuras > 0 then
    self:UpdatePositionAuraGrid(widget_frame, AURA_GRID_BUFFS, unit.style)
    self:UpdatePositionAuraGrid(widget_frame, AURA_GRID_DEBUFFS, unit.style)

    -- if unit_is_friendly and db.SwitchScaleByReaction then
    --   aura_grid_frame:SetHeight(ceil(auras_no / aura_grid.Columns) * (aura_grid.AuraHeight + aura_grid.AuraWidgetOffset) +
    --   aura_grid.RowSpacing + aura_grid.AuraWidgetOffset)
    -- end

    -- if unit_is_friendly then
    --   frame_auras_one, frame_auras_two = widget_frame.Buffs, widget_frame.Debuffs
    --   auras_one_active, auras_two_active = buffs_active, debuffs_active
    --   if db.SwitchScaleByReaction then
    --     scale_auras_one, scale_auras_two = db.Debuffs.Scale, db.Buffs.Scale
    --   else
    --     scale_auras_one, scale_auras_two = db.Buffs.Scale, db.Debuffs.Scale
    --   end
    -- else
    --   frame_auras_one, frame_auras_two = widget_frame.Debuffs, widget_frame.Buffs
    --   auras_one_active, auras_two_active = debuffs_active, buffs_active
    --   scale_auras_one, scale_auras_two = db.Debuffs.Scale, db.Buffs.Scale
    -- end

    -- if unit_is_friendly and db.SwitchScaleByReaction then
    --   print (unit.name, "=> Switch By Reaction")
    --   -- self:ResizeAurasOfAuraGrid(widget_frame, AURA_GRID_BUFFS, AURA_GRID_DEBUFFS) 
    --   -- self:ResizeAurasOfAuraGrid(widget_frame, AURA_GRID_DEBUFFS, AURA_GRID_BUFFS)
    --   self:ResizeAurasOfAuraGrid(self.Buffs, widget_frame.Debuffs)
    --   self:ResizeAurasOfAuraGrid(self.Debuffs, widget_frame.Buffs)

    --   widget_frame.IsSwitchedByReaction = true
    -- else
    --   widget_frame.IsSwitchedByReaction = false
    -- end

    -- Position the different aura frames so that they are stacked one above the other
    if enabled_cc then
      self:UpdatePositionAuraGrid(widget_frame, AURA_GRID_CROWDCONTROL, unit.style)
      widget_frame.CrowdControl:Show()
    else
      widget_frame.CrowdControl:Hide()
    end

    widget_frame:Show()
  else
    widget_frame:Hide()
  end
end

---------------------------------------------------------------------------------------------------
-- Functions for cooldown handling incl. OmniCC support
---------------------------------------------------------------------------------------------------

local function CreateCooldown(parent)
  -- When the cooldown shares the frameLevel of its parent, the icon texture can sometimes render
  -- ontop of it. So it looks like it's not drawing a cooldown but it's just hidden by the icon.

  local cooldown_frame = _G.CreateFrame("Cooldown", nil, parent, "ThreatPlatesAuraWidgetCooldown")
  cooldown_frame:SetAllPoints(parent.Icon)
  cooldown_frame:SetReverse(true)
  cooldown_frame:SetHideCountdownNumbers(true)
  cooldown_frame.noCooldownCount = HideOmniCC

  return cooldown_frame
end

local function UpdateCooldown(cooldown_frame, db)
  if db.ShowCooldownSpiral then
    cooldown_frame:SetDrawEdge(true)
    cooldown_frame:SetDrawSwipe(true)
  else
    cooldown_frame:SetDrawEdge(false)
    cooldown_frame:SetDrawSwipe(false)
  end

  -- Fix for OmnniCC cooldown numbers being shown on auras
  if cooldown_frame.noCooldownCount ~= HideOmniCC then
    cooldown_frame.noCooldownCount = HideOmniCC
    -- Force an update on OmniCC cooldowns
    cooldown_frame:Hide()
    cooldown_frame:Show()
  end
end

local function SetCooldown(cooldown_frame, duration, expiration)
  if duration and expiration and duration > 0 and expiration > 0 then
    cooldown_frame:SetCooldown(expiration - duration, duration + .25)
  else
    cooldown_frame:Clear()
  end
end

---------------------------------------------------------------------------------------------------
-- Functions for showing tooltips on auras
---------------------------------------------------------------------------------------------------

local function AuraFrameOnEnter(self)
  AuraTooltip:SetOwner(self, "ANCHOR_LEFT")
  AuraTooltip:SetUnitAura(self:GetParent():GetParent().unit.unitid, self.AuraIndex, self:GetParent().Filter)
end

local function AuraFrameOnLeave(self)
  AuraTooltip:Hide()
end

---------------------------------------------------------------------------------------------------
-- Creation and update functions
---------------------------------------------------------------------------------------------------

local function OnUpdateAuraGridFrame(self, elapsed)
  -- Update the number of seconds since the last update
  self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed

  if self.TimeSinceLastUpdate >= self.AuraGrid.UpdateInterval then
    self.TimeSinceLastUpdate = 0

    local aura_frame
    for i = 1, self.ActiveAuras do
      aura_frame = self.AuraFrames[i]
      self.AuraGrid:UpdateWidgetTime(aura_frame, aura_frame.AuraExpiration, aura_frame.AuraDuration)
    end
  end
end

function Widget:UpdateAuraGridLayout(widget_frame, aura_type)
  local aura_grid = self[aura_type]
  local aura_grid_frame = widget_frame[aura_type]
  local aura_frame_list = aura_grid_frame.AuraFrames

  local no_auras = #aura_frame_list

  -- If the number of auras to show was decreased, remove any overflow aura frames
  if no_auras > aura_grid.MaxAuras then
    for i = no_auras, aura_grid.MaxAuras + 1, -1 do
      aura_frame_list[i]:Hide()
      aura_frame_list[i] = nil
    end
    no_auras = aura_grid.MaxAuras
  end

  -- When called from Create(), #aura_frame_list is 0, so nothing will be done here
  -- When called from after a settings update, delete aura frames with wrong layout (icon/bar mode) and update all other aura frames
  local icon_mode = aura_grid.IconMode
  local aura_frame
  for i = no_auras, 1, -1 do
    aura_frame = aura_frame_list[i]
    if icon_mode then
      if aura_frame.Border then
        aura_grid:UpdateAuraFrame(aura_frame)
      else
        aura_frame:Hide()
        aura_frame_list[i] = nil
      end
    else
      if aura_frame.Statusbar then
        aura_grid:UpdateAuraFrame(aura_frame)
      else
        aura_frame:Hide()
        aura_frame_list[i] = nil
      end
    end
  end

  aura_grid_frame:SetSize(aura_grid.AuraWidgetWidth, aura_grid.AuraWidgetHeight)

  if ShowDuration or not aura_grid.IconMode then
    aura_grid_frame:SetScript("OnUpdate", OnUpdateAuraGridFrame)
  else
    aura_grid_frame:SetScript("OnUpdate", nil)
  end

  aura_grid_frame:SetFrameLevel(widget_frame:GetFrameLevel())
end

-- Initialize the aura grid layout, don't update auras themselves as not unitid know at this point
function Widget:UpdateLayout(widget_frame)
  local frame_level
  if self.db.FrameOrder == "HEALTHBAR_AURAS" then
    frame_level = widget_frame:GetParent():GetFrameLevel() + 1
  else
    frame_level = widget_frame:GetParent():GetFrameLevel() + 9
  end
  widget_frame:SetFrameLevel(frame_level)

  self:UpdateAuraGridLayout(widget_frame, AURA_GRID_BUFFS)
  self:UpdateAuraGridLayout(widget_frame, AURA_GRID_DEBUFFS)
  self:UpdateAuraGridLayout(widget_frame, AURA_GRID_CROWDCONTROL)
end

local function UnitAuraEventHandler(widget_frame, event, unitid)
  --  -- Skip player (cause TP does not handle player nameplate) and target (as it is updated via it's actual unitid anyway)
  --  if unitid == "player" or unitid == "target" then return end

  if widget_frame.Active then
    widget_frame.Widget:UpdateIconGrid(widget_frame, widget_frame:GetParent().unit)
  end
end

-- For Classic: LibClassicDurations
local function UnitBuffEventHandler(event, unitid)
  local plate = GetNamePlateForUnit(unitid)
  if plate and plate.TPFrame.Active then
    local widget_frame = plate.TPFrame.widgets.Auras
    if widget_frame.Active then
      widget_frame.Widget:UpdateIconGrid(widget_frame, widget_frame:GetParent().unit)
    end
  end
end

function Widget:PLAYER_TARGET_CHANGED()
  if not self.db.ShowTargetOnly then return end

  if self.CurrentTarget then
    self.CurrentTarget:Hide()
    self.CurrentTarget = nil
  end

  local plate = GetNamePlateForUnit("target")
  if plate and plate.TPFrame.Active then
    self.CurrentTarget = plate.TPFrame.widgets.Auras

    if self.CurrentTarget.Active then
      self:UpdateIconGrid(self.CurrentTarget, plate.TPFrame.unit)
    end
  end
end

function Widget:PLAYER_REGEN_ENABLED()
  -- It seems that unitid here can be nil when using the healthstone while in combat
  -- assert (unit.unitid ~= nil, "Auras: PLAYER_REGEN_ENABLED - unitid =", unit.unitid)

  local frame
  for _, plate in pairs(GetNamePlates()) do
    frame = plate and plate.TPFrame
    if frame and frame.Active then
      local widget_frame = frame.widgets.Auras
      local unit = frame.unit

      if widget_frame.Active and unit.HasUnlimitedAuras then
        unit.isInCombat = _G.UnitAffectingCombat(unit.unitid)
        self:UpdateIconGrid(widget_frame, unit)
      end
    end
  end
end

function Widget:PLAYER_REGEN_DISABLED()
  --PLayerIsInCombat = true

  for plate, _ in pairs(Addon.PlatesVisible) do
    local widget_frame = plate.TPFrame.widgets.Auras
    local unit = plate.TPFrame.unit

    if widget_frame.Active and unit.HasUnlimitedAuras then
      unit.isInCombat = _G.UnitAffectingCombat(unit.unitid)
      self:UpdateIconGrid(widget_frame, unit)
    end
  end
end

function Widget:PLAYER_ENTERING_WORLD()
  PLayerIsInInstance = IsInInstance()
end


---------------------------------------------------------------------------------------------------
-- Auras Area
---------------------------------------------------------------------------------------------------

local function CreateAuraGrid(self, parent)
  local aura_grid_frame = _G.CreateFrame("Frame", nil, parent)
  aura_grid_frame.AuraFrames = {}
  aura_grid_frame.ActiveAuras = 0
  aura_grid_frame.AuraGrid = self

  return aura_grid_frame
end

local function HideNonActiveAuras(self, aura_grid_frame, stop_highlight)
  local aura_frames = aura_grid_frame.AuraFrames
  for i = aura_grid_frame.ActiveAuras + 1, #aura_frames do
    aura_frames[i]:Hide()
    if stop_highlight then
      AuraHighlightStop(aura_frames[i].Highlight)
    end
  end
end

local function GetAuraFrame(self, aura_grid_frame, no)
  local aura_frame_list = aura_grid_frame.AuraFrames

  local aura_frame = aura_frame_list[no]
  if aura_frame == nil then
    -- Should always be #aura_frame_list + 1
    aura_frame = self:CreateAuraFrame(aura_grid_frame)

    local align_layout = self.AlignLayout
    aura_frame:ClearAllPoints()
    if no == 1 then
      aura_frame:SetPoint(align_layout[3], aura_grid_frame, self.AuraWidgetOffset * align_layout[5], (self.AuraWidgetOffset + self.RowSpacing) * align_layout[6])
    elseif (no - 1) % self.Columns == 0 then
      aura_frame:SetPoint(align_layout[3], aura_frame_list[no - self.Columns], align_layout[4], 0, self.RowSpacing * align_layout[6])
    else
      aura_frame:SetPoint(align_layout[1], aura_frame_list[no - 1], align_layout[2], self.ColumnSpacing * align_layout[5], 0)
    end

    self:UpdateAuraFrame(aura_frame)

    aura_frame_list[no] = aura_frame
  end

  return aura_frame
end

---------------------------------------------------------------------------------------------------
-- Functions for the aura grid with icons
---------------------------------------------------------------------------------------------------

local function CreateAuraFrameIconMode(self, parent)
  local frame = _G.CreateFrame("Frame", nil, parent)
  frame:SetFrameLevel(parent:GetFrameLevel())

  frame.Icon = frame:CreateTexture(nil, "ARTWORK", nil, -5)
  frame.Border = _G.CreateFrame("Frame", nil, frame, BackdropTemplate)
  frame.Border:SetFrameLevel(parent:GetFrameLevel())
  frame.Cooldown = CreateCooldown(frame)
  frame.Cooldown:SetFrameLevel(parent:GetFrameLevel())

  frame.Highlight = _G.CreateFrame("Frame", nil, frame)
  frame.Highlight:SetFrameLevel(parent:GetFrameLevel())
  frame.Highlight:SetPoint("CENTER")

  -- Use a seperate frame for text elements as a) using frame as parent results in the text being shown below
  -- the cooldown frame and b) using the cooldown frame results in the text not being visible if there is no
  -- cooldown (i.e., duration and expiration are nil which is true for auras with unlimited duration)
  local text_frame = _G.CreateFrame("Frame", nil, frame)
  text_frame:SetFrameLevel(parent:GetFrameLevel())
  text_frame:SetAllPoints(frame.Icon)
  frame.Stacks = text_frame:CreateFontString(nil, "OVERLAY")
  frame.TimeLeft = text_frame:CreateFontString(nil, "OVERLAY")

  frame:Hide()

  return frame
end

local function UpdateAuraFrameIconMode(self, frame)
  local db = self.db_widget

  UpdateCooldown(frame.Cooldown, db)
  if ShowDuration then
    frame.TimeLeft:Show()
  else
    frame.TimeLeft:Hide()
  end

  -- Add tooltips to icons
  if db.ShowTooltips then
    frame:SetScript("OnEnter", AuraFrameOnEnter)
    frame:SetScript("OnLeave", AuraFrameOnLeave)
  else
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
  end

  db = self.db

  -- Icon
  frame:SetSize(db.IconWidth, db.IconHeight)
  frame.Icon:SetAllPoints(frame)
  --frame.Icon:SetTexCoord(.07, 1-.07, .23, 1-.23) -- Style: Widee
  frame.Icon:SetTexCoord(.10, 1-.07, .12, 1-.12)  -- Style: Square - remove border from icons

  if db.ShowBorder then
    local offset, edge_size, inset = 2, 8, 0
    frame.Border:ClearAllPoints()
    frame.Border:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    frame.Border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    frame.Border:SetBackdrop({
      edgeFile = Widget.TEXTURE_BORDER,
      edgeSize = edge_size,
      insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    frame.Border:SetBackdropBorderColor(0, 0, 0, 1)
    frame.Border:Show()

  else
    frame.Border:Hide()
  end

  AuraHighlightStopPrevious(frame.Highlight)
  if AuraHighlightEnabled then
    frame.Highlight:SetSize(frame:GetWidth() + AuraHighlightOffset, frame:GetHeight() + AuraHighlightOffset)
  end

  Font:UpdateText(frame, frame.TimeLeft, db.Duration)
  Font:UpdateText(frame, frame.Stacks, db.StackCount)
end

local function UpdateAuraInformationIconMode(self, aura_frame) -- texture, duration, expiration, stacks, color, name)
  local duration = aura_frame.AuraDuration
  local expiration = aura_frame.AuraExpiration
  local stacks = aura_frame.AuraStacks
  local color = aura_frame.AuraColor

  -- Expiration
  self:UpdateWidgetTime(aura_frame, expiration, duration)

  local db_widget = self.db_widget
  if db_widget.ShowStackCount and stacks > 1 then
    aura_frame.Stacks:SetText(stacks)
  else
    aura_frame.Stacks:SetText("")
  end

  aura_frame.Icon:SetTexture(aura_frame.AuraTexture)

  -- Highlight Coloring
  if self.db.ShowBorder then
    if db_widget.ShowAuraType then
      aura_frame.Border:SetBackdropBorderColor(color.r, color.g, color.b, 1)
    end
  end

  if AuraHighlightEnabled then
    if aura_frame.AuraStealOrPurge then
      AuraHighlightStart(aura_frame.Highlight, AuraHighlightColor, 0)
    else
      AuraHighlightStop(aura_frame.Highlight)
    end
  end

  SetCooldown(aura_frame.Cooldown, duration, expiration)
  Animations:StopFlash(aura_frame)

  aura_frame:Show()
end

local function UpdateWidgetTimeIconMode(self, aura_frame, expiration, duration)
  if expiration == 0 then
    aura_frame.TimeLeft:SetText("")
    Animations:StopFlash(aura_frame)
  else
    local timeleft = expiration - GetTime()  
    if timeleft > 60 then
      aura_frame.TimeLeft:SetText(floor(timeleft/60).."m")
    else
      aura_frame.TimeLeft:SetText(floor(timeleft))
    end

    local db_widget = self.db_widget
    if db_widget.FlashWhenExpiring and timeleft < db_widget.FlashTime then
      Animations:Flash(aura_frame, FLASH_DURATION)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Functions for the aura grid with bars
---------------------------------------------------------------------------------------------------

local function CreateAuraFrameBarMode(self, parent)
  local db = self.db
  local font = Addon.LibSharedMedia:Fetch('font', db.Font)

  -- frame is probably not necessary, should be ok do add everything to the statusbar frame
  local frame = _G.CreateFrame("Frame", nil, parent)
  frame:SetFrameLevel(parent:GetFrameLevel())

  frame.Statusbar = _G.CreateFrame("StatusBar", nil, frame)
  frame.Statusbar:SetFrameLevel(parent:GetFrameLevel())
  frame.Statusbar:SetMinMaxValues(0, 100)

  frame.Background = frame.Statusbar:CreateTexture(nil, "BACKGROUND", nil, 0)
  frame.Background:SetAllPoints()

  frame.Highlight = _G.CreateFrame("Frame", nil, frame)
  frame.Highlight:SetFrameLevel(parent:GetFrameLevel())

  frame.Icon = frame:CreateTexture(nil, "ARTWORK", nil, -5)

  frame.Stacks = frame.Statusbar:CreateFontString(nil, "OVERLAY")
  frame.Stacks:SetAllPoints(frame.Icon)
  --frame.Stacks:SetFont("Fonts\\FRIZQT__.TTF", 11)

  frame.LabelText = frame.Statusbar:CreateFontString(nil, "OVERLAY")
  frame.LabelText:SetAllPoints(frame.Statusbar)
  frame.TimeText = frame.Statusbar:CreateFontString(nil, "OVERLAY")
  frame.TimeText:SetAllPoints(frame.Statusbar)

  frame.Cooldown = CreateCooldown(frame)
  frame.Cooldown:SetFrameLevel(parent:GetFrameLevel())

  frame:Hide()

  return frame
end

local function UpdateAuraFrameBarMode(self, frame)
  local db = self.db_widget

  UpdateCooldown(frame.Cooldown, db)
  if ShowDuration then
    frame.TimeText:Show()
  else
    frame.TimeText:Hide()
  end

  -- Add tooltips to icons
  if db.ShowTooltips then
    frame:SetScript("OnEnter", AuraFrameOnEnter)
    frame:SetScript("OnLeave", AuraFrameOnLeave)
  else
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
  end

  db = self.db
  local font = Addon.LibSharedMedia:Fetch('font', db.Font)

  -- width and position calculations
  local frame_width = db.BarWidth
  if db.ShowIcon then
    frame_width = frame_width + db.BarHeight + db.IconSpacing
  end
  frame:SetSize(frame_width, db.BarHeight)

  frame.Background:SetTexture(Addon.LibSharedMedia:Fetch('statusbar', db.BackgroundTexture))
  frame.Background:SetVertexColor(db.BackgroundColor.r, db.BackgroundColor.g, db.BackgroundColor.b, db.BackgroundColor.a)

  frame.Icon:ClearAllPoints()
  frame.Statusbar:ClearAllPoints()

  if db.ShowIcon then
    if db.IconAlignmentLeft then
      frame.Icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
      frame.Statusbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", db.BarHeight + db.IconSpacing, 0)
    else
      frame.Icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", db.BarWidth + db.IconSpacing, 0)
      frame.Statusbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    end

    Font:UpdateText(frame.Icon, frame.Stacks, db.StackCount)

    frame.Icon:SetTexCoord(0, 1, 0, 1)
    frame.Icon:SetSize(db.BarHeight, db.BarHeight)
    frame.Icon:Show()
  else
    frame.Statusbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.Icon:Hide()
  end

  Font:UpdateText(frame.Statusbar, frame.LabelText, db.Label)
  Font:UpdateText(frame.Statusbar, frame.TimeText, db.Duration)

  AuraHighlightStopPrevious(frame.Highlight)
  if AuraHighlightEnabled then
    local aura_highlight = frame.Highlight

    aura_highlight:ClearAllPoints()
    if self.db_widget.Highlight.Type == "ActionButton" then
      -- Align to icon because of bad scaling otherwise
      local offset = - (AuraHighlightOffset * 0.5)
      if db.IconAlignmentLeft then
        aura_highlight:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, offset)
      else
        aura_highlight:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", db.BarWidth + db.IconSpacing + offset, offset)
      end
      aura_highlight:SetSize(db.BarHeight + AuraHighlightOffset, db.BarHeight + AuraHighlightOffset)
    else
      aura_highlight:SetPoint("CENTER")
      aura_highlight:SetSize(frame:GetWidth() + AuraHighlightOffset, frame:GetHeight() + AuraHighlightOffset)
    end
  end

  frame.Statusbar:SetSize(db.BarWidth, db.BarHeight)
  frame.Statusbar:SetStatusBarTexture(Addon.LibSharedMedia:Fetch('statusbar', db.Texture))
  frame.Statusbar:GetStatusBarTexture():SetHorizTile(false)
  frame.Statusbar:GetStatusBarTexture():SetVertTile(false)
end

local function UpdateAuraInformationBarMode(self, aura_frame) -- texture, duration, expiration, stacks, color, name)
  local db = self.db

  local duration = aura_frame.AuraDuration
  local expiration = aura_frame.AuraExpiration
  local stacks = aura_frame.AuraStacks
  local color = aura_frame.AuraColor

  -- Expiration
  self:UpdateWidgetTime(aura_frame, expiration, duration)

  if stacks > 1 and self.db_widget.ShowStackCount then
    -- Stacks are either shown on the icon or as postfix to the aura name when
    -- a) OmniCC is enabled (which shows the CD on the icon) or the icon is disabled
    if not db.ShowIcon or not HideOmniCC then
      aura_frame.Stacks:Hide()
      aura_frame.AuraName = aura_frame.AuraName .. " (" .. stacks .. ")"
    else
      aura_frame.Stacks:SetText(stacks)
      aura_frame.Stacks:Show()
    end
  else
    aura_frame.Stacks:Hide()
  end

  -- Icon
  if db.ShowIcon then
    aura_frame.Icon:SetTexture(aura_frame.AuraTexture)
  end

  if AuraHighlightEnabled then
    if aura_frame.AuraStealOrPurge then
      AuraHighlightStart(aura_frame.Highlight, AuraHighlightColor, 0)
    else
      AuraHighlightStop(aura_frame.Highlight)
    end
  end

  aura_frame.LabelText:SetText(aura_frame.AuraName)
  -- Highlight Coloring
  aura_frame.Statusbar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)

  SetCooldown(aura_frame.Cooldown, duration, expiration)
  Animations:StopFlash(aura_frame)

  aura_frame:Show()
end

local function UpdateWidgetTimeBarMode(self, aura_frame, expiration, duration)
  if duration == 0 then
    aura_frame.TimeText:SetText("")
    aura_frame.Statusbar:SetValue(100)
    Animations:StopFlash(aura_frame)
  elseif expiration == 0 then
    aura_frame.TimeText:SetText("")
    aura_frame.Statusbar:SetValue(0)
    Animations:StopFlash(aura_frame)
  else
    local db = self.db_widget

    local timeleft = expiration - GetTime()

    if db.ShowDuration then
      if timeleft > 60 then
        aura_frame.TimeText:SetText(floor(timeleft/60).."m")
      else
        aura_frame.TimeText:SetText(floor(timeleft))
      end

      if db.FlashWhenExpiring and timeleft < db.FlashTime then
        Animations:Flash(aura_frame, FLASH_DURATION)
      end
    else
      aura_frame.TimeText:SetText("")

      if db.FlashWhenExpiring and timeleft < db.FlashTime then
        Animations:Flash(aura_frame, FLASH_DURATION)
      end
    end

    aura_frame.Statusbar:SetValue(timeleft * 100 / duration)
  end
end

local function UpdateWidgetTimeBarModeNoDuration(self, aura_frame, expiration, duration)
  if duration == 0 then
    aura_frame.Statusbar:SetValue(100)
    Animations:StopFlash(aura_frame)
  elseif expiration == 0 then
    aura_frame.Statusbar:SetValue(0)
    Animations:StopFlash(aura_frame)
  else
    local timeleft = expiration - GetTime()
    if timeleft > 60 then
      aura_frame.TimeText:SetText(floor(timeleft/60).."m")
    else
      aura_frame.TimeText:SetText(floor(timeleft))
    end

    local db = self.db_widget
    if db.FlashWhenExpiring and timeleft < db.FlashTime then
      Animations:Flash(aura_frame, FLASH_DURATION)
    end

    aura_frame.Statusbar:SetValue(timeleft * 100 / duration)
  end
end

---------------------------------------------------------------------------------------------------
-- Widget functions for creation and update
---------------------------------------------------------------------------------------------------

function Widget:Create(tp_frame)
  -- Required Widget Code
  local widget_frame = _G.CreateFrame("Frame", nil, tp_frame)
  widget_frame:Hide()

  -- Custom Code
  --------------------------------------
  widget_frame:SetAllPoints(tp_frame)

  widget_frame.Buffs = self.Buffs:Create(widget_frame)
  widget_frame.Debuffs = self.Debuffs:Create(widget_frame)
  widget_frame.CrowdControl = self.CrowdControl:Create(widget_frame)

  widget_frame.Widget = self

  self:UpdateLayout(widget_frame)

  widget_frame:SetScript("OnEvent", UnitAuraEventHandler)
  widget_frame:HookScript("OnShow", OnShowHookScript)
  -- widget_frame:HookScript("OnHide", OnHideHookScript)
  --------------------------------------
  -- End Custom Code

  return widget_frame
end

function Widget:IsEnabled()
  self.db = Addon.db.profile.AuraWidget
  return self.db.ON or self.db.ShowInHeadlineView
end

function Widget:OnEnable()
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- LOSS_OF_CONTROL_ADDED
  -- LOSS_OF_CONTROL_UPDATE

  if Addon.IS_CLASSIC then
    UnitAuraWrapper = Addon.LibClassicDurations.UnitAuraWithBuffs

    -- Add duration handling from LibClassicDurations
    Addon.LibClassicDurations:Register("ThreatPlates")
    -- NOTE: Enemy buff tracking won't start until you register UNIT_BUFF
    Addon.LibClassicDurations.RegisterCallback(TidyPlatesThreat, "UNIT_BUFF", UnitBuffEventHandler)
  end
end

function Widget:OnDisable()
  self:UnregisterAllEvents()
  if Addon.IS_CLASSIC then
    Addon.LibClassicDurations.UnregisterCallback(TidyPlatesThreat, "UNIT_BUFF")
  end
  for plate, _ in pairs(Addon.PlatesVisible) do
    plate.TPFrame.widgets.Auras:UnregisterAllEvents()
  end
end

function Widget:EnabledForStyle(style, unit)
  if (style == "NameOnly" or style == "NameOnly-Unique") then
    return self.db.ShowInHeadlineView or Addon.ActiveAuraTriggers
  elseif style ~= "etotem" then
    return self.db.ON or Addon.ActiveAuraTriggers
  end
end

function Widget:OnUnitAdded(widget_frame, unit)
  local db = self.db

  -- if db.SwitchScaleByReaction and UnitReaction(unit.unitid, "player") > 4 then
  --   print ("Scale: Buffs =", self.SwitchScaleBuffsFactor, "- Debuffs =", self.SwitchScaleDebuffsFactor)
  --   widget_frame.Buffs:SetScale(self.SwitchScaleBuffsFactor)
  --   widget_frame.Debuffs:SetScale(self.SwitchScaleDebuffsFactor)
  -- else
  --   widget_frame.Buffs:SetScale(1)
  --   widget_frame.Debuffs:SetScale(1)
  -- end

  widget_frame:UnregisterAllEvents()
  widget_frame:RegisterUnitEvent("UNIT_AURA", unit.unitid)

  self:UpdateIconGrid(widget_frame, unit)
end

function Widget:OnUnitRemoved(widget_frame, unit)
  widget_frame:UnregisterAllEvents()
end

local function ParseFilter(filter_by_spell)
  local filter = {}
  local only_player_auras = true

  local modifier, spell
  for key, value in pairs(filter_by_spell) do
    -- remove comments and whitespaces from the filter (string)
    local pos = value:find("%-%-")
    if pos then value = value:sub(1, pos - 1) end
    value = value:match("^%s*(.-)%s*$")  -- remove any leading/trailing whitespaces from the line

    -- value:match("^%s*(%w+)%s*(.-)%s*$")  -- remove any leading/trailing whitespaces from the line
    if value:sub(1, 4) == "All " then
      modifier = "All"
      spell = value:match("^All%s*(.-)$")
      only_player_auras = false
    elseif value:sub(1, 3) == "My " then
      modifier = "My"
      spell = value:match("^My%s*(.-)$")
    elseif value:sub(1, 4) == "Not " then
      modifier = "Not"
      spell = value:match("^Not%s*(.-)$")
      only_player_auras = false
    else
      modifier = true
      spell = value
    end

    -- separete filter by name and ID for more efficient aura filtering
    local spell_no = tonumber(spell)
    if spell_no then
      filter[spell_no] = modifier
    elseif spell ~= '' then
      filter[spell] = modifier
    end
  end

  return filter
end

function Widget:ParseSpellFilters()
  self.db = Addon.db.profile.AuraWidget

  self.AuraFilterBuffs = ParseFilter(self.db.Buffs.FilterBySpell)
  self.AuraFilterDebuffs = ParseFilter(self.db.Debuffs.FilterBySpell)
  self.AuraFilterCrowdControl = ParseFilter(self.db.CrowdControl.FilterBySpell)
end

-- function Widget:UpdateSizeDataIconMode(aura_grid, db)
--   aura_grid.AuraWidth = db.IconWidth + db.ColumnSpacing
--   aura_grid.AuraHeight = db.IconHeight + db.RowSpacing
--   aura_grid.RowSpacing = db.RowSpacing
--   aura_grid.ColumnSpacing = db.ColumnSpacing

--   aura_grid.AuraWidgetWidth = (db.IconWidth * db.Columns) + (db.ColumnSpacing * db.Columns) - db.ColumnSpacing + (aura_grid.AuraWidgetOffset * 2)
--   aura_grid.AuraWidgetHeight = (db.IconHeight * db.Rows) + (db.RowSpacing * db.Rows) - db.RowSpacing + (aura_grid.AuraWidgetOffset * 2)

--   for i = 1, db.Columns do
--     local active_auras_width = (db.IconWidth * i) + (db.ColumnSpacing * i) - db.ColumnSpacing + (aura_grid.AuraWidgetOffset * 2)
--     aura_grid.CenterAurasPositions[i] = (aura_grid.AuraWidgetWidth - active_auras_width) / 2
--   end
-- end

function Widget:UpdateSettingsIconMode(aura_type, filter)
  local aura_grid = self[aura_type]

  local db = self.db[aura_type].ModeIcon
  aura_grid.db = db
  aura_grid.db_widget = self.db

  aura_grid.UpdateInterval = Addon.ON_UPDATE_INTERVAL
  aura_grid.AlignLayout = GRID_LAYOUT[self.db[aura_type].AlignmentH][self.db[aura_type].AlignmentV]

  aura_grid.Columns = db.Columns
  aura_grid.MaxAuras = min(db.MaxAuras, db.Rows * db.Columns)

  aura_grid.AuraWidgetOffset = (self.db.ShowAuraType and 2) or 1

  aura_grid.AuraWidth = db.IconWidth + db.ColumnSpacing
  aura_grid.AuraHeight = db.IconHeight + db.RowSpacing
  aura_grid.RowSpacing = db.RowSpacing
  aura_grid.ColumnSpacing = db.ColumnSpacing

  aura_grid.AuraWidgetWidth = (db.IconWidth * db.Columns) + (db.ColumnSpacing * db.Columns) - db.ColumnSpacing + (aura_grid.AuraWidgetOffset * 2)
  aura_grid.AuraWidgetHeight = (db.IconHeight * db.Rows) + (db.RowSpacing * db.Rows) - db.RowSpacing + (aura_grid.AuraWidgetOffset * 2)

  for i = 1, db.Columns do
    local active_auras_width = (db.IconWidth * i) + (db.ColumnSpacing * i) - db.ColumnSpacing + (aura_grid.AuraWidgetOffset * 2)
    aura_grid.CenterAurasPositions[i] = (aura_grid.AuraWidgetWidth - active_auras_width) / 2
  end

  aura_grid.CreateAuraFrame = CreateAuraFrameIconMode
  aura_grid.UpdateAuraFrame = UpdateAuraFrameIconMode
  aura_grid.UpdateAuraInformation = UpdateAuraInformationIconMode
  aura_grid.UpdateWidgetTime = UpdateWidgetTimeIconMode

  aura_grid.Create = CreateAuraGrid
  aura_grid.GetAuraFrame = GetAuraFrame
  aura_grid.HideNonActiveAuras = HideNonActiveAuras
end


-- function Widget:UpdateSizeDataBarMode(aura_grid, db)
--   aura_grid.AuraWidth = db.BarWidth
--   aura_grid.AuraHeight = db.BarHeight + db.BarSpacing
--   aura_grid.RowSpacing = db.BarSpacing
--   aura_grid.ColumnSpacing = 0

--   if db.ShowIcon then
--     aura_grid.AuraWidgetWidth = db.BarWidth + db.BarHeight + db.IconSpacing
--   else
--     aura_grid.AuraWidgetWidth = db.BarWidth
--   end
--   aura_grid.AuraWidgetHeight = (db.BarHeight * db.MaxBars) + (db.BarSpacing * db.MaxBars) - db.BarSpacing + (aura_grid.AuraWidgetOffset * 2)
-- end

function Widget:UpdateSettingsBarMode(aura_type, filter)
  local aura_grid = self[aura_type]

  local db = self.db[aura_type].ModeBar
  aura_grid.db = db
  aura_grid.db_widget = self.db

  aura_grid.UpdateInterval = 1 / GetFramerate()
  aura_grid.AlignLayout = GRID_LAYOUT[self.db[aura_type].AlignmentH][self.db[aura_type].AlignmentV]

  aura_grid.Columns = 1
  aura_grid.MaxAuras = db.MaxBars

  aura_grid.AuraWidgetOffset = 0

  aura_grid.AuraWidth = db.BarWidth
  aura_grid.AuraHeight = db.BarHeight + db.BarSpacing
  aura_grid.RowSpacing = db.BarSpacing
  aura_grid.ColumnSpacing = 0

  if db.ShowIcon then
    aura_grid.AuraWidgetWidth = db.BarWidth + db.BarHeight + db.IconSpacing
  else
    aura_grid.AuraWidgetWidth = db.BarWidth
  end
  aura_grid.AuraWidgetHeight = (db.BarHeight * db.MaxBars) + (db.BarSpacing * db.MaxBars) - db.BarSpacing + (aura_grid.AuraWidgetOffset * 2)

  aura_grid.CreateAuraFrame = CreateAuraFrameBarMode
  aura_grid.UpdateAuraFrame = UpdateAuraFrameBarMode
  aura_grid.UpdateAuraInformation = UpdateAuraInformationBarMode

  if ShowDuration then
    aura_grid.UpdateWidgetTime = UpdateWidgetTimeBarMode
  else
    aura_grid.UpdateWidgetTime = UpdateWidgetTimeBarModeNoDuration
  end

  aura_grid.Create = CreateAuraGrid
  aura_grid.GetAuraFrame = GetAuraFrame
  aura_grid.HideNonActiveAuras = HideNonActiveAuras
end

-- Load settings from the configuration which are shared across all aura widgets
-- used (for each widget) in UpdateWidgetConfig
function Widget:UpdateSettings()
  self.db = Addon.db.profile.AuraWidget

  self.Buffs.IconMode = not self.db.Buffs.ModeBar.Enabled
  self.Debuffs.IconMode = not self.db.Debuffs.ModeBar.Enabled
  self.CrowdControl.IconMode = not self.db.CrowdControl.ModeBar.Enabled

  if self.Buffs.IconMode then
    self:UpdateSettingsIconMode(AURA_GRID_BUFFS)
  else
    self:UpdateSettingsBarMode(AURA_GRID_BUFFS)
  end

  if self.Debuffs.IconMode then
    self:UpdateSettingsIconMode(AURA_GRID_DEBUFFS)
  else
    self:UpdateSettingsBarMode(AURA_GRID_DEBUFFS)
  end

  if self.CrowdControl.IconMode then
    self:UpdateSettingsIconMode(AURA_GRID_CROWDCONTROL)
  else
    self:UpdateSettingsBarMode(AURA_GRID_CROWDCONTROL)
  end

  -- local buffs_size = (self.Buffs.IconMode and max(self.db.Buffs.ModeIcon.IconWidth, self.db.Buffs.ModeIcon.IconHeight)) or self.db.Buffs.ModeBar.BarHeight
  -- local debuffs_size = (self.Debuffs.IconMode and max(self.db.Debuffs.ModeIcon.IconWidth, self.db.Debuffs.ModeIcon.IconHeight)) or self.db.Debuffs.ModeBar.BarHeight

  -- self.SwitchScaleBuffsFactor = debuffs_size/ buffs_size
  -- self.SwitchScaleDebuffsFactor = buffs_size / debuffs_size

  self:ParseSpellFilters()

  HideOmniCC = not self.db.ShowOmniCC
  ShowDuration = self.db.ShowDuration and not self.db.ShowOmniCC
  --  -- Don't update any widget frame if the widget isn't enabled.
--  if not self:IsEnabled() then return end

  -- Highlighting
  AuraHighlightEnabled = self.db.Highlight.Enabled
  local glow_function = CUSTOM_GLOW_FUNCTIONS[self.db.Highlight.Type][1]
  AuraHighlightStart = CUSTOM_GLOW_WRAPPER_FUNCTIONS[glow_function] or Addon.LibCustomGlow[glow_function]
  AuraHighlightStopPrevious = AuraHighlightStop or Addon.LibCustomGlow.PixelGlow_Stop
  AuraHighlightStop = Addon.LibCustomGlow[CUSTOM_GLOW_FUNCTIONS[self.db.Highlight.Type][2]]
  AuraHighlightOffset = CUSTOM_GLOW_FUNCTIONS[self.db.Highlight.Type][3]

  local color = (self.db.Highlight.CustomColor and self.db.Highlight.Color) or ThreatPlates.DEFAULT_SETTINGS.profile.AuraWidget.Highlight.Color
  AuraHighlightColor[1] = color.r
  AuraHighlightColor[2] = color.g
  AuraHighlightColor[3] = color.b
  AuraHighlightColor[4] = color.a

  EnabledForStyle["NameOnly"] = self.db.ShowInHeadlineView
  EnabledForStyle["NameOnly-Unique"] = self.db.ShowInHeadlineView
  EnabledForStyle["dps"] = self.db.ON
  EnabledForStyle["tank"] = self.db.ON
  EnabledForStyle["normal"] = self.db.ON
  EnabledForStyle["totem"] = self.db.ON
  EnabledForStyle["unique"] = self.db.ON
  EnabledForStyle["etotem"] = false
  EnabledForStyle["empty"] = false
end

---------------------------------------------------------------------------------------------------
-- Configuration Mode
---------------------------------------------------------------------------------------------------

local EnabledConfigMode = false
local OldUnitAura
local Timer

local ConfigModeAuras = {
  HARMFUL = {},
  HELPFUL = {}
}

local DEMO_AURA_ICONS = {
  Buffs = { 136085, 132179, 135869, 135962, 135902, 136205, 136114, 136148, 132333 },
  Debuffs = { 132122, 132212, 135812, 135959, 136207, 132273, 135813, 136118, 132155 },
  CrowdControl = { 132114, 132118, 136071, 135963, 136184, 136175, 135849, 136183, 132316 },
}

local function GenerateDemoAuras()
  for no = 1, 40 do
    --aura.name, aura.texture, aura.stacks, aura.type, aura.duration, aura.expiration, aura.caster,
    --aura.StealOrPurge, aura.ShowPersonal, aura.spellid, aura.PlayerCanApply, aura.BossDebuff, isCastByPlayer, aura.ShowAll
    local random_name = tostring(math.random(1, 40))

    local aura_duration = math.random(3, 120)
    local aura_expiration = GetTime() + aura_duration
    local aura_name, aura_texture, aura_stacks, aura_type, aura_caster, aura_spellid, aura_steal, aura_show_all
    if no % 2 == 0 then
      aura_name = "Rake" .. random_name
      aura_texture = DEMO_AURA_ICONS.Debuffs[math.random(1, #DEMO_AURA_ICONS.Debuffs)]
      aura_stacks, aura_type, aura_caster, aura_spellid, aura_steal, aura_show_all = 3, nil, "player", 1822, false, false
    else
      aura_name = "Bash" .. random_name
      aura_texture = DEMO_AURA_ICONS.CrowdControl[math.random(1, #DEMO_AURA_ICONS.CrowdControl)]
      aura_stacks, aura_type, aura_caster, aura_spellid, aura_steal, aura_show_all = 2, nil, "player", 5211, false, true
    end
    ConfigModeAuras.HARMFUL[no] = { aura_name, aura_texture, aura_stacks, aura_type, aura_duration, aura_expiration, aura_caster, aura_steal, false, aura_spellid, true, false, true, aura_show_all, 1 }

    aura_name = "Regrowth" .. random_name
    aura_expiration = GetTime() + aura_duration
    aura_texture = DEMO_AURA_ICONS.Buffs[math.random(1, #DEMO_AURA_ICONS.Buffs)]
    aura_stacks, aura_type, aura_caster, aura_spellid, aura_steal = 5, "Magic", "nameplate1", 8936, no % 5 == 0
    ConfigModeAuras.HELPFUL[no] = { aura_name, aura_texture, aura_stacks, aura_type, aura_duration, aura_expiration, aura_caster, aura_steal, false, aura_spellid, true, false, true, false, 1 }
  end
end

local function UnitAuraForConfigurationMode(unitid, i, effect)
  local aura = ConfigModeAuras[effect][i]
  if aura then
    return unpack(aura)
  else
    return nil
  end
end

local function TimerCallback()
  for no = 40, 1, -1 do
    local aura = ConfigModeAuras.HARMFUL[no]
    if aura and aura[6] < GetTime() then
      table.remove(ConfigModeAuras.HARMFUL, no)
    end
    aura = ConfigModeAuras.HELPFUL[no]
    if aura and aura[6] < GetTime() then
      table.remove(ConfigModeAuras.HELPFUL, no)
    end
  end

  if #ConfigModeAuras.HARMFUL + #ConfigModeAuras.HELPFUL == 0 then
    GenerateDemoAuras()
  end

  for plate, unitid in pairs(Addon.PlatesVisible) do
    if plate.TPFrame.Active then
      Widget:UpdateIconGrid(plate.TPFrame.widgets.Auras, plate.TPFrame.unit)
    end
  end
end

function Widget:ToggleConfigurationMode()

  if not EnabledConfigMode then
    EnabledConfigMode = true

    GenerateDemoAuras()
    OldUnitAura = UnitAuraWrapper
    UnitAuraWrapper = UnitAuraForConfigurationMode

    Addon:ForceUpdate()
    Timer = C_Timer.NewTicker(0.5, TimerCallback)
  else
    EnabledConfigMode = false

    UnitAuraWrapper = OldUnitAura
    Timer:Cancel()

    Addon:ForceUpdate()
  end
end