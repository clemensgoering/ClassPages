-- ClassPages: hides the game's own action bars, so ClassPages bars can take their place (keys 1-0 included).
-- One setting, three bars:
--   main    hidden as soon as the setting is on
--   pet     hidden only while an enabled ClassPages bar holds pet actions
--   stance  hidden only while an enabled ClassPages bar holds one of the character's stances / forms
-- Nothing is destroyed: a bar moves under a hidden frame and comes back when its condition ends.
-- While the player controls another unit (possess bar, sky riding) the main bar is shown again, because those
-- actions only exist there. Vehicles use the game's separate override bar and are not touched.
-- Secure frames: every change runs through ns.Combat.Run.
--
-- Public API (ns.HUD.Blizzard)
--   Apply()                    make the game bars match the setting (any time; deferred in combat)
--   Wanted() -> bool           setting on and HUD enabled
--   Found(group) -> name|nil   which frame of a group ("main" by default) exists on this client
--   Hidden() -> { main, pet, stance }   what Apply would hide right now
-- Data: ns.profile.hud.hideMain (bool)
local ADDON, ns = ...

local HUD = ns.HUD
local Blizzard = {
  GROUPS = {
    main = { "MainActionBar", "MainMenuBar" },
    pet = { "PetActionBar", "PetActionBarFrame" },
    stance = { "StanceBar", "StanceBarFrame" },
  },
  SHOW_WHEN = "[possessbar][bonusbar:5] show; hide",
}
HUD.Blizzard = Blizzard

local hiders = {}
local original = {} -- [frame] = parent before hiding

function Blizzard.Wanted()
  local hud = ns.profile and ns.profile.hud
  return (hud and hud.hideMain and ns.db.settings.hudEnabled) and true or false
end

function Blizzard.Found(group)
  for _, name in ipairs(Blizzard.GROUPS[group or "main"] or {}) do
    local bar = _G[name]
    if type(bar) == "table" and bar.SetParent then return name end
  end
end

local function stanceNames()
  local names = {}
  local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
  for i = 1, (not ns.Secret.IsSecret(n) and tonumber(n)) or 0 do
    local _, _, _, spellID = GetShapeshiftFormInfo(i)
    local name = spellID and not ns.Secret.IsSecret(spellID) and ns.API.SpellName(spellID)
    if name then names[name] = true end
  end
  return names
end

function Blizzard.Hidden()
  local out = { main = false, pet = false, stance = false }
  if not Blizzard.Wanted() then return out end
  local names = stanceNames()
  local covers = HUD.Model.Replaces(ns.profile.hud, function(id)
    local name = ns.API.SpellName(ns.Spellbook.Resolve(id) or id)
    return name ~= nil and names[name] == true
  end)
  out.main, out.pet, out.stance = true, covers.pet, covers.stance
  return out
end

-- The main bar's hider reappears while another unit is controlled; the others stay hidden.
local function getHider(group)
  if hiders[group] then return hiders[group] end
  local hider
  if group == "main" then
    hider = ns.UI.SafeCreate("Frame", UIParent, { "SecureHandlerStateTemplate" }, "ClassPagesGameBarHider")
    if RegisterStateDriver then RegisterStateDriver(hider, "visibility", Blizzard.SHOW_WHEN) end
  else
    hider = CreateFrame("Frame", nil, UIParent)
  end
  hider:SetAllPoints(UIParent)
  hider:Hide()
  hiders[group] = hider
  return hider
end

function Blizzard.Apply()
  if not Blizzard.Wanted() and not next(original) then return end
  ns.Combat.Run("gameBars", function()
    local hidden = Blizzard.Hidden()
    for group, names in pairs(Blizzard.GROUPS) do
      for _, name in ipairs(names) do
        local bar = _G[name]
        if type(bar) == "table" and bar.SetParent then
          if hidden[group] and not original[bar] then
            original[bar] = bar:GetParent() or UIParent
            bar:SetParent(getHider(group))
          elseif not hidden[group] and original[bar] then
            bar:SetParent(original[bar])
            original[bar] = nil
          end
        end
      end
    end
  end)
end

ns:RegisterModule("GameBar", {
  Login = function() Blizzard.Apply() end,
  SelfTest = function()
    local rows, hidden = {}, Blizzard.Hidden()
    for _, group in ipairs({ "main", "pet", "stance" }) do
      local name = Blizzard.Found(group)
      rows[#rows + 1] = {
        name = "game " .. group .. " bar", ok = true, warn = name == nil and hidden[group],
        detail = (name or "not found") .. (hidden[group] and ", hidden" or ", untouched"),
      }
    end
    return rows
  end,
})
ns.Events:On("PLAYER_ENTERING_WORLD", function() Blizzard.Apply() end, "GameBar")
ns.Events:On("UPDATE_SHAPESHIFT_FORMS", function() Blizzard.Apply() end, "GameBar")
