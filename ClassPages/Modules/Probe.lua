-- ClassPages: live API probe for the HUD. Measures on the real client which values are secret, once out of combat
-- and once in combat (run /cp probe while fighting, e.g. from a macro), and stores the result for /cp debug.
-- This is how we learn Forever's actual rules instead of guessing; nothing here changes game state.
--
-- Public API (ns.Probe)
--   Run() -> lines        probe now (context = "combat" or "idle"), stored in ClassPagesDB.probe.hud[context]
--   Capabilities() -> lines   presence of the widget/API helpers the HUD can use
local ADDON, ns = ...
local L = ns.L

local Probe = {}
ns.Probe = Probe

local function flag(v)
  if v == nil then return "nil" end
  if ns.Secret.IsSecret(v) then return "SECRET" end
  return tostring(v)
end

function Probe.Capabilities()
  local out = {}
  local function has(label, ok) out[#out + 1] = ("%s: %s"):format(label, ok and "yes" or "no") end
  has("issecretvalue", issecretvalue ~= nil)
  has("C_Spell.GetSpellCooldownDuration", ns.API.Has("C_Spell.GetSpellCooldownDuration"))
  has("C_Secrets.ShouldSpellCooldownBeSecret", ns.API.Has("C_Secrets.ShouldSpellCooldownBeSecret"))
  has("C_CurveUtil", ns.API.Has("C_CurveUtil"))
  has("ActionButtonSpellAlertManager", ActionButtonSpellAlertManager ~= nil)
  has("C_SpellActivationOverlay.IsSpellOverlayed", ns.API.Has("C_SpellActivationOverlay.IsSpellOverlayed"))
  has("RegisterStateDriver", RegisterStateDriver ~= nil)
  local tex = UIParent and UIParent.CreateTexture and UIParent:CreateTexture()
  has("Region:SetAlphaFromBoolean", tex and tex.SetAlphaFromBoolean ~= nil)
  if tex then tex:Hide() end
  local cd = CreateFrame("Cooldown", nil, UIParent)
  has("Cooldown:SetCooldownFromDurationObject", cd.SetCooldownFromDurationObject ~= nil)
  cd:Hide()
  local LAB = LibStub and LibStub("LibActionButton-1.0", true)
  out[#out + 1] = "LibActionButton: " .. (LAB and tostring(select(2, LibStub:GetLibrary("LibActionButton-1.0"))) or "missing")
  local _, build, _, interface = GetBuildInfo()
  out[#out + 1] = ("client %s, interface %s, WOW_PROJECT_ID %s"):format(flag(build), flag(interface), flag(WOW_PROJECT_ID))
  return out
end

-- spells on the HUD (up to 12) or the class profile's first spells
local function spellsToProbe()
  local list, seen = {}, {}
  for _, bar in ipairs(ns.HUD.Bars()) do
    for _, b in pairs(bar.buttons) do
      if b.type == "spell" and #list < 12 then
        local id = ns.Spellbook.Resolve(b.id) or b.id
        if not seen[id] then seen[id] = true; list[#list + 1] = id end
      end
    end
  end
  return list
end

function Probe.Run()
  local context = ns.Combat.InLockdown() and "combat" or "idle"
  local lines = { ("context %s, %s"):format(context, date and date("%Y-%m-%d %H:%M") or "") }
  for _, l in ipairs(Probe.Capabilities()) do lines[#lines + 1] = l end
  local usable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
  for _, id in ipairs(spellsToProbe()) do
    local name = ns.API.SpellName(id) or ("#" .. id)
    local cd = C_Spell and C_Spell.GetSpellCooldown and select(2, pcall(C_Spell.GetSpellCooldown, id))
    local u, noMana
    if usable then
      local ok, a, b = pcall(usable, id)
      if ok then u, noMana = a, b end
    end
    local secretRule = ns.API.Has("C_Secrets.ShouldSpellCooldownBeSecret") and select(2, pcall(C_Secrets.ShouldSpellCooldownBeSecret, id))
    lines[#lines + 1] = ("%s: isActive=%s isOnGCD=%s start=%s dur=%s usable=%s noMana=%s ruleSecret=%s"):format(
      name, flag(type(cd) == "table" and cd.isActive), flag(type(cd) == "table" and cd.isOnGCD), flag(type(cd) == "table" and cd.startTime),
      flag(type(cd) == "table" and cd.duration), flag(u), flag(noMana), flag(secretRule))
  end
  ns.db.probe.hud = ns.db.probe.hud or {}
  ns.db.probe.hud[context] = lines
  return lines
end

ns.Slash.Register("probe", function()
  local lines = Probe.Run()
  for _, l in ipairs(lines) do ns.Print(l) end
  ns.Print(L["Probe saved. Run it once out of combat and once in combat, then /cp debug."])
end, "measure which HUD values are readable (run in and out of combat)")
