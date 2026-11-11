-- ClassPages: compatibility layer. Every game API the addon depends on is reached through ns.API, which
--   1. checks that the function exists (capability probe, never a version or WOW_PROJECT_ID check),
--   2. normalises return values into plain tables so a changed signature breaks exactly one place,
--   3. never raises: a missing or failing API yields nil and is counted in ns.API.failures.
-- Features (ns.Features) group the APIs a module needs; a module whose feature is unavailable stays dormant and says
-- so in /cp debug instead of throwing errors all session long.
--
-- Public API (ns.API)
--   Resolve(path) -> value or nil          walk a dotted global path ("C_Spell.GetSpellName") without raising
--   Has(path) -> bool                      the path exists
--   Call(path, ...) -> ok, results...      pcall of the resolved function; failures counted in API.failures
--   First({paths}) -> fn, path | nil       first path of a list that resolves to a function
--   SpellName(spellID) -> name | nil       localized name, cached until SPELLS_CHANGED
--   SpellIcon(spellID) -> texture | nil
--   IsSpellKnown(spellID) -> bool          known by the player (any rank)
--   PlayerClass() -> token, classID | nil  e.g. "HUNTER"
--   PlayerLevel() -> number | nil
-- Public API (ns.Features)
--   Define(name, { label, requires = { path | { alternatives } } })   register a feature and its required APIs
--   Available(name) -> true | false, reason   false when switched off or an API is missing
--   Missing(name) -> { path }              required paths that do not resolve
--   Disabled(name) -> bool, SetEnabled(name, bool)   user switch (ns.db.settings.disabledFeatures)
--   Status() -> { {name, label, ok, detail} }  rows for /cp debug
local ADDON, ns = ...
local L = ns.L

local API = { failures = {} }
ns.API = API

function API.Resolve(path)
  local cur = _G
  for part in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[part]
    if cur == nil then return nil end
  end
  return cur
end

function API.Has(path) return API.Resolve(path) ~= nil end

-- Calls a path safely. Returns ok, results...
local resolved = {} -- [path] = function; only hits are cached, a missing API may be added by a later patch
local function finish(path, ok, ...)
  if ok then return true, ... end
  API.failures[path] = (API.failures[path] or 0) + 1
  if API.failures[path] == 1 then ns.Log("API error", path, (...)) end -- once per path: this runs in hot paths
  return false, (...)
end

function API.Call(path, ...)
  local fn = resolved[path]
  if not fn then
    fn = API.Resolve(path)
    if type(fn) ~= "function" then
      API.failures[path] = (API.failures[path] or 0) + 1
      return false, "missing"
    end
    resolved[path] = fn
  end
  return finish(path, pcall(fn, ...))
end

-- First existing path of a list: API.First({ "C_Spell.GetSpellName", "GetSpellInfo" }) -> fn, path
function API.First(paths)
  for _, p in ipairs(paths) do
    local fn = API.Resolve(p)
    if type(fn) == "function" then return fn, p end
  end
  return nil
end

-- Spells ---------------------------------------------------------------------------------------
-- Names are asked for every button on every update event, so they are cached until the spellbook changes.
local spellNames = {}
function API.SpellName(spellID)
  if spellID == nil or ns.Secret.IsSecret(spellID) then return nil end
  local cached = spellNames[spellID]
  if cached then return cached end
  local ok, name = API.Call("C_Spell.GetSpellName", spellID)
  if ok and not ns.Secret.IsSecret(name) and name then
    spellNames[spellID] = name
    return name
  end
  return nil
end
ns.Events:On("SPELLS_CHANGED", function() wipe(spellNames) end, "API")

function API.SpellIcon(spellID)
  local ok, icon = API.Call("C_Spell.GetSpellTexture", spellID)
  return ok and icon or nil
end

-- Spell known by the player (any rank). Out of combat values are never secret.
function API.IsSpellKnown(spellID)
  local fn = API.First({ "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown" })
  if not fn then return false end
  local ok, known = pcall(fn, spellID)
  return ok and not ns.Secret.IsSecret(known) and known and true or false
end

-- Player class: "HUNTER", localized name, classID
function API.PlayerClass()
  if UnitClassBase then
    local file, id = UnitClassBase("player")
    if file and not ns.Secret.Any(file, id) then return file, id end
  end
  if UnitClass then
    local _, file, id = UnitClass("player")
    if file and not ns.Secret.Any(file, id) then return file, id end
  end
  return nil
end

function API.PlayerLevel()
  local lvl = UnitLevel and UnitLevel("player")
  if ns.Secret.IsSecret(lvl) then return nil end
  return tonumber(lvl)
end

-- Features -------------------------------------------------------------------------------------
local Features = { defs = {}, order = {} }
ns.Features = Features

-- Features.Define("hud", { label = "Action bars", requires = { "CreateFrame", { "C_Spell.GetSpellCooldown", "GetSpellCooldown" } } })
function Features.Define(name, def)
  def.name = name
  def.requires = def.requires or {}
  Features.defs[name] = def
  Features.order[#Features.order + 1] = name
end

-- Missing API paths (a requirement may be a list of alternatives; one of them is enough).
function Features.Missing(name)
  local def = Features.defs[name]
  local missing = {}
  if not def then return missing end
  for _, req in ipairs(def.requires) do
    if type(req) == "table" then
      local any = false
      for _, alt in ipairs(req) do if API.Has(alt) then any = true break end end
      if not any then missing[#missing + 1] = table.concat(req, "|") end
    elseif not API.Has(req) then
      missing[#missing + 1] = req
    end
  end
  return missing
end

function Features.Disabled(name)
  local d = ns.db and ns.db.settings and ns.db.settings.disabledFeatures
  return d and d[name] and true or false
end

function Features.Available(name)
  if Features.Disabled(name) then return false, L["switched off"] end
  local missing = Features.Missing(name)
  if #missing > 0 then return false, (L["missing: %s"]):format(table.concat(missing, ", ")) end
  return true
end

function Features.SetEnabled(name, enabled)
  ns.db.settings.disabledFeatures = ns.db.settings.disabledFeatures or {}
  ns.db.settings.disabledFeatures[name] = (not enabled) and true or nil
end

function Features.Status()
  local rows = {}
  for _, name in ipairs(Features.order) do
    local def = Features.defs[name]
    local ok, why = Features.Available(name)
    rows[#rows + 1] = { name = name, label = def.label or name, ok = ok, detail = ok and "ok" or why }
  end
  return rows
end

Features.Define("hud", { label = "Action bars (HUD)", requires = { "CreateFrame", "LibStub", "C_Spell.GetSpellCooldown" } })
Features.Define("hudReady", { label = "Ready flash", requires = { "C_Spell.GetSpellCooldown" } })
Features.Define("hudReactive", { label = "Reactive highlight (e.g. Counterattack)", requires = { { "C_Spell.IsSpellUsable", "IsUsableSpell" } } })
Features.Define("hudKeys", { label = "Key bindings for HUD buttons", requires = { "SetOverrideBindingClick", "ClearOverrideBindings" } })
Features.Define("trainer", { label = "Trainer book", requires = { "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceLevelReq", "GetTrainerServiceCost" } })
Features.Define("hudPet", { label = "Pet action bar", requires = { "GetPetActionInfo", "GetPetActionCooldown" } })
Features.Define("talentsTraits", { label = "Talent trees (trait API)", requires = {
  "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo",
} })
Features.Define("talentsClassic", { label = "Talent trees (classic API)", requires = { "GetNumTalentTabs", "GetTalentInfo" } })
Features.Define("spellbook", { label = "Spellbook", requires = { { "C_SpellBook.GetNumSpellBookSkillLines", "GetNumSpellTabs" }, { "C_SpellBook.GetSpellBookItemInfo", "GetSpellBookItemInfo" } } })
Features.Define("pets", { label = "Pet details", requires = { { "C_SpellBook.HasPetSpells", "HasPetSpells" } } })
Features.Define("stable", { label = "Stable", requires = { { "C_StableInfo.GetStablePetInfo", "GetStablePetInfo" } } })
Features.Define("beastTraining", { label = "Beast training window", requires = { { "GetCraftInfo", "C_TradeSkillUI.GetAllRecipeIDs" } } })

ns.Slash.Register("feature", function(arg)
  local name, state = arg:match("^(%S+)%s*(%S*)$")
  if not name or not Features.defs[name] then
    for _, row in ipairs(Features.Status()) do ns.Print(("%s: %s"):format(row.name, row.detail)) end
    return ns.Print(L["usage: /cp feature <name> on|off"])
  end
  if state == "on" or state == "off" then
    Features.SetEnabled(name, state == "on")
    ns.Print((L["Feature %s %s (takes effect after /reload)"]):format(name, state == "on" and L["on"] or L["off"]))
  else
    local ok, why = Features.Available(name)
    ns.Print(("%s: %s"):format(name, ok and "ok" or why))
  end
end, "list features or switch one on|off")
