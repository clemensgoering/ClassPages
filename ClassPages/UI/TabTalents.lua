-- ClassPages: talent planner tab. Three trees side by side in the classic 4x7 grid, read live from the client.
-- Left click adds a point, right click removes one (only when the plan stays valid). Plans are named and saved per
-- class; "Compare" marks what the live talents still lack, export/import uses the calculator digit format.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

-- three trees fill the tab width (752): 242 px each, icons 40 px
local COLS, ROWS, CELL, GAPX, GAPY = 4, 7, 40, 19, 8
local TREE_W = COLS * CELL + (COLS - 1) * GAPX + 25

local REASONS = {
  ["max rank"] = "Already at max rank.", ["no points left"] = "No points left for this level.",
  ["row locked"] = "Spend more points in this tree first (5 per row).", ["requires prerequisite"] = "Requires the talent above at max rank.",
  ["other talents depend on it"] = "Other talents depend on this point.", ["no points"] = "No point to remove.",
}

UI.RegisterTab("talents", "Talents", function(frame)
  local view = { compare = false }
  local trees, cells = {}, {}
  local level = 60

  local status = UI.Text(frame, "")
  status:SetPoint("TOPLEFT", 2, -444)
  local message = UI.Text(frame, "")
  message:SetPoint("TOPLEFT", 2, -460)
  message:SetTextColor(1, 0.5, 0.4)

  for t = 1, 3 do
    local card = UI.Card(frame, TREE_W, ROWS * (CELL + GAPY) + 42)
    card:SetPoint("TOPLEFT", (t - 1) * (TREE_W + 12), 0)
    card.title = UI.Text(card, "", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 10, -8)
    trees[t] = card
    cells[t] = {}
  end

  local function plan() return ns.Talents.Plan() end

  local function setMessage(why) message:SetText(why and L[REASONS[why] or why] or "") end

  local function cellFor(t, tal)
    local key = tal.row .. ":" .. tal.col
    local c = cells[t][key]
    if not c then
      c = UI.Icon(trees[t], CELL)
      c:SetPoint("TOPLEFT", 13 + (tal.col - 1) * (CELL + GAPX), -34 - (tal.row - 1) * (CELL + GAPY))
      c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      c:SetScript("OnClick", function(self, button)
        local model, byID = ns.Talents.Tree()
        if not model or not self.talent then return end
        local ok, why
        if button == "RightButton" then ok, why = ns.Talents.Planner.Remove(plan(), model, byID, self.talent.id)
        else ok, why = ns.Talents.Planner.Add(plan(), model, byID, self.talent.id, level) end
        setMessage(not ok and why or nil)
        view.Refresh()
      end)
      c:SetScript("OnEnter", function(self)
        if not self.talent or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.talent.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.talent.spellID)
        else GameTooltip:AddLine(tostring(self.talent.name)) end
        GameTooltip:AddLine(L["Left click: add · Right click: remove"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      cells[t][key] = c
    end
    return c
  end

  -- toolbar
  local planBox = UI.Edit(frame, 120, function(text) ns.Talents.SetActivePlan(text); view.Refresh() end)
  planBox:SetPoint("TOPLEFT", 2, -388)
  local function nextPlan()
    local names = ns.Talents.Plans()
    local cur = ns.Talents.ActivePlanName()
    for i, n in ipairs(names) do if n == cur then return names[i % #names + 1] end end
    return names[1]
  end
  local switch = UI.Button(frame, L["Next plan"], 110, function() local n = nextPlan(); if n then ns.Talents.SetActivePlan(n) end view.Refresh() end, "ghost")
  switch:SetPoint("LEFT", planBox, "RIGHT", 6, 0)
  local reset = UI.Button(frame, L["Reset"], 100, function() local p = plan(); p.ranks, p.order = {}, nil; setMessage(); view.Refresh() end, "ghost")
  reset:SetPoint("LEFT", switch, "RIGHT", 6, 0)
  local fromLive = UI.Button(frame, L["Copy live talents"], 170, function()
    local p = plan()
    p.ranks, p.order = {}, nil
    for id, r in pairs(ns.Talents.Current()) do p.ranks[id] = r end
    view.Refresh()
  end, "ghost")
  fromLive:SetPoint("LEFT", reset, "RIGHT", 6, 0)
  local compare = UI.Button(frame, L["Compare"], 110, function() view.compare = not view.compare; view.Refresh() end, "ghost")
  compare:SetPoint("LEFT", fromLive, "RIGHT", 6, 0)
  local ioBox = UI.Edit(frame, 300, function(text)
    local model = ns.Talents.Tree()
    local build, why
    if model then build, why = ns.Talents.Planner.Import(text, model) end
    if build then local p = plan(); p.ranks, p.order = build.ranks, nil; setMessage() else setMessage(why or "invalid text") end
    view.Refresh()
  end)
  ioBox:SetPoint("TOPLEFT", planBox, "BOTTOMLEFT", 0, -6)
  local export = UI.Button(frame, L["Export"], 100, function()
    local model = ns.Talents.Tree()
    if model then ioBox:SetText(ns.Talents.Planner.Export(plan(), model)); ioBox:SetFocus(); ioBox:HighlightText() end
  end)
  export:SetPoint("LEFT", ioBox, "RIGHT", 6, 0)

  function view.Refresh()
    local model, byID = ns.Talents.Tree()
    if not model then
      status:SetText((L["Talent trees could not be read: %s"]):format(tostring(ns.Talents.LastError() or "?")) .. "  /cp talents dump")
      return
    end
    local p, cur = plan(), ns.Talents.Current()
    local nextTalent, nextLevel = ns.Talents.Next()
    planBox:SetValue(ns.Talents.ActivePlanName())
    local Planner = ns.Talents.Planner
    for t, card in ipairs(trees) do
      local tree = model.trees[t]
      for _, c in pairs(cells[t]) do c:Hide() end
      if tree then
        card.title:SetText(("%s  |cffffffff%d|r"):format(tree.name, Planner.Spent(p, model, t)))
        for _, tal in ipairs(tree.talents) do
          if tal.row <= ROWS and tal.col <= COLS then
            local c = cellFor(t, tal)
            c.talent = tal
            c.tex:SetTexture(tal.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local rank = p.ranks[tal.id] or 0
            local have = cur[tal.id] or 0
            c.badge:SetText(("%d/%d"):format(rank, tal.maxRank))
            local open = rank > 0 or Planner.CanAdd(p, model, byID, tal.id, nil)
            c.tex:SetDesaturated(not open)
            c.tex:SetAlpha(open and 1 or 0.45)
            if nextTalent and nextTalent.id == tal.id then UI.Skin(c, "popover")
            elseif view.compare and rank > have then UI.Skin(c, "button")
            elseif rank >= tal.maxRank then UI.Skin(c, "tabOn")
            else UI.Skin(c, open and "slot" or "locked") end
            if rank >= tal.maxRank then c.badge:SetTextColor(1, 0.82, 0) elseif rank > 0 then c.badge:SetTextColor(0.4, 1, 0.4) else c.badge:SetTextColor(0.7, 0.7, 0.7) end
            c:Show()
          end
        end
      end
    end
    local spent, avail = Planner.Spent(p, model), Planner.PointsForLevel(level)
    local text = (L["Plan: %d of %d points (level %d)"]):format(spent, avail, level)
    if nextTalent then text = text .. "  ·  " .. (L["Next: %s (level %d)"]):format(tostring(nextTalent.name), nextLevel) end
    if view.compare then text = text .. "  ·  " .. (L["%d talents still to learn (gold)"]):format(#Planner.Diff(p, cur)) end
    status:SetText(text)
  end
  return view
end, { icon = "Interface\\Icons\\Ability_Marksmanship", order = 20 })
