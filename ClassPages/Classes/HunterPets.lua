-- ClassPages: hunter pet knowledge. Live data first: the active pet (happiness, loyalty, training points, diet,
-- abilities), the stable (read while the stable is open) and the beast training list (read while that window is
-- open) are snapshotted into ClassPagesCharDB.pets, so the page shows them any time. Observed family facts (diet,
-- abilities) are collected account-wide in ClassPagesDB.families and override the small static table below.
--
-- Static family facts: unique abilities as announced for Forever (Blizzard class deep dive, 2026), diets as in the
-- classic game (marked unconfirmed "~" in the UI until a pet of that family confirms them via GetPetFoodTypes).
--
-- Public API (ns.HunterPets)
--   FAMILIES                                   static facts by English family name
--   Family(localizedName) -> { key, unique, diet, dietConfirmed }
--   Snapshot() -> current pet table (also stored), Current(), Stable(), Training()
--   OverviewRows() -> rows for the overview tab
--   HappinessText(level) -> text key, color
--   FamilyIcon(family) -> texture | nil      icon for a family name (registered as ns.Guide.IconProviders.pet)
local ADDON, ns = ...
local L = ns.L

local Pets = {}
ns.HunterPets = Pets

local Secret = ns.Secret

-- English family name -> { unique ability (English key), diet keys }
Pets.FAMILIES = {
  { key = "Bat", unique = "Sonic Blast", diet = { "Fruit", "Fungus" } },
  { key = "Bear", unique = "Swipe", diet = { "Bread", "Cheese", "Fish", "Fruit", "Fungus", "Meat" } },
  { key = "Bird of Prey", unique = "Mine!", diet = { "Meat" } },
  { key = "Boar", unique = "Charge", diet = { "Bread", "Cheese", "Fish", "Fruit", "Fungus", "Meat" } },
  { key = "Carrion Bird", unique = "Demoralizing Screech", diet = { "Fish", "Meat" } },
  { key = "Cat", unique = "Prowl", diet = { "Fish", "Meat" } },
  { key = "Core Hound", unique = "Lava Breath", diet = { "Meat" } },
  { key = "Crab", unique = "Pinch", diet = { "Bread", "Fish", "Fruit", "Fungus" } },
  { key = "Crocolisk", unique = "Dismember", diet = { "Fish", "Meat" } },
  { key = "Fox", unique = "Trickster's Dance", diet = {} },
  { key = "Gorilla", unique = "Thunderstomp", diet = { "Fruit", "Fungus" } },
  { key = "Hyena", unique = "Tendon Rip", diet = { "Fruit", "Meat" } },
  { key = "Raptor", unique = "Savage Rend", diet = { "Meat" } },
  { key = "Scorpid", unique = "Scorpid Poison", diet = { "Meat" } },
  { key = "Spider", unique = "Web", diet = { "Meat" } },
  { key = "Tallstrider", unique = "Dust Cloud", diet = { "Cheese", "Fruit", "Fungus" } },
  { key = "Turtle", unique = "Shell Shield", diet = { "Fish", "Fruit", "Fungus" } },
  { key = "Wind Serpent", unique = "Lightning Breath", diet = { "Bread", "Cheese", "Fish" } },
  { key = "Wolf", unique = "Furious Howl", diet = { "Meat" } },
}

-- family icon for pet entries on class pages (ns.Guide renders them; the engine knows no families)
local ICON_NAMES = { ["Bird of Prey"] = "Owl", ["Carrion Bird"] = "Vulture", ["Core Hound"] = "CoreHound", ["Wind Serpent"] = "WindSerpent", Tallstrider = "TallStrider" }
function Pets.FamilyIcon(family)
  if type(family) ~= "string" then return nil end
  return "Interface\\Icons\\Ability_Hunter_Pet_" .. (ICON_NAMES[family] or (family:gsub(" ", "")))
end
if ns.Guide then ns.Guide.IconProviders.pet = function(e) return Pets.FamilyIcon(e.family) end end

local HAPPINESS = {
  [1] = { "Unhappy", { 1, 0.25, 0.25 } },
  [2] = { "Content", { 1, 0.85, 0.2 } },
  [3] = { "Happy", { 0.3, 1, 0.3 } },
}

function Pets.HappinessText(level)
  local h = HAPPINESS[level]
  if not h then return "Unknown", { 0.6, 0.6, 0.6 } end
  return h[1], h[2]
end

local function pcallSafe(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- Family facts for a localized family name (static facts matched through the locale table, observations merged).
function Pets.Family(localized)
  local out = { name = localized }
  for _, f in ipairs(Pets.FAMILIES) do
    if localized == f.key or localized == L[f.key] then
      out.key, out.unique, out.diet = f.key, f.unique, f.diet
      break
    end
  end
  local seen = localized and ns.db and ns.db.families[localized]
  if type(seen) == "table" then
    if type(seen.diet) == "table" and #seen.diet > 0 then out.diet, out.dietConfirmed = seen.diet, true end
    out.abilities = seen.abilities
  end
  return out
end

function Pets.Snapshot()
  local cur = { when = time() }
  if not UnitExists or not UnitExists("pet") then
    cur.none = true
    ns.cdb.pets.current = cur
    return cur
  end
  local name, family, level = UnitName("pet"), UnitCreatureFamily and UnitCreatureFamily("pet"), UnitLevel("pet")
  if not Secret.Any(name, family, level) then cur.name, cur.family, cur.level = name, family, level end
  local ok, happiness, damage, rate = pcallSafe(GetPetHappiness)
  if ok and not Secret.Any(happiness, damage, rate) then cur.happiness, cur.damagePct, cur.loyaltyRate = happiness, damage, rate end
  local okL, loyalty = pcallSafe(GetPetLoyalty)
  if okL and not Secret.IsSecret(loyalty) then cur.loyalty = loyalty end
  local okT, total, spent = pcallSafe(GetPetTrainingPoints)
  if okT and not Secret.Any(total, spent) and total then cur.tpTotal, cur.tpSpent = total, spent or 0 end
  local okX, xp, xpMax = pcallSafe(GetPetExperience)
  if okX and not Secret.Any(xp, xpMax) then cur.xp, cur.xpMax = xp, xpMax end
  local okF, f1, f2, f3, f4, f5, f6 = pcallSafe(GetPetFoodTypes)
  if okF and f1 and not Secret.Any(f1, f2, f3, f4, f5, f6) then cur.diet = { f1, f2, f3, f4, f5, f6 } end
  cur.abilities = {}
  for _, s in ipairs(ns.Spellbook.PetSpells()) do
    cur.abilities[#cur.abilities + 1] = { name = s.name, rank = s.subName, icon = s.icon, spellID = s.spellID }
  end
  ns.cdb.pets.current = cur
  -- account-wide family observations
  if cur.family then
    local fam = ns.db.families[cur.family] or {}
    ns.db.families[cur.family] = fam
    if cur.diet then fam.diet = cur.diet end
    fam.abilities = fam.abilities or {}
    for _, a in ipairs(cur.abilities) do fam.abilities[a.name] = true end
    fam.seen = time()
  end
  return cur
end

function Pets.Current() return ns.cdb.pets.current or {} end
function Pets.Stable() return ns.cdb.pets.stable or {} end
function Pets.Training() return ns.cdb.pets.training or {} end

local function readStable()
  local list = {}
  for i = 0, 5 do
    local entry
    if C_StableInfo and C_StableInfo.GetStablePetInfo then
      local ok, info = pcall(C_StableInfo.GetStablePetInfo, i)
      if ok and type(info) == "table" and info.name and not Secret.Any(info.name, info.level) then
        entry = { slot = i, name = info.name, level = info.level, family = info.familyName or info.family, icon = info.icon }
      end
    elseif GetStablePetInfo then
      local ok, icon, name, level, family, loyalty = pcall(GetStablePetInfo, i)
      if ok and name and not Secret.Any(name, level) then
        entry = { slot = i, name = name, level = level, family = family, icon = icon, loyalty = loyalty }
      end
    end
    if entry then list[#list + 1] = entry end
  end
  ns.cdb.pets.stable = { when = time(), pets = list }
end

local function isBeastTraining()
  local want = ns.API.SpellName(5149)
  if not want then return false end
  if GetCraftDisplaySkillLine then
    local ok, line = pcall(GetCraftDisplaySkillLine)
    if ok and line == want then return true end
  end
  if GetCraftName then
    local ok, line = pcall(GetCraftName)
    if ok and line == want then return true end
  end
  return false
end

-- Forever has no craft API: beast training may open in the profession window instead. Same snapshot format.
local function readTrainingProfession()
  local api = C_TradeSkillUI
  if not (api and api.GetBaseProfessionInfo and api.GetAllRecipeIDs and api.GetRecipeInfo) then return end
  local want = ns.API.SpellName(5149)
  local okB, base = pcall(api.GetBaseProfessionInfo)
  if not okB or type(base) ~= "table" or not want or base.professionName ~= want then return end
  local list = {}
  local okI, ids = pcall(api.GetAllRecipeIDs)
  for _, id in ipairs(okI and ids or {}) do
    local ok, r = pcall(api.GetRecipeInfo, id)
    if ok and type(r) == "table" and r.name and not Secret.Any(r.name, r.learned) then
      list[#list + 1] = { name = r.name, rank = r.subName or r.rank, status = r.learned and "used" or (r.disabled and "unavailable" or "available") }
    end
  end
  ns.cdb.pets.training = { when = time(), list = list, source = "profession" }
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function readTraining()
  if not GetNumCrafts or not isBeastTraining() then return end
  local list = {}
  local okN, num = pcall(GetNumCrafts)
  for i = 1, okN and num or 0 do
    local ok, name, rank, kind, _, _, tpCost, reqLevel = pcall(GetCraftInfo, i)
    if ok and name and kind ~= "header" and not Secret.Any(name, rank, kind) then
      list[#list + 1] = { name = name, rank = rank, status = kind, cost = tpCost, level = reqLevel }
    end
  end
  ns.cdb.pets.training = { when = time(), list = list }
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function Pets.OverviewRows()
  local cur = Pets.Current()
  if cur.none or not cur.name then return { { label = "Pet", value = L["no active pet"] } } end
  local rows = {
    { label = "Name", value = cur.name },
    { label = "Family", value = tostring(cur.family or "?") },
    { label = "Level", value = tostring(cur.level or "?") },
  }
  if cur.happiness then
    local text, color = Pets.HappinessText(cur.happiness)
    rows[#rows + 1] = { label = "Happiness", value = L[text] .. (cur.damagePct and (" · " .. cur.damagePct .. "%") or ""), color = color }
  end
  if cur.loyalty then rows[#rows + 1] = { label = "Loyalty", value = tostring(cur.loyalty) } end
  if cur.tpTotal then rows[#rows + 1] = { label = "Training points", value = ("%d / %d"):format(cur.tpTotal - (cur.tpSpent or 0), cur.tpTotal) } end
  return rows
end

ns:RegisterModule("HunterPets", {
  Init = function()
    if ns.API.PlayerClass() ~= "HUNTER" then return end
    -- pet events come in bursts (several per second in combat): one snapshot per burst, none in combat
    local function run()
      if ns.Combat.InLockdown() then return end
      Pets.Snapshot()
      if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end
    local function snap() ns.Events.Later("petSnapshot", 0.3, run) end
    ns.Events:On("PLAYER_REGEN_ENABLED", snap, "HunterPets")
    ns.Events:On("UNIT_PET", function(_, unit) if unit == "player" then snap() end end, "HunterPets")
    for _, e in ipairs({ "UNIT_HAPPINESS", "PET_BAR_UPDATE", "UNIT_PET_TRAINING_POINTS", "LOCALPLAYER_PET_RENAMED", "PET_UI_UPDATE" }) do
      ns.Events:On(e, snap, "HunterPets")
    end
    for _, e in ipairs({ "PET_STABLE_SHOW", "PET_STABLE_UPDATE" }) do ns.Events:On(e, readStable, "HunterPets") end
    if GetNumCrafts then
      for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE" }) do ns.Events:On(e, readTraining, "HunterPets") end
    end
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do ns.Events:On(e, readTrainingProfession, "HunterPets") end
  end,
  Login = function()
    if ns.API.PlayerClass() == "HUNTER" then Pets.Snapshot() end
  end,
  SelfTest = function()
    if ns.API.PlayerClass() ~= "HUNTER" then return { { name = "pets", ok = true, detail = "not a hunter" } } end
    local cur = Pets.Current()
    local apis = {}
    for _, f in ipairs({ "GetPetHappiness", "GetPetLoyalty", "GetPetTrainingPoints", "GetPetFoodTypes", "GetPetExperience", "C_StableInfo", "GetStablePetInfo", "GetNumCrafts" }) do
      apis[#apis + 1] = f .. (ns.API.Has(f) and "+" or "-")
    end
    return {
      { name = "pet APIs", ok = true, detail = table.concat(apis, " ") },
      { name = "active pet", ok = true, detail = cur.name and ("%s, happiness %s, tp %s"):format(cur.name, tostring(cur.happiness), tostring(cur.tpTotal)) or "none" },
      { name = "stable", ok = true, detail = ("%d pets cached"):format(#(Pets.Stable().pets or {})) },
      { name = "beast training", ok = true, detail = ("%d entries cached"):format(#(Pets.Training().list or {})) },
    }
  end,
})
