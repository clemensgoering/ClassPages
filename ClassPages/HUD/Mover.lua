-- ClassPages: HUD edit mode, modelled on Blizzard's Edit Mode (docs/mockups/index.html, "Bearbeitungsmodus").
--   * Toolbar at the top: hint, "+ New bar", "Snap to grid", "Done".
--   * Every bar gets a plain (non-secure) overlay: name tab "Shots 8x1", drag = move (snaps to SNAP px when on),
--     corner grip = columns/rows by dragging, click = select and open the popover, mouse wheel = columns.
--   * Popover next to the selected bar: steppers for columns, rows, size, spacing; "More settings...", "Hide", "Delete"
--     (second click confirms).
-- Edit mode only exists out of combat; entering combat closes it (secure frames cannot move in combat anyway).
-- Every change is written to the saved bar first and re-applied through ns.HUD.ApplyBar.
--
-- Public API (ns.HUD.Mover)
--   SetShown(on), Sync(bar), Hide(id), Refresh(), frames[id]
--   CenterOffset(cx, cy, ux, uy, scale) -> x, y      pure: CENTER offsets of a scaled frame relative to UIParent
local ADDON, ns = ...
local L = ns.L

local HUD = ns.HUD
local UI = ns.UI
local Mover = { frames = {}, SNAP = 8 }
HUD.Mover = Mover

local toolbar, popover

function Mover.CenterOffset(cx, cy, ux, uy, scale)
  scale = scale ~= 0 and scale or 1
  return ns.Util.Round(cx - ux / scale, 1), ns.Util.Round(cy - uy / scale, 1)
end

local function barOf(id) return ns.profile and ns.profile.hud.bars[id] end
local function snapStep() return ns.profile.hud.snap ~= false and Mover.SNAP or 0 end

local function changed(id)
  local bar = barOf(id)
  if not bar or ns.Combat.InLockdown() then return end
  HUD.Model.Sanitize(bar)
  HUD.ApplyBar(id)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- Popover ------------------------------------------------------------------------------------------
local function buildPopover()
  popover = CreateFrame("Frame", "ClassPagesEditPopover", UIParent)
  popover:SetSize(250, 214)
  popover:SetFrameStrata("FULLSCREEN_DIALOG")
  popover:SetClampedToScreen(true)
  popover:EnableMouse(true)
  UI.Skin(popover, "popover")
  popover.title = UI.Text(popover, "", "GameFontNormal")
  popover.title:SetPoint("TOPLEFT", 12, -10)
  popover.title:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
  local close = UI.IconButton(popover, "close", 20, function() HUD.Select(nil) end, "ghost")
  close:SetPoint("TOPRIGHT", -8, -7)
  local LIM = HUD.Model.LIMITS
  popover.steppers = {}
  local rows = { { "cols", "Columns", 1 }, { "rows", "Rows", 1 }, { "size", "Button size", 2 }, { "spacing", "Spacing", 1 } }
  for i, r in ipairs(rows) do
    local field = r[1]
    local s = UI.Stepper(popover, L[r[2]], LIM[field][1], LIM[field][2], r[3], function(v)
      local bar = barOf(HUD.Selected())
      if bar then bar[field] = v; changed(bar.id) end
    end, nil, 226)
    s:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 26)
    popover.steppers[field] = s
  end
  local more = UI.Button(popover, L["More settings..."], 226, function()
    local id = HUD.Selected()
    ns.UI.Open("hud")
    if id and ns.UI.SelectBar then ns.UI.SelectBar(id) end
  end, "ghost")
  more:SetPoint("TOPLEFT", 12, -144)
  popover.hide = UI.Button(popover, L["Hide"], 110, function()
    local bar = barOf(HUD.Selected())
    if bar then HUD.SetEnabled(bar.id, not bar.enabled); Mover.Refresh(); if ns.UI.Refresh then ns.UI.Refresh() end end
  end, "ghost")
  popover.hide:SetPoint("TOPLEFT", 12, -174)
  popover.delete = UI.Button(popover, L["Delete"], 110, function(self)
    local id = HUD.Selected()
    if not id then return end
    if not self.armed then
      self.armed = true
      self:SetLabel(L["Really delete?"])
      C_Timer.After(3, function() self.armed = false; self:SetLabel(L["Delete"]) end)
      return
    end
    self.armed = false
    self:SetLabel(L["Delete"])
    HUD.DeleteBar(id)
    HUD.Select(nil)
    if ns.UI.Refresh then ns.UI.Refresh() end
  end, "danger")
  popover.delete:SetPoint("TOPLEFT", popover.hide, "TOPRIGHT", 6, 0)
  popover:Hide()
end

local function showPopover(id)
  local bar, m = barOf(id), Mover.frames[id]
  if not bar or not m or not HUD.IsEditing() then if popover then popover:Hide() end return end
  if not popover then buildPopover() end
  popover.title:SetText(L[bar.name])
  for field, s in pairs(popover.steppers) do s:SetValue(bar[field]) end
  popover.hide:SetLabel(bar.enabled and L["Hide"] or L["Show"])
  popover:ClearAllPoints()
  -- right of the bar when there is room, otherwise left of it
  local right = (m:GetRight() or 0) + popover:GetWidth() + 20 < (UIParent:GetWidth() or 1920)
  if right then popover:SetPoint("LEFT", m, "RIGHT", 14, 0) else popover:SetPoint("RIGHT", m, "LEFT", -14, 0) end
  popover:Show()
end

-- Overlays -------------------------------------------------------------------------------------------
local function paint(m, bar)
  local selected = HUD.Selected() == bar.id
  local r, g, b = UI.ClassColor()
  if selected then
    m.fill:SetColor(1, 0.82, 0.45, 0.18)
    m.edge:SetColor(1, 0.82, 0.45, 1)
  else
    m.fill:SetColor(r, g, b, bar.enabled and 0.22 or 0.08)
    m.edge:SetColor(r, g, b, bar.enabled and 0.9 or 0.4)
  end
  m.label:SetText(("%s  |cff9b9283%dx%d|r%s"):format(L[bar.name], bar.cols, bar.rows, bar.enabled and "" or ("  |cffff6a4c" .. L["hidden"] .. "|r")))
  m.tab:SetWidth((m.label:GetStringWidth() or 80) + 16)
  m.grip:SetShown(selected)
end

local function create(id)
  local header = HUD.Frames(id)
  if not header then return nil end
  local m = CreateFrame("Frame", nil, UIParent)
  m:SetFrameStrata("DIALOG")
  m:SetPoint("TOPLEFT", header, "TOPLEFT", -3, 3)
  m:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 3, -3)
  m.fill = UI.Slice(m, "rr3", 6, "BACKGROUND", -6)
  m.edge = UI.Slice(m, "rr3_ring", 6, "BORDER", 1)
  m.tab = CreateFrame("Frame", nil, m)
  m.tab:SetHeight(20)
  m.tab:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 3)
  UI.Skin(m.tab, "ghost")
  m.label = UI.Text(m.tab, "", "GameFontHighlightSmall")
  m.label:SetPoint("LEFT", 8, 0)

  m:EnableMouse(true)
  m:EnableMouseWheel(true)
  m:RegisterForDrag("LeftButton")
  header:SetMovable(true)
  m:SetScript("OnDragStart", function()
    if ns.Combat.InLockdown() then return end
    m.dragging = true
    HUD.Select(id)
    header:StartMoving()
  end)
  m:SetScript("OnDragStop", function()
    if not m.dragging or ns.Combat.InLockdown() then return end
    header:StopMovingOrSizing()
    local bar = barOf(id)
    if bar then
      local cx, cy = header:GetCenter()
      local ux, uy = UIParent:GetCenter()
      if cx and ux then
        local x, y = Mover.CenterOffset(cx, cy, ux, uy, bar.scale)
        local step = snapStep()
        bar.point = { "CENTER", HUD.Model.Snap(x, step), HUD.Model.Snap(y, step) }
      end
      HUD.ApplyBar(id)
    end
    C_Timer.After(0, function() m.dragging = false end)
    showPopover(id)
  end)
  m:SetScript("OnMouseUp", function(_, button)
    if m.dragging or button ~= "LeftButton" then return end
    HUD.Select(id)
  end)
  m:SetScript("OnMouseWheel", function(_, delta)
    local bar = barOf(id)
    if not bar then return end
    bar.cols = bar.cols + delta
    changed(id)
  end)

  -- corner grip: drag to change columns and rows
  local grip = CreateFrame("Button", nil, m)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
  local gt = grip:CreateTexture(nil, "OVERLAY")
  gt:SetAllPoints(grip)
  gt:SetTexture(UI.MEDIA .. "grip")
  gt:SetVertexColor(1, 0.82, 0.45, 1)
  grip:SetScript("OnMouseDown", function(self)
    local bar = barOf(id)
    if not bar or ns.Combat.InLockdown() then return end
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self.start = { x = cx / s, y = cy / s, cols = bar.cols, rows = bar.rows }
    self:SetScript("OnUpdate", function()
      local b = barOf(id)
      if not b or ns.Combat.InLockdown() then self:SetScript("OnUpdate", nil) return end
      local nx, ny = GetCursorPosition()
      local unit = (b.size + b.spacing) * b.scale
      local cols, rows = HUD.Model.GridFromDrag(self.start.cols, self.start.rows, nx / s - self.start.x, self.start.y - ny / s, unit)
      if cols ~= b.cols or rows ~= b.rows then b.cols, b.rows = cols, rows; changed(id) end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil); showPopover(id) end)
  m.grip = grip

  m:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(m, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Click: edit · drag: move · corner: size"], 1, 1, 1)
    GameTooltip:AddLine(L["Drop spells, items or macros onto the slots."], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  Mover.frames[id] = m
  return m
end

-- Toolbar --------------------------------------------------------------------------------------------
local function buildToolbar()
  toolbar = CreateFrame("Frame", "ClassPagesEditToolbar", UIParent)
  toolbar:SetSize(640, 66)
  toolbar:SetPoint("TOP", UIParent, "TOP", 0, -60)
  toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
  toolbar:EnableMouse(true)
  UI.Skin(toolbar, "popover")
  local title = UI.Text(toolbar, L["Edit HUD"], "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -9)
  title:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
  local hint = UI.Text(toolbar, L["Click a bar to edit · drag to move · drag the corner to resize"])
  hint:SetPoint("BOTTOMLEFT", 14, 9)
  hint:SetWidth(612)
  hint:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
  local done = UI.Button(toolbar, L["Done"], 80, function() HUD.SetEditing(false) end)
  done:SetPoint("TOPRIGHT", -12, -7)
  done:SetHeight(28)
  local snap = UI.Check(toolbar, L["Snap to grid"], true, function(v) ns.profile.hud.snap = v end)
  snap:SetPoint("RIGHT", done, "LEFT", -110, 0)
  toolbar.snap = snap
  local add = UI.Button(toolbar, L["+ New bar"], 100, function()
    local bar = HUD.AddBar({ name = L["New bar"], kind = "free", cols = 6, rows = 1, size = 36 })
    HUD.Select(bar.id)
    if ns.UI.Refresh then ns.UI.Refresh() end
  end, "ghost")
  add:SetPoint("RIGHT", snap, "LEFT", -14, 0)
  local keys = UI.Button(toolbar, L["Bind keys"], 110, function() HUD.Binder.SetActive(true) end, "ghost")
  keys:SetPoint("RIGHT", add, "LEFT", -6, 0)
  toolbar:Hide()
end

-- Public -------------------------------------------------------------------------------------------
function Mover.Sync(bar)
  local m = Mover.frames[bar.id] or (HUD.IsEditing() and create(bar.id))
  if not m then return end
  paint(m, bar)
  m:SetShown(HUD.IsEditing())
  if HUD.Selected() == bar.id and HUD.IsEditing() then showPopover(bar.id) end
end

function Mover.Hide(id)
  if Mover.frames[id] then Mover.frames[id]:Hide() end
  if popover and HUD.Selected() == id then popover:Hide() end
end

function Mover.Refresh()
  for id, m in pairs(Mover.frames) do
    local bar = barOf(id)
    if bar then paint(m, bar) end
  end
  local sel = HUD.Selected()
  if sel and HUD.IsEditing() then showPopover(sel) elseif popover then popover:Hide() end
end

function Mover.SetShown(on)
  if on and not toolbar then
    local ok, err = pcall(buildToolbar)
    if not ok then
      if toolbar then toolbar:Hide() end
      toolbar = nil
      ns.Health.Record("edit toolbar", err)
    end
  end
  if toolbar then
    toolbar:SetShown(on)
    if toolbar.snap then toolbar.snap:SetValue(ns.profile.hud.snap ~= false) end
  end
  for id, m in pairs(Mover.frames) do m:SetShown(on and barOf(id) ~= nil) end
  if not on then
    if popover then popover:Hide() end
    HUD.Select(nil)
  end
end

ns.Events:On("PLAYER_REGEN_DISABLED", function()
  -- still allowed here: the lockdown starts after this event. A bar that is being dragged is dropped where it is.
  for _, bar in ipairs(HUD.Bars()) do
    local header = HUD.Frames(bar.id)
    if header and header.StopMovingOrSizing then header:StopMovingOrSizing() end
  end
  if HUD.IsEditing() then
    Mover.SetShown(false)
    ns.Combat.Run("hudLock", function() HUD.SetEditing(false) end)
  end
end, "Mover")
