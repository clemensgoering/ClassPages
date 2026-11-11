-- ClassPages: the class window (docs/mockups/index.html, "Klassenfenster"). Layout: header band 64 px (ring logo with the
-- class icon, "<Class> · ClassPages", subtitle "Level 42 · Marksmanship 21/0/0", close), tab strip 30 px (icon + name,
-- active tab with gold plate and gold line), body below with the tab content built lazily.
-- Generic tabs exist for every class; class tabs (opts.classTab) only when the class profile lists them in .tabs.
-- A failure while building never leaves a half-built window: it is recorded and the next open tries again.
--
-- Public API (ns.UI)
--   RegisterTab(key, title, builder(frame) -> { Refresh = fn }, opts)   opts = { classTab = bool, icon = texture }
--   Open(key?), Toggle(key?), IsOpen(), Refresh(), Current() -> key
local ADDON, ns = ...
local L = ns.L

local UI = ns.UI
UI.tabs, UI.order = UI.tabs or {}, UI.order or {}

local WIDTH, HEIGHT, HEAD_H, TABS_H = 780, 594, 64, 30
UI.BODY_W, UI.BODY_H = WIDTH - 28, HEIGHT - HEAD_H - TABS_H - 24
local window, activeKey

function UI.RegisterTab(key, title, builder, opts)
  if UI.tabs[key] then return end
  UI.tabs[key] = { key = key, title = title, builder = builder, classTab = opts and opts.classTab, icon = opts and opts.icon,
    order = opts and opts.order or (50 + #UI.order) }
  UI.order[#UI.order + 1] = key
end

local function visibleTabs()
  local allowed = {}
  for _, k in ipairs(ns.Classes.Player().tabs or {}) do allowed[k] = true end
  local list = {}
  for _, key in ipairs(UI.order) do
    local tab = UI.tabs[key]
    if not tab.classTab or allowed[key] then list[#list + 1] = tab end
  end
  table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.key < b.key end)
  return list
end

-- "Level 42 · Marksmanship 21/0/0": the tree with the most points named, the split as numbers.
local function subtitle()
  local parts = { (L["Level %d"]):format(ns.API.PlayerLevel() or 0) }
  local model = ns.Talents and ns.Talents.Tree and ns.Talents.Tree()
  if model then
    local cur, per, best, bestN = ns.Talents.Current(), {}, nil, 0
    for t, tree in ipairs(model.trees) do
      local n = 0
      for _, tal in ipairs(tree.talents) do n = n + (cur[tal.id] or 0) end
      per[t] = n
      if n > bestN then best, bestN = tree.name, n end
    end
    parts[#parts + 1] = (best and (best .. " ") or "") .. table.concat(per, "/")
  end
  return table.concat(parts, "  ·  ")
end

local function headerInfo()
  local class = ns.API.PlayerClass()
  local localized = UnitClass and UnitClass("player") or class
  if ns.Secret.IsSecret(localized) then localized = class end
  window.title:SetText(("%s  |cff9b9283·|r  ClassPages"):format(tostring(localized)))
  window.subtitle:SetText(subtitle())
end

local function selectTab(key)
  local tab = UI.tabs[key]
  if not tab or not window then return end
  activeKey = key
  for k, t in pairs(UI.tabs) do
    if t.frame then t.frame:SetShown(k == key) end
    if t.button then t.button:SetActive(k == key) end
  end
  if not tab.frame then
    tab.frame = CreateFrame("Frame", nil, window.body)
    tab.frame:SetAllPoints(window.body)
    local ok, view = pcall(tab.builder, tab.frame)
    if not ok then
      ns.Health.Record("tab " .. key, view)
      local err = UI.Text(tab.frame, (L["This tab could not be built: %s"]):format(tostring(view)))
      err:SetPoint("TOPLEFT", 12, -12)
      err:SetWidth(UI.BODY_W - 24)
      view = nil
    end
    tab.view = view
  end
  tab.frame:Show()
  if tab.view and tab.view.Refresh then
    local ok, err = pcall(tab.view.Refresh)
    if not ok then ns.Health.Record("refresh " .. key, err) end
  end
  if ns.profile then ns.profile.window.tab = key end
end

-- Browser-style tab: icon and name; the active one gets the warm gold plate and a gold line along its bottom.
local function tabButton(tab)
  local b = CreateFrame("Button", nil, window.head or window) -- above the header plate
  b:SetHeight(TABS_H - 2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", 10, 0)
  b.icon:SetTexture(tab.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetText(type(tab.title) == "table" and ns.Guide.Text(tab.title) or L[tab.title])
  b:SetWidth(math.max(80, (b.text:GetStringWidth() or 60) + 42))
  function b:Paint()
    local on = self.active
    UI.Skin(self, on and "tabOn" or "tab")
    if self.hover and not on then self.cpSkin.fill:SetColor(0.135, 0.110, 0.080, 1) end
    self.icon:SetDesaturated(not on and not self.hover)
    if on then self.text:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
    elseif self.hover then self.text:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
    else self.text:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3]) end
  end
  function b:SetActive(on) self.active = on and true or false; self:Paint() end
  b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
  b:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
  b:SetScript("OnClick", function() selectTab(tab.key) end)
  b:SetActive(false)
  return b
end

local function buildTabs()
  local prev
  for _, tab in ipairs(visibleTabs()) do
    local b = tabButton(tab)
    if prev then b:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 3, 0) else b:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 14, -HEAD_H - TABS_H) end
    tab.button = b
    prev = b
  end
end

-- Header: a plate with a class-coloured gradient, the class icon as a framed square with rounded corners, title and subtitle, the
-- language menu and a close button. The tabs sit on a line that fades out to both sides.
local function buildHeader()
  local r, g, b = UI.ClassColor()
  local head = CreateFrame("Frame", nil, window)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEAD_H + TABS_H - 1)
  window.head = head
  local plate = UI.Slice(head, "tab", 7, "BACKGROUND", -5)
  plate:SetColor(0.082, 0.066, 0.046, 1)
  -- Class-coloured gradient over the full width. The middle part starts at the top edge; the two edge strips start
  -- below the plate's rounded corners and use the matching part of the gradient; the corners themselves are filled
  -- with the rounded corner of the plate shape in the same tint, so the header follows the window's corners exactly.
  local TINT_H, CORNER = HEAD_H + TABS_H - 4, 5
  local function tintPart(left, right, top)
    local t = UI.Art(head, "fade_v", "BACKGROUND", -4)
    t:SetPoint("TOPLEFT", head, left[1], left[2], -top)
    t:SetPoint("BOTTOMRIGHT", head, right[1], right[2], -TINT_H)
    t:SetTexCoord(0, 1, top / TINT_H, 1)
    t:SetVertexColor(r, g, b, 0.13)
  end
  tintPart({ "TOPLEFT", CORNER }, { "TOPRIGHT", -CORNER }, 0)
  tintPart({ "TOPLEFT", 0 }, { "TOPLEFT", CORNER }, CORNER)
  tintPart({ "TOPRIGHT", -CORNER }, { "TOPRIGHT", 0 }, CORNER)
  local SHAPE = 16 -- texels of the "tab" shape, drawn 1:1
  for _, side in ipairs({ { "TOPLEFT", 0, CORNER / SHAPE }, { "TOPRIGHT", 1 - CORNER / SHAPE, 1 } }) do
    local c = UI.Art(head, "tab", "BACKGROUND", -4)
    c:SetSize(CORNER, CORNER)
    c:SetPoint(side[1], head, side[1], 0, 0)
    c:SetTexCoord(side[2], side[3], 0, CORNER / SHAPE)
    c:SetVertexColor(r, g, b, 0.125)
  end
  local line = UI.Divider(window)
  line:SetPoint("TOPLEFT", 2, -HEAD_H - TABS_H)
  line:SetPoint("TOPRIGHT", -2, -HEAD_H - TABS_H)
  line:SetVertexColor(0.80, 0.62, 0.30, 1)

  -- everything in the header lives on the header frame, so it is drawn above the plate
  local logo = head:CreateTexture(nil, "ARTWORK")
  logo:SetSize(36, 36)
  logo:SetPoint("TOPLEFT", 16, -13)
  logo:SetTexture(ns.Classes.Player().icon or "Interface\\Icons\\INV_Misc_Book_09")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- square logo with the same corner radius as the window, framed in the class colour
  UI.Round(head, logo, "mask_logo")
  local frame = CreateFrame("Frame", nil, head)
  frame:SetPoint("TOPLEFT", logo, "TOPLEFT", -1, 1)
  frame:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", 1, -1)
  UI.Slice(frame, "rr5_ring", 7, "OVERLAY"):SetColor(r, g, b, 1)
  window.title = UI.Text(head, "", "GameFontNormalLarge")
  window.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
  window.title:SetTextColor(r, g, b)
  window.subtitle = UI.Text(head, "", "GameFontHighlightSmall")
  window.subtitle:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -4)
  window.subtitle:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])

  local close = UI.IconButton(head, "close", 24, function() window:Hide() end, "ghost")
  close:SetPoint("TOPRIGHT", -12, -19)
  local lang = UI.Dropdown(head, 210, ns.Locale.LANGUAGES, ns.db.settings.language, function(v)
    ns.db.settings.language = v
    ns.Locale.Set(v)
    ns.Print(L["Language changed. /reload updates all texts."])
  end)
  lang:SetPoint("RIGHT", close, "LEFT", -8, 0)
  lang.tip = L["Language"]
end

local function savePosition()
  local p, _, rp, x, y = window:GetPoint()
  if ns.profile and p then ns.profile.window.point = { p, rp, ns.Util.Round(x, 0), ns.Util.Round(y, 0) } end
end

local function build()
  window = CreateFrame("Frame", "ClassPagesWindow", UIParent)
  window:SetSize(WIDTH, HEIGHT)
  window:SetFrameStrata("HIGH")
  window:SetToplevel(true)
  window:SetClampedToScreen(true)
  local pt = ns.profile and ns.profile.window.point
  if type(pt) == "table" and pt[1] then window:SetPoint(pt[1], UIParent, pt[2] or pt[1], pt[3] or 0, pt[4] or 0)
  else window:SetPoint("CENTER") end
  UI.Skin(window, "window")
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
  buildHeader()
  window.body = CreateFrame("Frame", nil, window)
  window.body:SetPoint("TOPLEFT", 14, -HEAD_H - TABS_H - 12)
  window.body:SetPoint("BOTTOMRIGHT", -14, 12)
  buildTabs()
  if UISpecialFrames then table.insert(UISpecialFrames, "ClassPagesWindow") end
  window:SetScript("OnShow", function() headerInfo() end)
  window:Hide()
end

local function create()
  if window and window.body then return window end
  local ok, err = pcall(build)
  if not ok then
    if window then window:Hide() end
    window = nil
    ns.Health.Record("UI window", err)
    ns.Print((L["The window could not be built: %s"]):format(tostring(err)))
    return nil
  end
  return window
end

function UI.Open(key)
  if not create() then return end
  window:Show()
  headerInfo()
  local tabs = visibleTabs()
  key = key or activeKey or (ns.profile and ns.profile.window.tab)
  local allowed = false
  for _, t in ipairs(tabs) do if t.key == key then allowed = true end end
  if not allowed then key = tabs[1] and tabs[1].key end
  selectTab(key)
end

function UI.Toggle(key)
  if window and window:IsShown() and (not key or key == activeKey) then window:Hide() else UI.Open(key) end
end

function UI.IsOpen() return window ~= nil and window:IsShown() end
function UI.Current() return activeKey end

function UI.Refresh()
  if not UI.IsOpen() then return end
  headerInfo()
  local tab = activeKey and UI.tabs[activeKey]
  if tab and tab.view and tab.view.Refresh then
    local ok, err = pcall(tab.view.Refresh)
    if not ok then ns.Health.Record("refresh " .. activeKey, err) end
  end
end
