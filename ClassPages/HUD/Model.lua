-- ClassPages: bar data model. Pure Lua (no frames) so every rule is tested headless (tools/tests/hud_model_test.lua).
--
-- Saved bar (profile.hud.bars[id])
--   { id, name, kind, enabled, cols, rows, size, spacing, scale, alpha, point = { anchor, x, y },
--     timers = { flag = bool }, buttons = { [slot] = { type = "spell"|"item"|"macro"|"pet"|"action", id = ... } },
--     show = { target = bool, mouseover = bool, stance = n },   visibility rules (all optional)
--     keys = { [slot] = "SHIFT-1" },                             key bindings of this bar's buttons
--     preset = key of the class preset it was created from (optional),
--     unknown = { [slot] = button }   buttons of a type this version does not know: parked here by Sanitize,
--                                     returned to buttons when valid again }
--
-- Public API (ns.HUD.Model)
--   LIMITS                                    min/max of every numeric field
--   New(fields) -> bar                        new bar with defaults, sanitised
--   Sanitize(bar) -> bar, changed             repairs a bar read from disk in place (types, ranges, unknown slots)
--   Layout(bar) -> { width, height, slots = { {x, y} } }   positions relative to the bar's TOPLEFT
--   Capacity(bar) -> cols * rows
--   IsEmpty(bar) -> bool                      no button inside the grid
--   Snap(v, step) -> v                        round to the snap grid (step 0 or nil = off)
--   GridFromDrag(cols, rows, dx, dy, unit) -> cols, rows   clamped grid size while dragging the corner grip
--   Add(hud, fields) -> bar                   new bar with the next free ID stored in hud.bars
--   FromPreset(hud, preset, resolve) -> bar   bar from a class preset; resolve(entry) -> button or nil
--   VisibilityCondition(bar, editing) -> macro condition for the secure visibility driver
--   Chord(key, alt, ctrl, shift) -> "ALT-CTRL-SHIFT-KEY" | nil      ShortKey(chord) -> "S-1"
--   Replaces(hud, isStance) -> { pet, stance }   enabled bars hold pet actions / stance spells
--   KeyRow(hud, barID) -> { barID, ... }   keys 1-0, -, = on the first buttons; taken from other bars
--   SetKey(hud, barID, slot, chord|nil) -> removed from {barID, slot} | nil   one chord, one button
local ADDON, ns = ...

ns.HUD = ns.HUD or {}
local Model = {}
ns.HUD.Model = Model

Model.LIMITS = {
  cols = { 1, 24 }, rows = { 1, 12 }, size = { 16, 80 }, spacing = { 0, 20 }, scale = { 0.5, 2 }, alpha = { 0, 1 },
}
Model.BUTTON_TYPES = { spell = true, item = true, macro = true, pet = true, action = true }
Model.ANCHORS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local DEFAULTS = { kind = "free", enabled = true, cols = 6, rows = 1, size = 36, spacing = 4, scale = 1, alpha = 1 }

local function clampField(bar, field)
  local lim = Model.LIMITS[field]
  local v = tonumber(bar[field])
  if not v then bar[field] = DEFAULTS[field]; return true end
  local c = math.max(lim[1], math.min(lim[2], v))
  if field == "cols" or field == "rows" or field == "size" or field == "spacing" then c = math.floor(c + 0.5) end
  if c ~= bar[field] then bar[field] = c; return true end
  return false
end

local function validButton(b)
  if type(b) ~= "table" or not Model.BUTTON_TYPES[b.type] then return false end
  if b.type == "macro" then return type(b.id) == "number" or type(b.id) == "string" end
  return type(b.id) == "number"
end

function Model.Sanitize(bar)
  local changed = false
  if type(bar) ~= "table" then return nil, true end
  for k, v in pairs(DEFAULTS) do
    if type(bar[k]) ~= type(v) then bar[k] = v; changed = true end
  end
  if not ns.HUD.Kinds.defs[bar.kind] then bar.kind = "free"; changed = true end
  for field in pairs(Model.LIMITS) do changed = clampField(bar, field) or changed end
  if type(bar.name) ~= "string" or bar.name == "" then bar.name = "Bar " .. tostring(bar.id or "?"); changed = true end
  local p = bar.point
  if type(p) ~= "table" or not Model.ANCHORS[p[1]] or type(p[2]) ~= "number" or type(p[3]) ~= "number" then
    bar.point = { "CENTER", 0, 0 }; changed = true
  end
  if type(bar.timers) ~= "table" then bar.timers = {}; changed = true end
  for flag, v in pairs(bar.timers) do
    if type(v) ~= "boolean" then bar.timers[flag] = nil; changed = true end
  end
  if type(bar.show) ~= "table" then bar.show = {}; changed = true end
  for k, v in pairs(bar.show) do
    local ok = (k == "stance" and type(v) == "number" and v >= 1 and v <= 10) or ((k == "target" or k == "mouseover") and type(v) == "boolean")
    if not ok then bar.show[k] = nil; changed = true end
  end
  if type(bar.keys) ~= "table" then bar.keys = {}; changed = true end
  for slot, key in pairs(bar.keys) do
    if type(slot) ~= "number" or slot < 1 or type(key) ~= "string" or key == "" then bar.keys[slot] = nil; changed = true end
  end
  if type(bar.buttons) ~= "table" then bar.buttons = {}; changed = true end
  -- slots beyond the grid are KEPT (shrinking a bar and growing it again restores the buttons). A button this
  -- version does not understand (written by a newer one) is parked in bar.unknown and comes back when it is valid.
  if type(bar.unknown) == "table" then
    for slot, b in pairs(bar.unknown) do
      if type(slot) == "number" and slot >= 1 and validButton(b) and bar.buttons[slot] == nil then
        bar.buttons[slot] = b; bar.unknown[slot] = nil; changed = true
      end
    end
  end
  for slot, b in pairs(bar.buttons) do
    if type(slot) ~= "number" or slot < 1 or not validButton(b) then
      if type(slot) == "number" and slot >= 1 and type(b) == "table" and type(b.type) == "string" then
        bar.unknown = type(bar.unknown) == "table" and bar.unknown or {}
        bar.unknown[slot] = b
      end
      bar.buttons[slot] = nil; changed = true
    end
  end
  return bar, changed
end

function Model.New(fields)
  local bar = {}
  for k, v in pairs(DEFAULTS) do bar[k] = v end
  for k, v in pairs(fields or {}) do bar[k] = ns.Util.DeepCopy(v) end
  return (Model.Sanitize(bar))
end

function Model.Capacity(bar) return bar.cols * bar.rows end

-- Grid left-to-right, top-to-bottom. Positions are offsets from the bar's TOPLEFT (y grows downwards, negative).
function Model.Layout(bar)
  local size, gap = bar.size, bar.spacing
  local slots = {}
  for i = 1, Model.Capacity(bar) do
    local col = (i - 1) % bar.cols
    local row = math.floor((i - 1) / bar.cols)
    slots[i] = { x = col * (size + gap), y = -row * (size + gap) }
  end
  return { width = bar.cols * size + (bar.cols - 1) * gap, height = bar.rows * size + (bar.rows - 1) * gap, slots = slots }
end

function Model.Add(hud, fields)
  hud.nextID = math.max(tonumber(hud.nextID) or 1, 1)
  while hud.bars[hud.nextID] do hud.nextID = hud.nextID + 1 end
  local f = ns.Util.DeepCopy(fields or {})
  f.id = hud.nextID
  local bar = Model.New(f)
  hud.bars[bar.id] = bar
  hud.nextID = hud.nextID + 1
  return bar
end

-- True when no button lies inside the grid (such a bar shows its empty slots, otherwise it would be invisible).
function Model.IsEmpty(bar)
  for slot in pairs(bar.buttons or {}) do
    if slot <= Model.Capacity(bar) then return false end
  end
  return true
end

-- Rounds a coordinate to the snap grid (step 0 or nil = no snapping).
function Model.Snap(v, step)
  if not step or step <= 0 then return v end
  return math.floor(v / step + 0.5) * step
end

-- Resize by dragging the corner grip: dx/dy in screen pixels since the drag started (dy positive = down),
-- unit = one button plus spacing in screen pixels. Returns the clamped columns and rows.
function Model.GridFromDrag(startCols, startRows, dx, dy, unit)
  if not unit or unit <= 0 then return startCols, startRows end
  local lc, lr = Model.LIMITS.cols, Model.LIMITS.rows
  local cols = math.max(lc[1], math.min(lc[2], startCols + math.floor(dx / unit + 0.5)))
  local rows = math.max(lr[1], math.min(lr[2], startRows + math.floor(dy / unit + 0.5)))
  return cols, rows
end

-- Secure visibility macro condition for RegisterStateDriver (evaluated by the client, also in combat).
-- All active rules must hold: pet bars need a pet, "only in combat", "only with a target", "only in stance n".
function Model.VisibilityCondition(bar, editing)
  if editing then return "show" end
  if not bar.enabled then return "hide" end
  local flags = ns.HUD.Kinds.Effective(bar)
  local show = type(bar.show) == "table" and bar.show or {}
  local conds = {}
  if bar.kind == "pet" then conds[#conds + 1] = "pet" end
  if flags.hideOOC then conds[#conds + 1] = "combat" end
  if show.target then conds[#conds + 1] = "exists" end
  if show.stance then conds[#conds + 1] = "stance:" .. show.stance end
  if #conds == 0 then return "show" end
  return "[" .. table.concat(conds, ",") .. "] show; hide"
end

-- Key bindings -------------------------------------------------------------------------------------
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true }

-- Binding string for a pressed key with its modifiers; nil for a modifier on its own or keys that must stay free.
function Model.Chord(key, alt, ctrl, shift)
  if type(key) ~= "string" or key == "" or MODIFIER_KEYS[key] or key == "ESCAPE" or key == "ENTER" or key == "PRINTSCREEN" then return nil end
  return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

local SHORT = { ["ALT%-"] = "A-", ["CTRL%-"] = "C-", ["SHIFT%-"] = "S-", NUMPAD = "N", MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", BUTTON = "M", SPACE = "Sp" }
function Model.ShortKey(chord)
  if type(chord) ~= "string" then return "" end
  for long, short in pairs(SHORT) do chord = chord:gsub(long, short) end
  return chord
end

-- Assigns a chord to one button; the same chord on any other button of this HUD is released (returned).
function Model.SetKey(hud, barID, slot, chord)
  local removed
  if chord then
    for id, bar in pairs(hud.bars) do
      for s, key in pairs(bar.keys or {}) do
        if key == chord and not (id == barID and s == slot) then bar.keys[s] = nil; removed = { id, s } end
      end
    end
  end
  local bar = hud.bars[barID]
  if not bar then return removed end
  bar.keys = bar.keys or {}
  bar.keys[slot] = chord
  return removed
end

-- Gives the first buttons of a bar the main bar keys (1-0, -, =). Returns the ids of all bars that changed.
Model.ROW_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
function Model.KeyRow(hud, barID)
  local bar = hud.bars[barID]
  if not bar then return {} end
  local touched, list = { [barID] = true }, {}
  for slot = 1, math.min(#Model.ROW_KEYS, Model.Capacity(bar)) do
    local removed = Model.SetKey(hud, barID, slot, Model.ROW_KEYS[slot])
    if removed then touched[removed[1]] = true end
  end
  for id in pairs(touched) do list[#list + 1] = id end
  table.sort(list)
  return list
end

-- Which of the game's extra bars the enabled bars replace: { pet = bool, stance = bool }.
-- isStance(spellID) -> bool is supplied by the caller (game API).
function Model.Replaces(hud, isStance)
  local out = { pet = false, stance = false }
  for _, bar in pairs(hud.bars or {}) do
    if bar.enabled then
      for slot, b in pairs(bar.buttons or {}) do
        if type(b) == "table" and type(slot) == "number" and slot <= Model.Capacity(bar) then
          if b.type == "pet" then out.pet = true
          elseif b.type == "spell" and isStance and isStance(b.id) then out.stance = true end
        end
      end
    end
  end
  return out
end

-- resolve(entry) maps a preset entry ({spellKey} or generator entry) to a saved button { type, id } or nil.
function Model.FromPreset(hud, preset, entries)
  local bar = Model.Add(hud, {
    name = preset.title, kind = preset.kind, enabled = preset.enabled ~= false, cols = preset.cols, rows = preset.rows,
    size = preset.size, point = preset.point and { preset.point[1], preset.point[2], preset.point[3] } or nil, preset = preset.key,
  })
  local slot = 0
  for _, button in ipairs(entries or {}) do
    slot = slot + 1
    bar.buttons[slot] = button
  end
  return bar
end
