-- ClassPages: runtime of the user-defined bars. One secure header per bar (SecureHandlerStateTemplate), buttons from
-- LibActionButton-1.0 (spell, item, macro, action) or ns.HUD.PetButton (pet). Everything secure (create, move,
-- resize, re-attribute) goes through ns.Combat.Run and is applied after combat when needed.
--
-- Rules
--   * The saved bar (profile.hud.bars[id]) is the single source of truth; frames are rebuilt from it.
--   * Buttons have a fixed base size (36) and are scaled to bar.size, so Blizzard's button art never misaligns.
--   * Drag & drop changes made by the player are written back through LibActionButton's OnButtonContentsChanged.
--   * Visibility: secure state driver from Model.VisibilityCondition (pet, combat, target, stance); "mouseover" fades
--     the bar to FADE_ALPHA until the mouse is over it (alpha is not protected, so this also works in combat).
--   * Key bindings: override bindings owned by the bar header (bar.keys), re-applied with the bar; labels by Highlight.
--   * Counters: item counts, reagent spells and class counters (profile.counters, e.g. ammunition) turn orange/red
--     when low (flag lowCount).
--   * Timers: cooldown swipe/countdown by LibActionButton (secret-safe duration objects); ready flash, reactive and
--     proc glow by ns.HUD.Highlight, only on bars whose kind (or override) enables them.
--
-- Public API (ns.HUD)
--   Rebuild()                 rebuild every bar from the profile (profile switch, import)
--   ApplyBar(id)              re-apply one bar after an edit (position, grid, flags, buttons)
--   RefreshContents()         re-resolve spells after the spellbook changed (new ranks)
--   SetEditing(on), IsEditing()
--   Frames(id) -> header, buttons
--   AddBar(fields) -> bar, DeleteBar(id) -> bool, Bars() -> list sorted by id
--   Select(id), Selected() -> id | nil       bar selected in the HUD tab / mover
--   Presets() -> { {key, title, kind, barID} }   class presets, barID = existing bar from that preset
--   AddPreset(key) -> bar | nil              create an enabled bar from a class preset
--   SetEnabled(id, on)                       show or hide a bar (saved)
--   UpdateCounts()                           refresh the count text of all buttons
--   UseNumberKeys(id) -> bool                give bar id the keys 1-0, -, = on its first buttons
local ADDON, ns = ...
local L = ns.L

local HUD = ns.HUD
local Model, Kinds, Content, Highlight, PetButton = HUD.Model, HUD.Kinds, HUD.Content, HUD.Highlight, HUD.PetButton
local Secret = ns.Secret

local BASE = 36
local frames = {}       -- [barID] = { header, lab = {slot = button}, pet = {slot = button}, used = {slot = button} }
local editing = false
local LAB, Masque
local reactiveNames = {} -- [localized spell name] = true for the player's class
local counterNames = {}  -- [localized spell name] = { count = fn, low = n } from the class profile
local FADE_ALPHA = 0
local state = { ready = 0, reactive = 0, proc = 0 }
HUD.stats = state

local function hud() return ns.profile and ns.profile.hud end

function HUD.Bars()
  local list = {}
  for _, bar in pairs(hud() and hud().bars or {}) do list[#list + 1] = bar end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function HUD.Frames(id)
  local f = frames[id]
  return f and f.header, f and f.used
end

function HUD.IsEditing() return editing end

-- showGrid: empty slots stay visible (edit mode, and bars without any button so they never vanish)
local function labConfig(flags, showGrid)
  local config = {
    showGrid = showGrid or editing,
    tooltip = "enabled",
    outOfRangeColoring = flags.range and "button" or "none",
    hideElements = { macro = true, hotkey = true, equipped = false, border = true, borderIfEmpty = true },
    keyBoundTarget = false,
  }
  -- nil = countdown numbers follow the game's CVar; false = hidden
  if not flags.cooldown then config.cooldownCount = false end
  return config
end

local KEY_STATES = "[vehicleui][overridebar][possessbar][petbattle] off; on"
local KEY_SNIPPET = [[
  self:ClearBindings()
  if newstate ~= "off" and KEYS then
    for key, name in pairs(KEYS) do self:SetBindingClick(false, key, name, "LeftButton") end
  end
]]

local function getHeader(bar)
  local f = frames[bar.id]
  if f then return f end
  local name = "ClassPagesBar" .. bar.id
  local header = ns.UI.SafeCreate("Frame", UIParent, { "SecureHandlerStateTemplate" }, name)
  header:SetClampedToScreen(true)
  -- shown while the bar has no button: an empty bar is otherwise invisible
  local hint = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", header, "TOP", 0, 3)
  hint:SetText(L["Drag spells here"])
  f = { header = header, lab = {}, pet = {}, used = {}, hint = hint }
  frames[bar.id] = f
  return f
end

local function labButton(f, bar, slot)
  local b = f.lab[slot]
  if b or not LAB then return b end
  b = LAB:CreateButton(slot, ("ClassPagesBar%dButton%d"):format(bar.id, slot), f.header, labConfig(Kinds.Effective(bar)))
  b.cpBarID, b.cpSlot = bar.id, slot
  Highlight.Attach(b)
  if Masque then
    local group = Masque:Group("ClassPages", tostring(bar.name))
    pcall(b.AddToMasque, b, group)
  end
  f.lab[slot] = b
  return b
end

local function petButton(f, bar, slot)
  local b = f.pet[slot]
  if b then return b end
  b = PetButton.Create(("ClassPagesBar%dPet%d"):format(bar.id, slot), f.header)
  b.cpBarID = bar.id
  Highlight.Attach(b)
  f.pet[slot] = b
  return b
end

-- Mouseover bars: hooked once per button; f.fade says whether the rule is active right now.
local function hookFade(b, f)
  if b.cpFadeHooked then return end
  b.cpFadeHooked = true
  b:HookScript("OnEnter", function() if f.fade then f.header:SetAlpha(f.alpha or 1) end end)
  b:HookScript("OnLeave", function()
    if f.fade and not (f.header.IsMouseOver and f.header:IsMouseOver()) then f.header:SetAlpha(FADE_ALPHA) end
  end)
end

local function placeButton(b, header, pos, bar)
  local scale = bar.size / BASE
  b:SetScale(scale)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", header, "TOPLEFT", pos.x / scale, pos.y / scale)
  b:SetSize(BASE, BASE)
end

-- Applies one bar completely. Must run out of combat (wrapped by ApplyBar).
local function apply(bar)
  Model.Sanitize(bar)
  local f = getHeader(bar)
  local header = f.header
  local layout = Model.Layout(bar)
  local flags = Kinds.Effective(bar)
  local empty = Model.IsEmpty(bar)
  f.hint:SetShown(empty and not editing)

  header:SetSize(layout.width, layout.height)
  header:SetScale(bar.scale)
  f.alpha = bar.alpha
  f.fade = bar.show.mouseover and not editing or false
  header:SetAlpha(f.fade and FADE_ALPHA or bar.alpha)
  header:ClearAllPoints()
  header:SetPoint(bar.point[1], UIParent, bar.point[1], bar.point[2], bar.point[3])

  local visible = ns.db.settings.hudEnabled and bar.enabled or editing
  if RegisterStateDriver then
    if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end
    RegisterStateDriver(header, "visibility", visible and Model.VisibilityCondition(bar, editing) or "hide")
  else
    header:SetShown(visible)
  end

  wipe(f.used)
  local capacity = Model.Capacity(bar)
  for slot = 1, capacity do
    local saved = bar.buttons[slot]
    local usePet = saved and saved.type == "pet"
    local b = usePet and petButton(f, bar, slot) or labButton(f, bar, slot)
    local other = usePet and f.lab[slot] or f.pet[slot]
    if other then other:Hide() end
    if b then
      placeButton(b, header, layout.slots[slot], bar)
      if usePet then
        b.cpShowCooldown = flags.cooldown
        PetButton.Assign(b, saved.id)
      else
        b:UpdateConfig(labConfig(flags, empty))
        b:SetAttribute("buttonlock", not editing)
        local kind, value = Content.Runtime(saved)
        b:SetState(0, kind, value)
        if b.cooldown and b.cooldown.SetDrawSwipe then b.cooldown:SetDrawSwipe(flags.cooldown) end
      end
      hookFade(b, f)
      Highlight.SetKeyText(b, Model.ShortKey(bar.keys[slot]))
      b.cpFlags = flags
      b.cpReady = b.cpReady or {}
      Highlight.Resize(b)
      Highlight.SetReactive(b, nil)
      b:Show()
      f.used[slot] = b
    end
  end
  -- slots beyond the grid stay saved but their frames are hidden
  for slot, b in pairs(f.lab) do if slot > capacity then b:Hide() end end
  for slot, b in pairs(f.pet) do if slot > capacity then b:Hide() end end

  -- key bindings belong to the header: cleared and re-applied with the bar, gone when the bar is hidden or deleted
  if ClearOverrideBindings then ClearOverrideBindings(header) end
  local bound = {}
  if SetOverrideBindingClick and ns.db.settings.hudEnabled and bar.enabled then
    for slot, key in pairs(bar.keys) do
      local b = f.used[slot]
      local name = b and b.GetName and b:GetName()
      if name then
        SetOverrideBindingClick(header, false, key, name, "LeftButton")
        bound[key] = name
      end
    end
  end
  -- vehicles, possessed units and pet battles need the number keys for the game's own bars: the header releases
  -- its keys there and takes them back afterwards (secure snippet, works in combat)
  if header.Execute and RegisterStateDriver and UnregisterStateDriver then
    header:Execute("KEYS = newtable()")
    for key, name in pairs(bound) do header:Execute(("KEYS[%q] = %q"):format(key, name)) end
    header:SetAttribute("_onstate-cpkeys", KEY_SNIPPET)
    UnregisterStateDriver(header, "cpkeys")
    RegisterStateDriver(header, "cpkeys", KEY_STATES)
    header:Execute('local newstate = self:GetAttribute("state-cpkeys") ' .. KEY_SNIPPET)
  end
  if HUD.UpdateCounts then HUD.UpdateCounts() end
  if HUD.Mover then HUD.Mover.Sync(bar) end
  if HUD.Binder then HUD.Binder.Sync(bar) end
end

function HUD.ApplyBar(id)
  local bar = hud() and hud().bars[id]
  if not bar then return end
  if not LAB then return end
  ns.Combat.Run("bar" .. id, function() apply(bar) end)
  if HUD.Blizzard then HUD.Blizzard.Apply() end
end

local function hideBar(id)
  local f = frames[id]
  if not f then return end
  ns.Combat.Run("bar" .. id, function()
    if UnregisterStateDriver then UnregisterStateDriver(f.header, "visibility") end
    if UnregisterStateDriver then UnregisterStateDriver(f.header, "cpkeys") end
    if f.header.Execute then f.header:Execute("KEYS = newtable()") end
    if ClearOverrideBindings then ClearOverrideBindings(f.header) end
    f.header:Hide()
    if HUD.Mover then HUD.Mover.Hide(id) end
  end)
end

local function updateReactiveNames()
  wipe(reactiveNames)
  local profile = ns.Classes.Player()
  for baseID in pairs(ns.Classes.ReactiveSet(profile)) do
    local name = ns.API.SpellName(baseID)
    if name then reactiveNames[name] = true end
  end
  wipe(counterNames)
  for key, def in pairs(profile.counters or {}) do
    local name = profile.spells[key] and ns.API.SpellName(profile.spells[key])
    if name and type(def) == "table" and type(def.count) == "function" then counterNames[name] = def end
  end
end

function HUD.Rebuild()
  if not LAB or not hud() then return end
  updateReactiveNames()
  local alive = {}
  for _, bar in ipairs(HUD.Bars()) do
    alive[bar.id] = true
    HUD.ApplyBar(bar.id)
  end
  for id in pairs(frames) do if not alive[id] then hideBar(id) end end
  if HUD.Blizzard then HUD.Blizzard.Apply() end
end

-- Main bar keys (1-0, -, =) for the first buttons of one bar; other bars give these keys up.
function HUD.UseNumberKeys(id)
  if not hud() or not hud().bars[id] then return false end
  for _, changed in ipairs(Model.KeyRow(hud(), id)) do HUD.ApplyBar(changed) end
  return true
end

function HUD.RefreshContents()
  updateReactiveNames()
  for _, bar in ipairs(HUD.Bars()) do HUD.ApplyBar(bar.id) end
end

function HUD.SetEditing(on)
  if ns.Combat.InLockdown() then
    ns.Print(L["Not in combat."])
    return false
  end
  if on and HUD.Binder and HUD.Binder.IsActive() then HUD.Binder.SetActive(false) end
  editing = on and true or false
  if HUD.Mover then HUD.Mover.SetShown(editing) end
  HUD.Rebuild()
  if not editing and HUD.Mover then HUD.Mover.SetShown(false) end
  return true
end

-- New bars appear centred, a bit lower for every bar already there, so they never stack invisibly.
function HUD.AddBar(fields)
  fields = fields or {}
  if not fields.point then fields.point = { "CENTER", 0, -40 - 30 * (#HUD.Bars() % 8) } end
  local bar = Model.Add(hud(), fields)
  HUD.ApplyBar(bar.id)
  return bar
end

-- Class presets that can be (re)created from the HUD tab: { {key, title, kind, barID = existing bar or nil} }
function HUD.Presets()
  local out = {}
  for _, p in ipairs(ns.Classes.Player().presets or {}) do
    local existing
    for _, bar in ipairs(HUD.Bars()) do if bar.preset == p.key then existing = bar.id end end
    out[#out + 1] = { key = p.key, title = p.title, kind = p.kind, barID = existing }
  end
  return out
end

function HUD.AddPreset(key)
  local profile = ns.Classes.Player()
  for _, p in ipairs(profile.presets or {}) do
    if p.key == key then
      local bar = Model.FromPreset(hud(), p, Content.PresetButtons(profile, p))
      bar.enabled = true
      HUD.ApplyBar(bar.id)
      return bar
    end
  end
  return nil
end

function HUD.SetEnabled(id, on)
  local bar = hud().bars[id]
  if not bar then return end
  bar.enabled = on and true or false
  HUD.ApplyBar(id)
end

local selected
function HUD.Select(id)
  selected = id
  if HUD.Mover then HUD.Mover.Refresh() end
end
function HUD.Selected() return selected and hud() and hud().bars[selected] and selected or nil end

function HUD.DeleteBar(id)
  if not hud().bars[id] then return false end
  ns.DB.Backup("delete bar " .. tostring(hud().bars[id].name))
  hud().bars[id] = nil
  hideBar(id)
  return true
end

-- Timers and highlights ---------------------------------------------------------------------------
local function eachUsed(fn)
  for _, f in pairs(frames) do
    for _, b in pairs(f.used) do fn(b) end
  end
end

local function spellOf(b)
  if b.cpIsPet or not b.GetAction then return nil end
  local kind, value = b:GetAction()
  if kind == "spell" then return value end
  if kind == "action" and b.GetSpellId then
    local ok, id = pcall(b.GetSpellId, b)
    if ok and not Secret.IsSecret(id) then return id end
  end
  return nil
end

local function updatePets()
  for _, f in pairs(frames) do
    for _, b in pairs(f.used) do if b.cpIsPet then PetButton.Update(b) end end
  end
end

-- unit events fire for every group member: only the player's own matter
local function updatePetsOfPlayer(_, unit)
  if unit == nil or (not Secret.IsSecret(unit) and unit == "player") then updatePets() end
end

local function readyStep(b, now)
  if b.cpIsPet or not (b.cpFlags and b.cpFlags.readyFlash) then return end
  local spellID = spellOf(b)
  if not spellID then return end
  local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
  if not ok then return end
  if Highlight.Step(b.cpReady, Highlight.ReadActive(info), now) then
    state.ready = state.ready + 1
    Highlight.Flash(b)
  end
end

local function updateCooldowns(event)
  if event == "PET_BAR_UPDATE_COOLDOWN" then updatePets() return end
  if not (C_Spell and C_Spell.GetSpellCooldown) then return end
  local now = GetTime()
  for _, f in pairs(frames) do
    for _, b in pairs(f.used) do readyStep(b, now) end
  end
end

local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
local function usableStep(b)
  if b.cpIsPet or not (b.cpFlags and b.cpFlags.reactive) then return end
  local spellID = spellOf(b)
  local name = spellID and ns.API.SpellName(spellID)
  if not name or not reactiveNames[name] then return end
  local ok, usable = pcall(IsSpellUsable, spellID)
  if ok then
    state.reactive = state.reactive + 1
    Highlight.SetReactive(b, usable)
  end
end

local function updateUsable()
  if not IsSpellUsable or not next(reactiveNames) then return end
  for _, f in pairs(frames) do
    for _, b in pairs(f.used) do usableStep(b) end
  end
end

-- Counters: a count may be secret in combat. It is handed to Highlight.SetCount untested (which checks IsSecret);
-- a failed read passes nil and shows no warning.
local function countStep(b)
  if b.cpIsPet or not b.GetAction then return end
  if not (b.cpFlags and b.cpFlags.lowCount) then Highlight.SetCount(b, nil); return end
  local kind, value = b:GetAction()
  if kind == "item" then
    local id = tonumber(value) or tonumber(tostring(value):match("item:(%d+)"))
    if not id then Highlight.SetCount(b, nil) return end
    local ok, n = ns.API.Call("C_Item.GetItemCount", id)
    if ok then Highlight.SetCount(b, n) else Highlight.SetCount(b, nil) end
  elseif kind == "spell" then
    local name = ns.API.SpellName(value)
    local def = name and counterNames[name]
    if def then
      local ok, n = pcall(def.count)
      state.counted = (state.counted or 0) + 1
      if ok then Highlight.SetCount(b, n, def.low, true) else Highlight.SetCount(b, nil, def.low, true) end
    elseif C_Spell and C_Spell.IsConsumableSpell and C_Spell.GetSpellCastCount then
      local okC, consumable = pcall(C_Spell.IsConsumableSpell, value)
      local okN, n = pcall(C_Spell.GetSpellCastCount, value)
      if okC and okN and not Secret.IsSecret(consumable) and consumable then Highlight.SetCount(b, n) else Highlight.SetCount(b, nil) end
    else
      Highlight.SetCount(b, nil)
    end
  else
    Highlight.SetCount(b, nil)
  end
end

function HUD.UpdateCounts()
  for _, f in pairs(frames) do
    for _, b in pairs(f.used) do countStep(b) end
  end
end

local function updateCountsOfPlayer(_, unit)
  if unit == nil or (not Secret.IsSecret(unit) and unit == "player") then HUD.UpdateCounts() end
end

-- Proc glow (LibActionButton draws it only with LibButtonGlow; we use Blizzard's alert manager or our glow).
local function setProc(spellID, on)
  if Secret.IsSecret(spellID) or not spellID then return end
  local name = ns.API.SpellName(spellID)
  eachUsed(function(b)
    if b.cpIsPet or not (b.cpFlags and b.cpFlags.procGlow) then return end
    local id = spellOf(b)
    if id and (id == spellID or (name and ns.API.SpellName(id) == name)) then
      state.proc = state.proc + 1
      local mgr = ActionButtonSpellAlertManager
      if mgr and mgr.ShowAlert then
        pcall(on and mgr.ShowAlert or mgr.HideAlert, mgr, b)
      else
        Highlight.SetReactive(b, on)
      end
    end
  end)
end

ns:RegisterModule("HUD", {
  Init = function()
    LAB = LibStub and LibStub("LibActionButton-1.0", true)
    Masque = LibStub and LibStub("Masque", true)
    if not LAB then ns.Health.Record("HUD", "LibActionButton-1.0 missing") return end
    local ok = ns.Features.Available("hud")
    if not ok then return end
    LAB.RegisterCallback(HUD, "OnButtonUpdate", function(_, button)
      if button.cpBarID then Highlight.Tile(button) end
    end)
    LAB.RegisterCallback(HUD, "OnButtonContentsChanged", function(_, button, stateID, kind, value)
      if tostring(stateID) ~= "0" or not button.cpBarID then return end
      local bar = hud() and hud().bars[button.cpBarID]
      if not bar then return end
      bar.buttons[button.cpSlot] = Content.FromLAB(kind, value)
      ns.Log("bar", bar.id, "slot", button.cpSlot, "=", kind, tostring(value))
      -- the first or last button changes the empty-bar display (grid, hint); drag & drop happens out of combat
      if not ns.Combat.InLockdown() then HUD.ApplyBar(bar.id) end
      if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end)
    local opts = { allowSecret = true } -- these handlers only hand values to widgets or check them with IsSecret
    for _, e in ipairs({ "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN" }) do
      ns.Events:On(e, updateCooldowns, "HUD", opts)
    end
    for _, e in ipairs({ "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "PLAYER_TARGET_CHANGED" }) do
      ns.Events:On(e, updateUsable, "HUD", opts)
    end
    for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST" }) do
      ns.Events:On(e, updatePets, "HUD", opts)
    end
    ns.Events:On("UNIT_PET", updatePetsOfPlayer, "HUD", opts)
    ns.Events:On("BAG_UPDATE_DELAYED", HUD.UpdateCounts, "HUD", opts)
    ns.Events:On("UNIT_INVENTORY_CHANGED", updateCountsOfPlayer, "HUD", opts)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, id) setProc(id, true) end, "HUD", opts)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, id) setProc(id, false) end, "HUD", opts)
  end,
  Login = function()
    if not LAB or not ns.Features.Available("hud") then return end
    ns.Spellbook.Scan()
    local profile = ns.Classes.Player()
    local n = Content.Seed(hud(), profile)
    if n > 0 then
      ns.Print((L["%d bars created for your class. /cp or the minimap button opens the window, /cp unlock moves them."]):format(n))
    end
    HUD.Rebuild()
  end,
  SelfTest = function()
    local rows = {}
    local ok, why = ns.Features.Available("hud")
    rows[#rows + 1] = { name = "LibActionButton", ok = LAB ~= nil, detail = LAB and ("minor " .. tostring(select(2, LibStub:GetLibrary("LibActionButton-1.0", true)))) or "missing" }
    rows[#rows + 1] = { name = "hud feature", ok = ok, detail = ok and "ok" or why }
    local n, shown = 0, 0
    for id, f in pairs(frames) do
      n = n + 1
      if f.header:IsShown() then shown = shown + 1 end
      local bar = hud().bars[id]
      if bar then
        local _, changed = Model.Sanitize(bar)
        rows[#rows + 1] = { name = "bar " .. id .. " " .. tostring(bar.name), ok = true, warn = changed, detail = ("%dx%d, %d buttons, %s"):format(bar.cols, bar.rows, ns.Util.Count(f.used), bar.kind) }
      end
    end
    rows[#rows + 1] = { name = "bars", ok = true, detail = ("%d built, %d shown, %d queued for after combat"):format(n, shown, ns.Combat.Pending()) }
    rows[#rows + 1] = { name = "highlights", ok = true, detail = ("ready %d, reactive %d, proc %d"):format(state.ready, state.reactive, state.proc) }
    return rows
  end,
})

ns.Slash.Register("unlock", function() HUD.SetEditing(true) end, "unlock the HUD to move and resize bars")
ns.Slash.Register("lock", function() if HUD.SetEditing(false) then ns.Print(L["HUD locked."]) end end, "lock the HUD")
