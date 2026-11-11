-- ClassPages: turns class presets into saved buttons and resolves saved buttons to what the client should show.
-- Spells are saved with the ID the player dragged or the preset named; at runtime ns.Spellbook.Resolve maps them to
-- the highest known rank, so learning a new rank upgrades every bar without editing it.
--
-- Public API (ns.HUD.Content)
--   PresetButtons(profile, preset) -> { {type, id} }     buttons for a class preset (known spells only)
--   Seed(hud, profile) -> count                          create every preset bar once per profile
--   Refill(bar, profile) -> ok                           refill a preset bar; the old buttons go to bar.undo
--   Undo(bar) -> ok                                      restore the buttons before the last refill
--   Runtime(button) -> kind, value                       LibActionButton state for a saved button
--   FromLAB(kind, value) -> saved button or nil          saved button from a LibActionButton state (drag & drop)
local ADDON, ns = ...

ns.HUD = ns.HUD or {}
local Content = {}
ns.HUD.Content = Content

local NUM_PET_SLOTS = 10

local generators = {}

generators.pet = function()
  local out = {}
  for i = 1, NUM_PET_SLOTS do out[#out + 1] = { type = "pet", id = i } end
  return out
end

-- Stances, forms, auras: whatever the game lists on its stance bar for this character.
generators.stances = function()
  local out = {}
  local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
  for i = 1, (not ns.Secret.IsSecret(n) and tonumber(n)) or 0 do
    local _, _, _, spellID = GetShapeshiftFormInfo(i)
    if spellID and not ns.Secret.IsSecret(spellID) then out[#out + 1] = { type = "spell", id = spellID } end
  end
  return out
end

generators.professions = function()
  local out = {}
  for _, p in ipairs(ns.Spellbook.Professions()) do
    if p.spellID then out[#out + 1] = { type = "spell", id = p.spellID } end
  end
  return out
end

-- Generic classes: the first non-passive spells of the spellbook, one per name.
generators.spellbook = function(preset)
  local out, seen, limit = {}, {}, (preset.cols or 8) * (preset.rows or 1)
  for _, it in ipairs(ns.Spellbook.Items()) do
    if not it.passive and it.name and not seen[it.name] then
      seen[it.name] = true
      out[#out + 1] = { type = "spell", id = it.spellID }
      if #out >= limit then break end
    end
  end
  return out
end
Content.generators = generators

function Content.PresetButtons(profile, preset)
  if preset.generator then
    local gen = generators[preset.generator]
    return gen and gen(preset) or {}
  end
  local out = {}
  for _, key in ipairs(preset.spells or {}) do
    local base = ns.Classes.SpellID(profile, key)
    local known = base and ns.Spellbook.Resolve(base)
    if known then out[#out + 1] = { type = "spell", id = base } end
  end
  return out
end

function Content.Seed(hud, profile)
  if hud.seeded then return 0 end
  local n = 0
  for _, preset in ipairs(profile.presets or {}) do
    if not preset.optional then
      ns.HUD.Model.FromPreset(hud, preset, Content.PresetButtons(profile, preset))
      n = n + 1
    end
  end
  hud.seeded = true
  return n
end

local function findPreset(profile, key)
  for _, p in ipairs(profile.presets or {}) do if p.key == key then return p end end
  return nil
end

function Content.Refill(bar, profile)
  local preset = bar.preset and findPreset(profile, bar.preset)
  if not preset then return false end
  bar.undo = ns.Util.DeepCopy(bar.buttons)
  bar.buttons = {}
  for slot, b in ipairs(Content.PresetButtons(profile, preset)) do bar.buttons[slot] = b end
  return true
end

function Content.Undo(bar)
  if type(bar.undo) ~= "table" then return false end
  bar.buttons, bar.undo = bar.undo, nil
  ns.HUD.Model.Sanitize(bar)
  return true
end

function Content.Runtime(b)
  if type(b) ~= "table" then return "empty", nil end
  if b.type == "spell" then
    local id = ns.Spellbook.Resolve(b.id) or b.id
    return "spell", id
  elseif b.type == "item" then
    return "item", "item:" .. tostring(b.id)
  elseif b.type == "macro" or b.type == "action" then
    return b.type, b.id
  end
  return "empty", nil
end

function Content.FromLAB(kind, value)
  if kind == "spell" and tonumber(value) then return { type = "spell", id = tonumber(value) } end
  if kind == "item" and value then
    local id = tonumber(value) or tonumber(tostring(value):match("item:(%d+)"))
    if id then return { type = "item", id = id } end
  end
  if kind == "macro" and value then return { type = "macro", id = value } end
  if kind == "action" and tonumber(value) then return { type = "action", id = tonumber(value) } end
  return nil
end
