-- ClassPages: minimap button (class icon) and Blizzard's addon compartment entry. Left click toggles the class
-- window, right click toggles the HUD edit mode. Drag moves the button around the minimap (angle saved).
-- No library dependency; the drag OnUpdate only runs while dragging.
--
-- Public API (ns.Minimap)
--   Click(mouseButton)   left toggles the window, right toggles the HUD edit mode
--   Tooltip(tip)         fill a tooltip with the button's help lines
--   Compartment(_, mouseButton), CompartmentEnter(_, frame), CompartmentLeave()   globals on ClassPages for the TOC
local ADDON, ns = ...
local L = ns.L

local Mini = {}
ns.Minimap = Mini

local button

local function angle() return tonumber(ns.db.settings.minimapAngle) or 220 end

local function place(a)
  if not button or not Minimap then return end
  local rad = math.rad(a)
  local radius = (Minimap:GetWidth() / 2) + 6
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function onDragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  local a = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  if a < 0 then a = a + 360 end
  ns.db.settings.minimapAngle = ns.Util.Round(a, 1)
  place(a)
end

function Mini.Click(mouseButton)
  if mouseButton == "RightButton" then
    ns.HUD.SetEditing(not ns.HUD.IsEditing())
  else
    ns.UI.Toggle()
  end
end

function Mini.Tooltip(tip)
  tip:AddLine("ClassPages", 0.67, 0.83, 0.45)
  tip:AddLine(L["Left-click: open window"], 1, 1, 1)
  tip:AddLine(L["Right-click: unlock / lock HUD"], 1, 1, 1)
  tip:AddLine(L["Drag: move button"], 0.7, 0.7, 0.7)
end

local function create()
  if button or not Minimap then return end
  button = CreateFrame("Button", "ClassPagesMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local overlay = button:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture(ns.Classes.Player().icon or "Interface\\Icons\\INV_Misc_Book_09")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetPoint("TOPLEFT", 7, -6)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    Mini.Tooltip(GameTooltip)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnClick", function(_, mouseButton) Mini.Click(mouseButton) end)
  place(angle())
  if ns.db.settings.minimapHidden then button:Hide() end
end

-- Addon compartment (TOC: ## AddonCompartmentFunc / ...OnEnter / ...OnLeave). Globals by contract of the client.
function ClassPages.Compartment(_, mouseButton) Mini.Click(mouseButton) end
function ClassPages.CompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  Mini.Tooltip(GameTooltip)
  GameTooltip:Show()
end
function ClassPages.CompartmentLeave() GameTooltip:Hide() end

ns:RegisterModule("Minimap", {
  Login = function() create() end,
  SelfTest = function()
    return { { name = "minimap button", ok = button ~= nil, warn = button == nil, detail = button and (button:IsShown() and "visible" or "hidden") or "not created" } }
  end,
})

ns.Slash.Register("minimap", function(arg)
  if arg == "hide" or arg == "off" then
    ns.db.settings.minimapHidden = true
    if button then button:Hide() end
  elseif arg == "show" or arg == "on" then
    ns.db.settings.minimapHidden = false
    if button then button:Show() else create() end
  else
    ns.Print(L["usage: /cp minimap show|hide"])
  end
end, "show or hide the minimap button")
