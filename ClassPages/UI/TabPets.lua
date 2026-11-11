-- ClassPages: pet tab (class tab, listed by the Hunter profile). Active pet card, abilities, beast training list,
-- stable and family facts. Data comes from ns.HunterPets snapshots, so the tab also shows the last known state
-- while the stable or the beast training window is closed.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

local ABILITY_ROWS, TRAINING_ROWS, STABLE_ROWS, FAMILY_ROWS = 8, 9, 4, 19

local STATUS_COLOR = { used = { 0.4, 1, 0.4 }, available = { 1, 0.82, 0 }, unavailable = { 0.6, 0.6, 0.6 } }

local function lines(parent, count, x, y, width, step)
  local out = {}
  for i = 1, count do
    local fs = UI.Text(parent, "")
    fs:SetPoint("TOPLEFT", x, y - (i - 1) * (step or 16))
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    out[i] = fs
  end
  return out
end

UI.RegisterTab("pets", "Pets", function(frame)
  local view = {}
  local Pets = ns.HunterPets

  local pet = UI.Card(frame, 244, 200, L["Active pet"])
  pet:SetPoint("TOPLEFT", 0, 0)
  local petName = UI.Text(pet, "", "GameFontHighlight")
  petName:SetPoint("TOPLEFT", 12, -38)
  local happy = UI.Bar(pet, 220, 20)
  happy:SetPoint("TOPLEFT", 12, -60)
  local info = lines(pet, 5, 12, -92, 220, 18)

  local abilities = UI.Card(frame, 244, 240, L["Abilities"])
  abilities:SetPoint("TOPLEFT", pet, "BOTTOMLEFT", 0, -10)
  local abil = lines(abilities, ABILITY_ROWS, 12, -38, 220, 22)

  local training = UI.Card(frame, 244, 200, L["Beast training"])
  training:SetPoint("TOPLEFT", pet, "TOPRIGHT", 10, 0)
  local train = lines(training, TRAINING_ROWS, 12, -38, 220)

  local stable = UI.Card(frame, 244, 240, L["Stable"])
  stable:SetPoint("TOPLEFT", training, "BOTTOMLEFT", 0, -10)
  local stab = lines(stable, STABLE_ROWS, 12, -38, 220, 20)
  local stableHint = UI.Text(stable, L["Open the stable once to refresh this list."])
  stableHint:SetPoint("BOTTOMLEFT", 12, 10)
  stableHint:SetWidth(220)
  stableHint:SetTextColor(0.6, 0.6, 0.6)

  local families = UI.Card(frame, 244, 450, L["Families"])
  families:SetPoint("TOPLEFT", training, "TOPRIGHT", 10, 0)
  local fam = lines(families, FAMILY_ROWS, 12, -38, 220, 21)

  function view.Words(list)
    local out = {}
    for i, w in ipairs(list) do out[i] = L[w] end
    return table.concat(out, ", ")
  end

  function view.Refresh()
    local cur = Pets.Current()
    if cur.name then
      petName:SetText(("%s  |cffaaaaaa%s · %s %s|r"):format(cur.name, tostring(cur.family or "?"), L["Level"], tostring(cur.level or "?")))
      local text, color = Pets.HappinessText(cur.happiness)
      happy:SetValue((cur.happiness or 0) / 3)
      happy:SetStatusBarColor(color[1], color[2], color[3])
      happy.text:SetText(L[text] .. (cur.damagePct and (" · " .. cur.damagePct .. "% " .. L["damage"]) or ""))
      local fam1 = Pets.Family(cur.family)
      local rows = {
        cur.loyalty and (L["Loyalty"] .. ": " .. tostring(cur.loyalty)) or "",
        cur.tpTotal and ((L["Training points"] .. ": %d / %d"):format(cur.tpTotal - (cur.tpSpent or 0), cur.tpTotal)) or "",
        cur.xpMax and cur.xpMax > 0 and ((L["Experience"] .. ": %d%%"):format(math.floor(cur.xp / cur.xpMax * 100))) or "",
        L["Diet"] .. ": " .. (cur.diet and table.concat(cur.diet, ", ") or (fam1.diet and ("~" .. view.Words(fam1.diet)) or "?")),
        fam1.unique and (L["Family ability"] .. ": " .. L[fam1.unique]) or "",
      }
      for i, fs in ipairs(info) do fs:SetText(rows[i] or "") end
    else
      petName:SetText(L["no active pet"])
      happy:SetValue(0)
      happy.text:SetText("")
      for _, fs in ipairs(info) do fs:SetText("") end
    end

    local list = cur.abilities or {}
    for i, fs in ipairs(abil) do
      local a = list[i]
      fs:SetText(a and ("|T%s:16|t  %s  |cffaaaaaa%s|r"):format(tostring(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark"), a.name, a.rank or "") or "")
    end

    local tr = Pets.Training()
    local tlist = tr.list or {}
    for i, fs in ipairs(train) do
      local e = tlist[i]
      if e then
        local c = STATUS_COLOR[e.status] or STATUS_COLOR.unavailable
        fs:SetText(("%s %s  |cffaaaaaa%s|r"):format(e.name, e.rank or "", e.cost and e.cost > 0 and (e.cost .. " TP") or ""))
        fs:SetTextColor(c[1], c[2], c[3])
      else
        fs:SetText(i == 1 and L["Open Beast Training once to fill this list."] or "")
        fs:SetTextColor(0.6, 0.6, 0.6)
      end
    end

    local st = Pets.Stable().pets or {}
    for i, fs in ipairs(stab) do
      local p = st[i]
      fs:SetText(p and ("%s  |cffaaaaaa%s · %s|r"):format(p.name, tostring(p.family or "?"), tostring(p.level or "?")) or "")
    end

    for i, fs in ipairs(fam) do
      local f = Pets.FAMILIES[i]
      if f then
        local seen = ns.db.families[L[f.key]] or ns.db.families[f.key]
        fs:SetText(("%s%s  |cffaaaaaa%s|r"):format(seen and "|cff66ff66" or "", L[f.key], L[f.unique]))
      else
        fs:SetText("")
      end
    end
  end
  return view
end, { classTab = true, icon = "Interface\\Icons\\Ability_Hunter_BeastCall", order = 30 })
