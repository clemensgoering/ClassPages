-- ClassPages: HUD tab (docs/mockups/index.html, tab "HUD").
-- Left: bar list (eye = show/hide, name, grid, select), "+ New bar" with a content kind, class presets as chips
-- ("+ Shots"; greyed with a check mark while a bar from that preset exists, so deleted presets come back with one
-- click). Right: editor of the selected bar: name, kind, live preview, then three sections switched by a segment
-- (Layout: steppers · Timers: highlight flags · Visibility: rules) and the actions.
-- Every change is saved first and re-applied (after combat if needed).
--
-- Public API
--   ns.UI.SelectBar(id)   select a bar in the editor (defined when the tab is built; nil before)
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

local LIST_ROWS, PRESET_ROWS = 8, 4
local LEFT_W, RIGHT_W = 300, 440
local SECTIONS = { { "layout", "Layout" }, { "timers", "Timers" }, { "visibility", "Visibility" } }
local TIMER_FLAGS = { "cooldown", "readyFlash", "reactive", "procGlow", "range", "lowCount" }
local FLAG_LABELS = {
  cooldown = "Cooldown", readyFlash = "Ready flash", reactive = "Reactive glow",
  procGlow = "Proc glow", range = "Range tint", lowCount = "Low count warning", hideOOC = "Only in combat",
}

UI.RegisterTab("hud", "HUD", function(frame)
  local view = { section = "layout" }
  local selected
  local HUD, Model, Kinds = ns.HUD, ns.HUD.Model, ns.HUD.Kinds
  local function bar() return selected and ns.profile.hud.bars[selected] end
  local function changed()
    local b = bar()
    if b then Model.Sanitize(b); HUD.ApplyBar(b.id) end
    view.Refresh()
  end

  -- Left: bars -------------------------------------------------------------------------------------
  local list = UI.Card(frame, LEFT_W, 270, L["Bars"])
  list:SetPoint("TOPLEFT", 0, 0)
  local rows = {}
  for i = 1, LIST_ROWS do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(LEFT_W - 20, 26)
    row:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 28)
    UI.Skin(row, "row")
    row.eye = UI.IconButton(row, "eye", 20, function(self) local b = ns.profile.hud.bars[self:GetParent().barID]; if b then HUD.SetEnabled(b.id, not b.enabled); view.Refresh() end end, "ghost")
    row.eye:SetPoint("LEFT", 3, 0)
    row.eye.tip = L["Show / hide this bar"]
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.eye, "RIGHT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = UI.Text(row, "")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetWordWrap(false)
    row.grid = UI.Text(row, "")
    row.grid:SetPoint("RIGHT", -8, 0)
    row.grid:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
    row:SetScript("OnClick", function(self) selected = self.barID; view.Refresh() end)
    rows[i] = row
  end

  local kinds = {}
  for _, k in ipairs(Kinds.List()) do kinds[#kinds + 1] = { k, Kinds.Get(k).title } end
  local newKind = "attacks"
  local add = UI.Card(frame, LEFT_W, 196, L["Add"])
  add:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
  local kindPick = UI.Cycle(add, 170, kinds, newKind, function(v) newKind = v end)
  kindPick:SetPoint("TOPLEFT", 10, -36)
  local addBtn = UI.Button(add, L["+ New bar"], 100, function()
    local b = HUD.AddBar({ name = L["New bar"], kind = newKind, cols = 6, rows = 1, size = 36 })
    selected = b.id
    view.Refresh()
  end)
  addBtn:SetPoint("LEFT", kindPick, "RIGHT", 8, 0)
  local presetTitle = UI.Text(add, L["Class presets"])
  presetTitle:SetPoint("TOPLEFT", 10, -68)
  presetTitle:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
  local chips = {}
  for i = 1, PRESET_ROWS * 2 do
    local c = UI.Button(add, "", (LEFT_W - 26) / 2, function(self)
      if self.presetKey and not self.used then
        local b = HUD.AddPreset(self.presetKey)
        if b then selected = b.id end
        view.Refresh()
      elseif self.used then
        selected = self.used
        view.Refresh()
      end
    end, "ghost")
    c:SetPoint("TOPLEFT", 10 + ((i - 1) % 2) * ((LEFT_W - 26) / 2 + 6), -88 - math.floor((i - 1) / 2) * 26)
    chips[i] = c
  end

  -- Right: editor ------------------------------------------------------------------------------------
  local ed = UI.Card(frame, RIGHT_W, 476)
  ed:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
  local empty = UI.Text(ed, L["Select a bar on the left or add one."])
  empty:SetPoint("CENTER")

  local name = UI.Edit(ed, 204, function(text) local b = bar(); if b and text ~= "" then b.name = text; changed() end end)
  name:SetPoint("TOPLEFT", 12, -12)
  local kind = UI.Cycle(ed, 204, kinds, "free", function(v) local b = bar(); if b then b.kind = v; changed() end end)
  kind:SetPoint("LEFT", name, "RIGHT", 8, 0)
  kind.tip = L["The content kind decides which timers make sense; you can override each one below."]

  local preview = CreateFrame("Frame", nil, ed)
  preview:SetSize(RIGHT_W - 24, 60)
  preview:SetPoint("TOPLEFT", 12, -44)
  UI.Skin(preview, "slot")
  local cells = {}
  local function drawPreview(b)
    local cols, rowsN = b.cols, b.rows
    local cell = math.max(3, math.min(math.floor((RIGHT_W - 40) / cols) - 2, math.floor(52 / rowsN) - 2, 18))
    local gap = 2
    local w, h = cols * (cell + gap) - gap, rowsN * (cell + gap) - gap
    local cr, cg, cb = UI.ClassColor()
    local n = 0
    for r = 1, rowsN do
      for c = 1, cols do
        n = n + 1
        local t = cells[n]
        if not t then t = preview:CreateTexture(nil, "ARTWORK"); cells[n] = t end -- square tiles like action buttons
        t:ClearAllPoints()
        t:SetSize(cell, cell)
        t:SetPoint("TOPLEFT", preview, "TOPLEFT", (RIGHT_W - 24 - w) / 2 + (c - 1) * (cell + gap), -(60 - h) / 2 - (r - 1) * (cell + gap))
        if b.buttons[n] ~= nil then t:SetColorTexture(cr, cg, cb, 0.9) else t:SetColorTexture(0.27, 0.22, 0.15, 0.85) end
        t:Show()
      end
    end
    for i = n + 1, #cells do cells[i]:Hide() end
  end

  -- segment: one section visible at a time, so every control has room
  local segs, parts = {}, { layout = {}, timers = {}, visibility = {} }
  for i, s in ipairs(SECTIONS) do
    local b = UI.Button(ed, L[s[2]], 134, function() view.section = s[1]; view.Refresh() end, "ghost")
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 141, -114)
    segs[s[1]] = b
  end
  local TOP = -150

  local LIM = Model.LIMITS
  local steppers = {}
  local function stepper(field, label, step, col, row, fmt, factor)
    factor = factor or 1
    local s = UI.Stepper(ed, L[label], LIM[field][1] * factor, LIM[field][2] * factor, step, function(v)
      local b = bar(); if b then b[field] = v / factor; changed() end
    end, fmt, 200)
    s:SetPoint("TOPLEFT", 12 + col * 216, TOP - row * 28)
    s.factor = factor
    steppers[field] = s
    parts.layout[#parts.layout + 1] = s
  end
  stepper("cols", "Columns", 1, 0, 0)
  stepper("rows", "Rows", 1, 1, 0)
  stepper("size", "Button size", 2, 0, 1)
  stepper("spacing", "Spacing", 1, 1, 1)
  stepper("scale", "Scale %", 5, 0, 2, "%d%%", 100)
  stepper("alpha", "Opacity %", 5, 1, 2, "%d%%", 100)

  local flagChecks = {}
  local function flagCheck(flag, col, row, section)
    local c = UI.Check(ed, L[FLAG_LABELS[flag]], false, function(v)
      local b = bar(); if not b then return end
      local kindDefault = Kinds.Get(b.kind).defaults[flag] and true or false
      b.timers[flag] = (v ~= kindDefault) and v or nil
      changed()
    end)
    c:SetPoint("TOPLEFT", 12 + col * 216, TOP - 2 - row * 26)
    flagChecks[flag] = c
    parts[section][#parts[section] + 1] = c
    parts[section][#parts[section] + 1] = c.text
  end
  for i, flag in ipairs(TIMER_FLAGS) do flagCheck(flag, (i - 1) % 2, math.floor((i - 1) / 2), "timers") end
  local flagsHint = UI.Text(ed, L["grey = default"])
  flagsHint:SetPoint("TOPLEFT", 12, TOP - 82)
  flagsHint:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
  parts.timers[#parts.timers + 1] = flagsHint

  -- visibility rules
  local function showCheck(label, col, row, get, set)
    local c = UI.Check(ed, L[label], false, function(v) local b = bar(); if b then set(b, v); changed() end end)
    c:SetPoint("TOPLEFT", 12 + col * 216, TOP - 2 - row * 26)
    c.get = get
    parts.visibility[#parts.visibility + 1] = c
    parts.visibility[#parts.visibility + 1] = c.text
    return c
  end
  local visChecks = {
    showCheck("Show", 0, 0, function(b) return b.enabled end, function(b, v) b.enabled = v end),
    showCheck("Only with a target", 1, 0, function(b) return b.show.target end, function(b, v) b.show.target = v or nil end),
    showCheck("Fade in on mouseover", 1, 1, function(b) return b.show.mouseover end, function(b, v) b.show.mouseover = v or nil end),
  }
  flagCheck("hideOOC", 0, 1, "visibility")
  local stanceLabel = UI.Text(ed, L["Stance / form"])
  stanceLabel:SetPoint("TOPLEFT", 12, TOP - 60)
  local stance = UI.Cycle(ed, 200, { { 0, "Any" } }, 0, function(v) local b = bar(); if b then b.show.stance = v > 0 and v or nil; changed() end end)
  stance:SetPoint("TOPLEFT", 228, TOP - 54)
  parts.visibility[#parts.visibility + 1] = stanceLabel
  parts.visibility[#parts.visibility + 1] = stance
  local function stanceOptions()
    local opts = { { 0, "Any" } }
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, (not ns.Secret.IsSecret(n) and tonumber(n)) or 0 do
      local _, _, _, spellID = GetShapeshiftFormInfo(i)
      opts[#opts + 1] = { i, (spellID and not ns.Secret.IsSecret(spellID) and ns.API.SpellName(spellID)) or (L["Stance %d"]):format(i) }
    end
    return opts
  end

  local info = UI.Text(ed, "")
  info:SetPoint("TOPLEFT", 12, -250)
  info:SetWidth(RIGHT_W - 24)
  info:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])

  local function action(label, col, row, onClick, style, tip)
    local b = UI.Button(ed, L[label], 134, onClick, style)
    b:SetPoint("TOPLEFT", 12 + col * 141, -276 - row * 28)
    b.tip = tip and L[tip] or nil
    return b
  end
  local move = action("Move in game", 0, 0, function()
    local b = bar(); if b and HUD.SetEditing(true) then HUD.Select(b.id) end
  end, nil, "Opens the edit mode with this bar selected.")
  local keys = action("Bind keys", 1, 0, function() HUD.Binder.SetActive(true) end, "ghost", "Hover a button, press a key · Delete clears · Esc ends")
  local refill = action("Refill from preset", 2, 0, function()
    local b = bar(); if b and ns.HUD.Content.Refill(b, ns.Classes.Player()) then changed() end
  end, "ghost", "Replaces the buttons with the known spells of the class preset. Undo restores them.")
  local undo = action("Undo", 0, 1, function() local b = bar(); if b and ns.HUD.Content.Undo(b) then changed() end end, "ghost")
  local clear = action("Clear buttons", 1, 1, function()
    local b = bar(); if not b then return end
    b.undo = ns.Util.DeepCopy(b.buttons); b.buttons = {}; changed()
  end, "ghost")
  local delete = action("Delete bar", 2, 1, function(self)
    if not selected then return end
    if not self.armed then
      self.armed = true; self:SetLabel(L["Really delete?"])
      C_Timer.After(3, function() self.armed = false; self:SetLabel(L["Delete bar"]) end)
      return
    end
    self.armed = false; self:SetLabel(L["Delete bar"])
    if HUD.DeleteBar(selected) then selected = nil; view.Refresh() end
  end, "danger")

  local numbers = action("Keys 1–0", 0, 2, function()
    local b = bar(); if b and HUD.UseNumberKeys(b.id) then view.Refresh() end
  end, "ghost", "Binds 1–0, - and = to the first buttons of this bar. Other bars give these keys up.")

  local tip = UI.Text(ed, L["Drag spells onto a bar. Shift+drag removes."])
  tip:SetPoint("BOTTOMLEFT", 12, 44)
  tip:SetWidth(RIGHT_W - 24)
  tip:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
  local showAll = UI.Check(ed, L["Show HUD bars"], ns.db.settings.hudEnabled, function(v) ns.db.settings.hudEnabled = v; HUD.Rebuild() end)
  showAll:SetPoint("BOTTOMLEFT", 12, 14)
  local hideMain = UI.Check(ed, L["Hide game bars"], ns.profile.hud.hideMain, function(v)
    ns.profile.hud.hideMain = v and true or false
    HUD.Blizzard.Apply()
    if v and not HUD.Blizzard.Found() then ns.Print(L["The game's main bar was not found on this client."]) end
  end)
  hideMain:SetPoint("BOTTOMLEFT", 226, 14)
  hideMain.tip = L["Hides the game's main bar. Its pet and stance bars follow once your own bars hold those buttons."]

  local always = { name, kind, preview, info, move, keys, refill, undo, clear, delete, numbers }
  for _, b in pairs(segs) do always[#always + 1] = b end

  function ns.UI.SelectBar(id) selected = id; view.Refresh() end

  function view.Refresh()
    local bars = HUD.Bars()
    if not selected or not ns.profile.hud.bars[selected] then selected = bars[1] and bars[1].id end
    list:SetNote(("%d"):format(#bars))
    for i, row in ipairs(rows) do
      local b = bars[i]
      row.barID = b and b.id
      if b then
        row.name:SetText(L[b.name])
        row.name:SetTextColor(b.enabled and UI.TEXT[1] or 0.5, b.enabled and UI.TEXT[2] or 0.5, b.enabled and UI.TEXT[3] or 0.5)
        row.grid:SetText(("%dx%d"):format(b.cols, b.rows))
        row.icon:SetTexture(Kinds.Get(b.kind).icon)
        row.eye:SetIcon(b.enabled and "eye" or "eye_off", 12)
        row.eye.iconTex:SetVertexColor(b.enabled and 0.37 or 0.5, b.enabled and 0.83 or 0.5, b.enabled and 0.37 or 0.5)
        UI.Skin(row, b.id == selected and "rowOn" or "row")
        row:Show()
      else
        row:Hide()
      end
    end
    local presets = HUD.Presets()
    for i, c in ipairs(chips) do
      local p = presets[i]
      c.presetKey, c.used = p and p.key, p and p.barID
      if p then
        c:SetLabel((p.barID and "|cff5fd35f+|r " or "+ ") .. L[p.title])
        c:SetStyle(p.barID and "buttonOff" or "ghost")
        c.tip = p.barID and L["Already on screen: click to select it."] or L["Creates this bar with your known spells."]
        c:Show()
      else
        c:Hide()
      end
    end

    hideMain:SetValue(ns.profile.hud.hideMain)
    local b = bar()
    empty:SetShown(b == nil)
    for _, part in ipairs(always) do part:SetShown(b ~= nil) end
    for key, list2 in pairs(parts) do
      for _, part in ipairs(list2) do part:SetShown(b ~= nil and key == view.section) end
    end
    if not b then return end
    for key, seg in pairs(segs) do seg:SetStyle(key == view.section and "button" or "ghost") end
    name:SetValue(L[b.name])
    kind:SetValue(b.kind)
    drawPreview(b)
    for field, s in pairs(steppers) do s:SetValue(b[field] * s.factor) end
    local eff = Kinds.Effective(b)
    for flag, c in pairs(flagChecks) do
      c:SetValue(eff[flag])
      if b.timers[flag] == nil then c.text:SetTextColor(0.6, 0.6, 0.6) else c.text:SetTextColor(1, 1, 1) end
    end
    for _, c in ipairs(visChecks) do c:SetValue(c.get(b)) end
    local opts = stanceOptions()
    stance:SetOptions(opts)
    stance:SetValue(b.show.stance or 0)
    local hasStances = #opts > 1
    if view.section == "visibility" then stance:SetShown(hasStances); stanceLabel:SetShown(hasStances) end
    local n = 0
    for slot in pairs(b.buttons) do if slot <= Model.Capacity(b) then n = n + 1 end end
    info:SetText((L["%d of %d slots filled"]):format(n, Model.Capacity(b)) .. "  ·  " .. (L["%d keys bound"]):format(ns.Util.Count(b.keys)))
    refill:SetShown(b.preset ~= nil)
    undo:SetShown(b.undo ~= nil)
  end
  return view
end, { icon = "Interface\\Icons\\INV_Misc_Gear_01", order = 90 })
