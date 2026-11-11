-- ClassPages: pet action button. LibActionButton has no pet type, so pet slots use a thin secure button
-- (left click / key: type = "pet", action = slot; right click: toggles autocast through a macro line).
-- Cooldowns are passed straight from GetPetActionCooldown to the Cooldown widget, and the "active" and "autocast on"
-- markers take secret booleans through SetAlphaFromBoolean (secret-safe pass-through, nothing is compared).
--
-- Markers: gold frame = action is active (stance, running ability); corner marks = can autocast;
--          pulsing inner frame = autocast is on.
--
-- Public API (ns.HUD.PetButton)
--   Create(name, parent) -> button     out of combat only
--   Assign(button, slot)               secure attributes (out of combat)
--   Update(button)                     icon, active/autocast state, usability, cooldown (any time)
local ADDON, ns = ...

ns.HUD = ns.HUD or {}
local PetButton = {}
ns.HUD.PetButton = PetButton

local Secret = ns.Secret

-- Square frame of four lines on its own child frame, so it can be shown, faded and animated as one.
local function ring(owner, parent, inset, thick, r, g, b)
  local f = CreateFrame("Frame", nil, owner)
  f:SetAllPoints(parent)
  local function line(a1, a2, x1, y1, x2, y2, w, h)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(r, g, b, 1)
    t:SetPoint(a1, parent, a1, x1, y1)
    t:SetPoint(a2, parent, a2, x2, y2)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  line("TOPLEFT", "TOPRIGHT", inset, -inset, -inset, -inset, nil, thick)
  line("BOTTOMLEFT", "BOTTOMRIGHT", inset, inset, -inset, inset, nil, thick)
  line("TOPLEFT", "BOTTOMLEFT", inset, -inset, inset, inset, thick, nil)
  line("TOPRIGHT", "BOTTOMRIGHT", -inset, -inset, -inset, inset, thick, nil)
  return f
end

-- value: boolean, or a secret boolean in combat (then the widget decides, we never look at it)
local function mark(region, value)
  if Secret.IsSecret(value) then
    if region.SetAlphaFromBoolean then
      region:Show()
      pcall(region.SetAlphaFromBoolean, region, value, 1, 0)
    end
    return
  end
  region:SetAlpha(1)
  region:SetShown(value and true or false)
end

function PetButton.Create(name, parent)
  -- same template order as LibActionButton: the secure template comes last, so its click handler wins
  local b = ns.UI and ns.UI.SafeCreate and ns.UI.SafeCreate("CheckButton", parent, { "ActionButtonTemplate, SecureActionButtonTemplate", "SecureActionButtonTemplate" }, name)
    or CreateFrame("CheckButton", name, parent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetSize(36, 36)
  b.cpIcon = b.icon or b.Icon or _G[(name or "") .. "Icon"]
  if not b.cpIcon then
    b.cpIcon = b:CreateTexture(nil, "ARTWORK")
    b.cpIcon:SetAllPoints(b)
  end
  b.cpCooldown = b.cooldown or b.Cooldown or _G[(name or "") .. "Cooldown"]
  if not b.cpCooldown then
    b.cpCooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cpCooldown:SetAllPoints(b)
  end
  local auto = b:CreateTexture(nil, "OVERLAY")
  auto:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
  auto:SetPoint("CENTER")
  auto:SetSize(58, 58)
  auto:Hide()
  b.cpAutoCast = auto
  b.cpActive = ring(b, b, 0, 2, 1, 0.82, 0.45)
  b.cpActive:Hide()
  -- the pulse sits on an inner frame: the outer one keeps its alpha for SetAlphaFromBoolean
  b.cpAutoOn = CreateFrame("Frame", nil, b)
  b.cpAutoOn:SetAllPoints(b)
  b.cpAutoOn:Hide()
  local pulse = ring(b.cpAutoOn, b, 3, 1, 1, 0.95, 0.4)
  if pulse.CreateAnimationGroup then
    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.6)
    ag:Play()
  end
  -- the check state would flip with every click; the gold frame shows "active" instead
  b:SetScript("PostClick", function(self)
    if self.SetChecked then self:SetChecked(false) end
    PetButton.Update(self)
  end)
  b:SetScript("OnEnter", function(self)
    if not self.cpSlot or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetPetAction then GameTooltip:SetPetAction(self.cpSlot) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b.cpIsPet = true
  return b
end

function PetButton.Assign(b, slot)
  if ns.Combat.InLockdown() then return false end
  b.cpSlot = slot
  b:SetAttribute("type1", "pet")
  b:SetAttribute("action", slot)
  b.cpAutoName = nil
  PetButton.Update(b)
end

-- Right click toggles autocast. The secure attributes can only change out of combat; the name is not secret there.
local function setAutoToggle(b, name)
  if b.cpAutoName == name or ns.Combat.InLockdown() then return end
  b.cpAutoName = name
  b:SetAttribute("type2", name and "macro" or nil)
  b:SetAttribute("macrotext2", name and ("/petautocasttoggle " .. name) or nil)
end

function PetButton.Update(b)
  local slot = b.cpSlot
  if not slot or not GetPetActionInfo then return end
  local ok, name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = pcall(GetPetActionInfo, slot)
  if not ok or (not Secret.IsSecret(name) and not name) then
    b.cpIcon:SetTexture(nil)
    b.cpAutoCast:Hide()
    b.cpActive:Hide()
    b.cpAutoOn:Hide()
    if b.cpCooldown.Clear then b.cpCooldown:Clear() end
    return
  end
  if not Secret.Any(isToken, texture) and isToken and type(texture) == "string" and _G[texture] then texture = _G[texture] end
  b.cpIcon:SetTexture(texture)
  if b.SetChecked then b:SetChecked(false) end
  mark(b.cpActive, isActive)
  mark(b.cpAutoCast, autoCastAllowed)
  mark(b.cpAutoOn, autoCastEnabled)
  if not Secret.Any(name, isToken, autoCastAllowed) then
    setAutoToggle(b, (autoCastAllowed and not isToken and type(name) == "string") and name or false)
  end
  if GetPetActionSlotUsable then
    local okU, usable = pcall(GetPetActionSlotUsable, slot)
    if okU and not Secret.IsSecret(usable) then
      local c = usable and 1 or 0.4
      b.cpIcon:SetVertexColor(c, c, c)
    end
  end
  if GetPetActionCooldown and b.cpShowCooldown ~= false then
    local okC, start, duration = pcall(GetPetActionCooldown, slot)
    if okC then pcall(b.cpCooldown.SetCooldown, b.cpCooldown, start, duration) end
  end
end
