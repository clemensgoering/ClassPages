-- ClassPages: highlight layer on top of the action buttons (LibActionButton draws cooldown, usability, range, procs).
--   * Ready flash: a short flash when a cooldown ends. Decided by a pure state machine from the non-secret `isActive`
--     flag (12.0.1+) or, out of combat, from start/duration. The global cooldown is filtered by elapsed wall time
--     (an active phase shorter than MIN_ACTIVE seconds never flashes), so no secret duration is ever compared.
--     If neither source is readable the flash simply stays off: degrade, never error.
--   * Reactive glow: while a reactive spell (class profile .reactive, e.g. Counterattack) is usable. A non-secret
--     usable flag toggles the glow; a secret one is handed to Region:SetAlphaFromBoolean when the client has it.
--
-- Public API (ns.HUD.Highlight)
--   ReadActive(info) -> true | false | nil      nil = cannot tell (secret / missing)        (pure)
--   Step(state, active, now) -> fire            advance a tracker; fire = flash now      (pure)
--   Tile(button)                                square 1 px frame instead of the template art (repeatable)
--   Attach(button)                              add flash + glow textures to a button frame
--   Resize(button)                              scale the glow to the button's current size
--   Flash(button), SetReactive(button, usable)  visuals
--   CountState(count, low) -> "none"|"ok"|"low"|"empty"   (pure; secret or missing count = "none")
--   SetCount(button, count, low, own)           colour the count text (own = draw the number ourselves)
--   SetKeyText(button, text)                    key binding label in the top right corner
local ADDON, ns = ...

ns.HUD = ns.HUD or {}
local Highlight = { MIN_ACTIVE = 2.0 }
ns.HUD.Highlight = Highlight

local Secret = ns.Secret

function Highlight.ReadActive(info)
  if type(info) ~= "table" then return nil end
  local active = info.isActive
  if active ~= nil and not Secret.IsSecret(active) then
    if info.isOnGCD ~= nil and not Secret.IsSecret(info.isOnGCD) and info.isOnGCD then return false end
    return active and true or false
  end
  local start, duration = info.startTime, info.duration
  if start == nil or duration == nil or Secret.Any(start, duration) then return nil end
  return (start > 0 and duration > 0) and true or false
end

-- state = { active = bool, since = time } (kept per button). Returns true when the flash should play.
function Highlight.Step(state, active, now)
  if active == nil then return false end
  if active then
    if not state.active then state.active, state.since = true, now end
    return false
  end
  local fire = state.active and state.since and (now - state.since) >= Highlight.MIN_ACTIVE or false
  state.active, state.since = false, nil
  return fire
end

-- Visuals -------------------------------------------------------------------------------------
local FLASH_TEX = "Interface\\Buttons\\CheckButtonHilight"
local GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"

-- Square tile look. The game's button template is drawn for 45 px buttons: on ours its frame, mask and
-- highlight sit off-centre. Template art is dropped, the icon is cropped and gets a 1 px frame.
-- Runs again after every library update, because the library re-applies its own sizes.
local EDGE = { 0.29, 0.23, 0.16 }

local function fit(region, button, inset)
  if not region or not region.ClearAllPoints then return end
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
  region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end

local function flat(region, button, r, g, b, a, blend)
  if not region or not region.SetColorTexture then return end
  region:SetColorTexture(r, g, b, a)
  if blend and region.SetBlendMode then region:SetBlendMode(blend) end
  fit(region, button, 1)
end

function Highlight.Tile(button)
  if button.MasqueSkinned then return end
  if not button.cpEdge then
    local edge = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    edge:SetAllPoints(button)
    button.cpEdge = edge
  end
  local icon = button.icon or button.cpIcon
  if icon then
    if button.IconMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(button.IconMask) end
    if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    fit(icon, button, 1)
  end
  local normal = button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture())
  if normal and normal.SetAlpha then normal:SetAlpha(0) end
  fit(button.SlotBackground, button, 1)
  fit(button.cooldown or button.cpCooldown, button, 1)
  flat(button.HighlightTexture or (button.GetHighlightTexture and button:GetHighlightTexture()), button, 1, 1, 1, 0.16, "ADD")
  flat(button.PushedTexture or (button.GetPushedTexture and button:GetPushedTexture()), button, 0, 0, 0, 0.35)
  flat(button.CheckedTexture or (button.GetCheckedTexture and button:GetCheckedTexture()), button, 1, 0.82, 0.45, 0.22, "ADD")
end

function Highlight.Attach(button)
  Highlight.Tile(button)
  if button.cpFlash then return end
  local flash = button:CreateTexture(nil, "OVERLAY")
  flash:SetTexture(FLASH_TEX)
  flash:SetBlendMode("ADD")
  flash:SetAllPoints(button)
  flash:SetAlpha(0)
  button.cpFlash = flash
  if flash.CreateAnimationGroup then
    local ag = flash:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.45); a2:SetOrder(2)
    button.cpFlashAnim = ag
  end

  local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
  glow:SetTexture(GLOW_TEX)
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(1, 0.85, 0.2)
  glow:SetPoint("CENTER", button, "CENTER", 0, 0)
  local w = button:GetWidth() or 36
  glow:SetSize(w * 1.9, w * 1.9)
  glow:Hide()
  button.cpGlow = glow
  if glow.CreateAnimationGroup then
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.5)
    button.cpGlowAnim = ag
  end
end

function Highlight.Resize(button)
  if button.cpGlow then
    local w = button:GetWidth() or 36
    button.cpGlow:SetSize(w * 1.9, w * 1.9)
  end
end

function Highlight.Flash(button)
  if not button.cpFlash then return end
  if button.cpFlashAnim then
    button.cpFlashAnim:Stop()
    button.cpFlashAnim:Play()
  end
end

-- usable may be a secret boolean in combat.
function Highlight.SetReactive(button, usable)
  local glow = button.cpGlow
  if not glow then return end
  if Secret.IsSecret(usable) then
    if glow.SetAlphaFromBoolean then
      glow:Show()
      local ok = pcall(glow.SetAlphaFromBoolean, glow, usable, 1, 0)
      if not ok then glow:Hide() end
    end
    return
  end
  if usable == nil then glow:Hide(); return
  end
  if usable then
    if not glow:IsShown() then
      glow:Show()
      glow:SetAlpha(1)
      if button.cpGlowAnim then button.cpGlowAnim:Play() end
    end
  elseif glow:IsShown() then
    if button.cpGlowAnim then button.cpGlowAnim:Stop() end
    glow:Hide()
  end
end

-- Counters ----------------------------------------------------------------------------------------
Highlight.LOW_DEFAULT = 5
local COUNT_COLORS = { ok = { 1, 1, 1 }, low = { 1, 0.6, 0.2 }, empty = { 1, 0.25, 0.25 } }

function Highlight.CountState(count, low)
  if count == nil or Secret.IsSecret(count) or type(count) ~= "number" then return "none" end
  if count <= 0 then return "empty" end
  if count <= (low or Highlight.LOW_DEFAULT) then return "low" end
  return "ok"
end

-- own = true: the button has no count text of its own (e.g. ammunition on the ranged attack), we draw the number.
function Highlight.SetCount(button, count, low, own)
  local state = Highlight.CountState(count, low)
  local fs = button.Count
  if own then
    if not button.cpCount then
      button.cpCount = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      button.cpCount:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    fs = button.cpCount
    fs:SetText(state == "none" and "" or tostring(count))
  elseif button.cpCount then
    button.cpCount:SetText("")
  end
  local c = COUNT_COLORS[state] or COUNT_COLORS.ok
  if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
  return state
end

function Highlight.SetKeyText(button, text)
  if not button.cpKey then
    if not text or text == "" then return end
    button.cpKey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.cpKey:SetPoint("TOPRIGHT", -2, -2)
    button.cpKey:SetTextColor(0.85, 0.85, 0.85)
  end
  button.cpKey:SetText(text or "")
end
