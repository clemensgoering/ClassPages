-- ClassPages: class profile registry. Everything class-specific lives in Classes/<Class>.lua and is registered here;
-- engine code (Core/, HUD/, Talents/, UI/) never names a class. A class without a profile gets the generic one, so
-- talents, HUD and spellbook presets work for every class from day one.
--
-- Profile contract
--   ns.Classes:Register{
--     class    = "HUNTER",                          -- UnitClassBase token
--     color    = { r, g, b }, icon = texture,
--     spells   = { key = baseSpellID, ... },        -- named spells; presets and highlights refer to the keys
--     reactive = { { key = "counterattack", hint = "after a parry" }, ... },  -- usable-only-after-event spells
--     presets  = { { key, title, kind, cols, rows, size, point = {p, x, y}, enabled, spells = { keys } | generator = "pet"|"professions"|"spellbook" }, ... },
--     tabs     = { "pets" },                        -- extra window tabs (registered in UI by key)
--     counters = { spellKey = { count = function() -> n, low = n } },  -- numbers drawn on that spell's button (e.g. ammunition)
--     overviewCards = function() -> { { title, note?, rows = { {label, value, color?} } } } end,  -- up to two overview cards (optional)
--   }
--   ns.Classes:AddPage(class, page)   data-only class page (docs/04-KLASSENSEITEN.md), rendered by UI/TabGuide.lua.
--     Works before or after Register: a class without a full profile gets a basic one (generic presets, class colour).
--
-- Public API
--   ns.Classes:Register(profile), ns.Classes.Get(class), ns.Classes.Player() -> profile (generic fallback)
--   ns.Classes.SpellID(profile, key) -> base spell ID
--   ns.Classes.AllPages() -> pages           pages of all classes sorted by key (UI registers one tab per page)
--   ns.Classes.ReactiveSet(profile) -> { [baseSpellID] = hint }
--   ns.Classes.TREES[CLASS] = { tree names }  classic tree names in tab order; ns.Classes.COLORS[CLASS] = { r, g, b }
--   preset field optional = true: offered in the window but not created on first login (e.g. pet, stances)
local ADDON, ns = ...

local Classes = { profiles = {} }
ns.Classes = Classes

local GENERIC = {
  class = "GENERIC", color = { 0.8, 0.8, 0.8 }, spells = {}, reactive = {}, tabs = {},
  presets = {
    { key = "main", title = "Main abilities", kind = "attacks", cols = 8, rows = 1, size = 40, point = { "BOTTOM", 0, 210 }, enabled = true, generator = "spellbook" },
    { key = "professions", title = "Professions", kind = "professions", cols = 4, rows = 1, size = 32, point = { "BOTTOMLEFT", 380, 120 }, enabled = false, generator = "professions" },
    -- optional: offered in the window, not created on first login (many classes have neither)
    { key = "pet", title = "Pet", kind = "pet", cols = 10, rows = 1, size = 28, point = { "BOTTOM", 0, 178 }, enabled = true, generator = "pet", optional = true },
    { key = "stances", title = "Stances", kind = "utility", cols = 6, rows = 1, size = 28, point = { "BOTTOMLEFT", 380, 178 }, enabled = true, generator = "stances", optional = true },
  },
}
Classes.GENERIC = GENERIC

-- Classic talent tree names in tab order (English keys, translated on display). Used when the client does not name
-- the trees itself (Forever reports a single specialization named like the class).
Classes.TREES = {
  WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
  PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  DRUID = { "Balance", "Feral Combat", "Restoration" },
}

-- Standard class colours and icons for basic profiles (classes with pages but without a full profile).
Classes.COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}

function Classes:Register(profile)
  assert(type(profile) == "table" and type(profile.class) == "string", "Classes:Register{ class = ... }")
  local existing = self.profiles[profile.class]
  profile.spells = profile.spells or {}
  profile.reactive = profile.reactive or {}
  profile.presets = profile.presets or GENERIC.presets
  profile.tabs = profile.tabs or {}
  profile.pages = profile.pages or {}
  profile.color = profile.color or Classes.COLORS[profile.class] or GENERIC.color
  profile.icon = profile.icon or ("Interface\\Icons\\ClassIcon_" .. profile.class:sub(1, 1) .. profile.class:sub(2):lower())
  -- pages added before the full profile was registered move over
  for _, page in ipairs(existing and existing.pages or {}) do
    profile.pages[#profile.pages + 1] = page
    profile.tabs[#profile.tabs + 1] = page.key
  end
  for _, p in ipairs(profile.presets) do
    for _, key in ipairs(p.spells or {}) do
      assert(profile.spells[key], ("preset %s names unknown spell key %s"):format(p.key, key))
    end
  end
  self.profiles[profile.class] = profile
  return profile
end

function Classes:AddPage(class, page)
  assert(type(class) == "string" and type(page) == "table" and type(page.key) == "string", "Classes:AddPage(class, { key = ... })")
  local profile = self.profiles[class] or self:Register({ class = class })
  profile.pages[#profile.pages + 1] = page
  profile.tabs[#profile.tabs + 1] = page.key
  page.class = class
  return page
end

-- All pages of all classes (UI registers one tab per page; the window shows only the player's).
function Classes.AllPages()
  local out = {}
  for _, profile in pairs(Classes.profiles) do
    for _, page in ipairs(profile.pages or {}) do out[#out + 1] = page end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

function Classes.Get(class)
  return class and Classes.profiles[class] or GENERIC
end

function Classes.Player()
  return Classes.Get(ns.API.PlayerClass())
end

function Classes.SpellID(profile, key)
  return profile and profile.spells and profile.spells[key]
end

-- Base spell IDs of the reactive spells of a profile: { [baseSpellID] = hint }
function Classes.ReactiveSet(profile)
  local set = {}
  for _, r in ipairs(profile and profile.reactive or {}) do
    local id = profile.spells[r.key]
    if id then set[id] = r.hint or true end
  end
  return set
end
