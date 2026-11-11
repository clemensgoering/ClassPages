-- ClassPages: content kinds of a bar. A kind decides which timers and highlights make sense for its source, so a
-- profession bar never flashes "ready" while an attack bar does. Users may override every flag per bar
-- (bar.timers[flag] = true/false); nil means "as the kind says".
--
-- Flags
--   cooldown     cooldown swipe and countdown (always follows the source: a spell without cooldown shows none)
--   readyFlash   short flash when a cooldown ends (GCD ignored)
--   reactive     glow while a reactive spell (class profile .reactive) is usable
--   procGlow     Blizzard's spell alert glow (procs)
--   range        tint the icon when the target is out of range
--   lowCount     warn when a counted button (ammo, reagent, item, charges) runs low
--   hideOOC      hide the bar out of combat
--
-- Public API
--   ns.HUD.Kinds.Register(key, { title, icon, defaults = {flag = bool} })
--   ns.HUD.Kinds.Get(key) -> kind (falls back to "free"), .List() -> ordered keys, .FLAGS
--   ns.HUD.Kinds.Effective(bar) -> { flag = bool } (pure)
local ADDON, ns = ...

ns.HUD = ns.HUD or {}
local Kinds = { defs = {}, order = {} }
ns.HUD.Kinds = Kinds

Kinds.FLAGS = { "cooldown", "readyFlash", "reactive", "procGlow", "range", "lowCount", "hideOOC" }

function Kinds.Register(key, def)
  def.key = key
  def.defaults = def.defaults or {}
  if not Kinds.defs[key] then Kinds.order[#Kinds.order + 1] = key end
  Kinds.defs[key] = def
end

function Kinds.Get(key) return Kinds.defs[key] or Kinds.defs.free end
function Kinds.List() return Kinds.order end

function Kinds.Effective(bar)
  local kind = Kinds.Get(bar and bar.kind)
  local out = {}
  for _, flag in ipairs(Kinds.FLAGS) do
    local override = bar and type(bar.timers) == "table" and bar.timers[flag]
    if type(override) == "boolean" then out[flag] = override
    else out[flag] = kind.defaults[flag] and true or false end
  end
  return out
end

Kinds.Register("attacks", { title = "Attacks", icon = "Interface\\Icons\\Ability_Marksmanship",
  defaults = { cooldown = true, readyFlash = true, reactive = true, procGlow = true, range = true, lowCount = true } })
Kinds.Register("utility", { title = "Utility", icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce",
  defaults = { cooldown = true, readyFlash = true, reactive = true, procGlow = true, range = false, lowCount = true } })
Kinds.Register("pet", { title = "Pet", icon = "Interface\\Icons\\Ability_Hunter_BeastCall",
  defaults = { cooldown = true, readyFlash = false, reactive = false, procGlow = false, range = false } })
Kinds.Register("professions", { title = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing",
  defaults = { cooldown = true, readyFlash = false, reactive = false, procGlow = false, range = false } })
Kinds.Register("items", { title = "Items", icon = "Interface\\Icons\\INV_Potion_54",
  defaults = { cooldown = true, readyFlash = false, reactive = false, procGlow = false, range = false, lowCount = true } })
Kinds.Register("free", { title = "Free", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
  defaults = { cooldown = true, readyFlash = true, reactive = true, procGlow = true, range = true, lowCount = true } })
