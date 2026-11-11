-- ClassPages: Hunter profile. Spell IDs are the rank-1 IDs; ns.Spellbook.Resolve maps them to the highest known rank.
-- Spells the character does not know (yet) are skipped when a preset is filled, so one profile serves level 10 and
-- level 60, every talent build and Forever's reworked spells (unknown keys just stay empty).
-- Pet details (happiness, loyalty, stable, beast training) live in Classes/HunterPets.lua.
local ADDON, ns = ...
local L = ns.L

ns.Classes:Register({
  class = "HUNTER",
  color = { 0.67, 0.83, 0.45 },
  icon = "Interface\\Icons\\ClassIcon_Hunter",
  tabs = { "pets" },

  spells = {
    autoShot = 75, huntersMark = 1130, serpentSting = 1978, arcaneShot = 3044, multiShot = 2643, aimedShot = 19434,
    concussiveShot = 5116, rapidFire = 3045, volley = 1510, scatterShot = 19503, tranqShot = 19801, viperSting = 3034,
    scorpidSting = 3043, distractingShot = 20736, flare = 1543,
    raptorStrike = 2973, mongooseBite = 1495, counterattack = 19306, wingClip = 2974, disengage = 781,
    intimidation = 19577, bestialWrath = 19574, deterrence = 19263, feignDeath = 5384,
    freezingTrap = 1499, frostTrap = 13809, immolationTrap = 13795, explosiveTrap = 13813,
    aspectHawk = 13165, aspectMonkey = 13163, aspectCheetah = 5118, aspectPack = 13159, aspectWild = 20043, aspectBeast = 13161,
    callPet = 883, dismissPet = 2641, revivePet = 982, mendPet = 136, feedPet = 6991, tameBeast = 1515,
    beastTraining = 5149, eyesOfTheBeast = 1002, beastLore = 1462, scareBeast = 1513,
  },

  -- Usable only right after an event: the HUD lights them up while usable (no combat log needed).
  reactive = {
    { key = "counterattack", hint = "usable after you parry" },
    { key = "mongooseBite", hint = "usable after the target dodges" },
  },

  presets = {
    { key = "shots", title = "Shots", kind = "attacks", cols = 8, rows = 1, size = 40, point = { "BOTTOM", 0, 215 }, enabled = true,
      spells = { "autoShot", "huntersMark", "serpentSting", "arcaneShot", "multiShot", "aimedShot", "concussiveShot", "rapidFire" } },
    { key = "melee", title = "Melee & reactive", kind = "attacks", cols = 6, rows = 1, size = 36, point = { "BOTTOM", 0, 262 }, enabled = true,
      spells = { "raptorStrike", "mongooseBite", "counterattack", "wingClip", "disengage", "scatterShot" } },
    { key = "pet", title = "Pet", kind = "pet", cols = 10, rows = 1, size = 28, point = { "BOTTOM", 0, 178 }, enabled = true, generator = "pet" },
    { key = "traps", title = "Traps & aspects", kind = "utility", cols = 4, rows = 3, size = 32, point = { "BOTTOMRIGHT", -300, 120 }, enabled = true,
      spells = { "freezingTrap", "frostTrap", "immolationTrap", "explosiveTrap", "aspectHawk", "aspectMonkey", "aspectCheetah", "aspectPack",
        "aspectWild", "aspectBeast", "feignDeath", "deterrence" } },
    { key = "petcare", title = "Pet care", kind = "utility", cols = 5, rows = 2, size = 28, point = { "BOTTOMRIGHT", -300, 240 }, enabled = false,
      spells = { "callPet", "dismissPet", "revivePet", "mendPet", "feedPet", "tameBeast", "beastTraining", "eyesOfTheBeast", "beastLore", "scareBeast" } },
    { key = "cds", title = "Cooldowns", kind = "attacks", cols = 4, rows = 1, size = 36, point = { "BOTTOM", 230, 215 }, enabled = false,
      spells = { "rapidFire", "bestialWrath", "intimidation", "volley" } },
    { key = "professions", title = "Professions", kind = "professions", cols = 4, rows = 1, size = 32, point = { "BOTTOMLEFT", 300, 120 }, enabled = false, generator = "professions" },
  },

  -- counted buttons: ammunition on the ranged attack, orange below 200
  counters = {
    autoShot = { low = 200, count = function()
      if not (GetInventoryItemCount and GetInventoryItemID) then return nil end
      if not GetInventoryItemID("player", 0) then return 0 end
      return GetInventoryItemCount("player", 0)
    end },
  },

  -- two overview cards (docs/mockups: "Begleiter", "Munition")
  overviewCards = function()
    local cards = {}
    if ns.HunterPets then cards[#cards + 1] = { title = "Pet", note = ns.HunterPets.Current().name, rows = ns.HunterPets.OverviewRows() } end
    local rows = {}
    local ammo = GetInventoryItemCount and GetInventoryItemCount("player", 0)
    if ammo and not ns.Secret.IsSecret(ammo) then
      rows[#rows + 1] = { label = "In the quiver", value = tostring(ammo), color = ammo < 200 and { 1, 0.42, 0.3 } or nil }
      if ammo < 200 then rows[#rows + 1] = { label = "Note", value = L["Restock ammunition"], color = { 1, 0.42, 0.3 } } end
    else
      rows[#rows + 1] = { label = "In the quiver", value = "?" }
    end
    cards[#cards + 1] = { title = "Ammunition", rows = rows }
    return cards
  end,
})
