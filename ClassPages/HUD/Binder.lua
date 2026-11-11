-- ClassPages: key binding mode. Hover a button and press a key (with Alt/Ctrl/Shift) to bind it; Delete, Backspace or
-- a right click clears the binding, Escape or "Done" ends the mode. Bindings are saved per bar (bar.keys) and applied
-- as override bindings by ns.HUD (they never touch the game's own key binding settings).
-- Only out of combat: the mode ends when combat starts.
--
-- Public API (ns.HUD.Binder)
--   SetActive(on) -> ok, IsActive(), Sync(bar)
--   Refresh()             repaint the visible overlays
--   Press(key)            handle a key press for the hovered button (used by the key frame and by tests)
--   Hover(barID, slot)    set the hovered button (nil = none)
local ADDON, ns = ...
local L = ns.L

local HUD = ns.HUD
local UI = ns.UI
local Binder = { overlays = {} }
HUD.Binder = Binder

local active, hovered, panel, keyFrame = false, nil, nil, nil

function Binder.IsActive() return active end
function Binder.Hover(barID, slot) hovered = barID and { barID, slot } or nil end

local function barOf(id) return ns.profile and ns.profile.hud.bars[id] end

local function paint(o)
  local bar = barOf(o.barID)
  local key = bar and bar.keys[o.slot]
  o.text:SetText(key and HUD.Model.ShortKey(key) or "")
  local isHover = hovered and hovered[1] == o.barID and hovered[2] == o.slot
  if isHover then o.fill:SetColor(1, 0.82, 0.45, 0.45)
  elseif key then o.fill:SetColor(0.3, 0.8, 0.3, 0.30)
  else o.fill:SetColor(0, 0, 0, 0.45) end
end

local function overlay(barID, slot, button)
  local id = barID .. ":" .. slot
  local o = Binder.overlays[id]
  if not o then
    o = CreateFrame("Button", nil, UIParent)
    o:SetFrameStrata("DIALOG")
    o.fill = o:CreateTexture(nil, "BACKGROUND") -- square like the button underneath
    o.fill:SetAllPoints(o)
    function o.fill:SetColor(r, g, b, a) self:SetColorTexture(r, g, b, a) end
    o.text = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    o.text:SetPoint("CENTER")
    o:RegisterForClicks("RightButtonUp")
    o:SetScript("OnEnter", function(self) Binder.Hover(self.barID, self.slot); Binder.Refresh() end)
    o:SetScript("OnLeave", function() Binder.Hover(nil); Binder.Refresh() end)
    o:SetScript("OnClick", function(self) Binder.Hover(self.barID, self.slot); Binder.Press("DELETE") end)
    Binder.overlays[id] = o
  end
  o.barID, o.slot = barID, slot
  o:ClearAllPoints()
  o:SetAllPoints(button)
  return o
end

function Binder.Refresh()
  for _, o in pairs(Binder.overlays) do if o:IsShown() then paint(o) end end
end

-- Shows the overlays of one bar (called for every bar when the mode starts and whenever a bar is re-applied).
function Binder.Sync(bar)
  local prefix = bar.id .. ":"
  for id, o in pairs(Binder.overlays) do if id:sub(1, #prefix) == prefix then o:Hide() end end
  if not active or not bar.enabled then return end
  local _, used = HUD.Frames(bar.id)
  for slot, button in pairs(used or {}) do
    local o = overlay(bar.id, slot, button)
    o:Show()
    paint(o)
  end
end

function Binder.Press(key)
  if not active then return end
  if key == "ESCAPE" then Binder.SetActive(false) return end
  if not hovered then return end
  local barID, slot = hovered[1], hovered[2]
  local chord
  if key ~= "DELETE" and key ~= "BACKSPACE" then
    chord = HUD.Model.Chord(key, IsAltKeyDown and IsAltKeyDown(), IsControlKeyDown and IsControlKeyDown(), IsShiftKeyDown and IsShiftKeyDown())
    if not chord then return end
  end
  local removed = HUD.Model.SetKey(ns.profile.hud, barID, slot, chord)
  HUD.ApplyBar(barID)
  if removed and removed[1] ~= barID then HUD.ApplyBar(removed[1]) end
  Binder.Refresh()
  if ns.UI.Refresh then ns.UI.Refresh() end
end

local function buildPanel()
  panel = CreateFrame("Frame", "ClassPagesBindPanel", UIParent)
  panel:SetSize(560, 66)
  panel:SetPoint("TOP", UIParent, "TOP", 0, -60)
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:EnableMouse(true)
  UI.Skin(panel, "popover")
  local title = UI.Text(panel, L["Bind keys"], "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -9)
  title:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
  local hint = UI.Text(panel, L["Hover a button, press a key · Delete clears · Esc ends"])
  hint:SetPoint("BOTTOMLEFT", 14, 9)
  hint:SetWidth(532)
  hint:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
  local done = UI.Button(panel, L["Done"], 80, function() Binder.SetActive(false) end)
  done:SetPoint("TOPRIGHT", -12, -7)
  done:SetHeight(28)
  keyFrame = CreateFrame("Frame", nil, panel)
  keyFrame:EnableKeyboard(true)
  if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(false) end
  keyFrame:SetScript("OnKeyDown", function(_, key) Binder.Press(key) end)
  panel:Hide()
end

function Binder.SetActive(on)
  if on and ns.Combat.InLockdown() then ns.Print(L["Not in combat."]) return false end
  if on and not ns.Features.Available("hudKeys") then ns.Print(L["Key bindings are not available on this client."]) return false end
  if on and HUD.IsEditing() then HUD.SetEditing(false) end
  if on and not panel then
    local ok, err = pcall(buildPanel)
    if not ok then
      if panel then panel:Hide() end
      panel = nil
      ns.Health.Record("bind panel", err)
      return false
    end
  end
  active = on and true or false
  hovered = nil
  if panel then panel:SetShown(active) end
  for _, bar in ipairs(HUD.Bars()) do Binder.Sync(bar) end
  return true
end

ns.Events:On("PLAYER_REGEN_DISABLED", function() if active then Binder.SetActive(false) end end, "Binder")
ns.Slash.Register("keys", function() Binder.SetActive(not active) end, "bind keys to HUD buttons (hover a button, press a key)")
