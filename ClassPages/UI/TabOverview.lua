-- ClassPages: overview tab (docs/mockups/index.html, "Übersicht"): four cards in a 2x2 grid.
--   1 talent distribution (bar per tree)   2+3 class cards from profile.overviewCards (Hunter: pet, ammunition),
--   filled up with "Professions" and "Class" for classes with fewer cards   4 HUD (bars, edit, unlock)
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

local CARD_W, CARD_H, ROWS = 370, 229, 7

local function kvCard(parent)
  local c = UI.Card(parent, CARD_W, CARD_H, "")
  c.rows = {}
  for i = 1, ROWS do
    local r = UI.KV(c, CARD_W - 24)
    r:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 22)
    c.rows[i] = r
  end
  function c:Fill(def)
    self.title:SetText(L[def.title or ""])
    self:SetNote(def.note or "")
    for i, r in ipairs(self.rows) do
      local row = def.rows and def.rows[i]
      if row then r:Set(L[row.label], row.value, row.color); r:Show() else r:Hide() end
    end
  end
  return c
end

-- Generic cards for classes without own ones.
local function professionsCard()
  local rows = {}
  for _, p in ipairs(ns.Spellbook.Professions()) do
    rows[#rows + 1] = { label = p.name, value = p.skill and p.maxSkill and ("%d / %d"):format(p.skill, p.maxSkill) or "" }
  end
  if #rows == 0 then rows[1] = { label = "No professions learned.", value = "" } end
  return { title = "Professions", rows = rows }
end

local function classCard()
  local class = ns.API.PlayerClass()
  return { title = "Class", rows = {
    { label = "Level", value = tostring(ns.API.PlayerLevel() or "?") },
    { label = "Known spells", value = tostring(ns.Spellbook.index.count or 0) },
    { label = "Class page", value = ns.Classes.profiles[class or ""] and L["full"] or L["generic"] },
  } }
end

UI.RegisterTab("overview", "Overview", function(frame)
  local view = {}

  local talents = UI.Card(frame, CARD_W, CARD_H, L["Talent distribution"])
  talents:SetPoint("TOPLEFT", 0, 0)
  local trees = {}
  for i = 1, 3 do
    local label = UI.Text(talents, "")
    label:SetPoint("TOPLEFT", 12, -44 - (i - 1) * 40)
    label:SetWidth(120)
    local bar = UI.Bar(talents, 200, 12)
    bar:SetPoint("LEFT", label, "RIGHT", 4, 0)
    local num = UI.Text(talents, "", "GameFontHighlight")
    num:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    trees[i] = { label = label, bar = bar, num = num }
  end
  local planner = UI.Button(talents, L["Open planner"], 130, function() UI.Open("talents") end)
  planner:SetPoint("BOTTOMLEFT", 12, 12)
  local talentHint = UI.Text(talents, "")
  talentHint:SetPoint("LEFT", planner, "RIGHT", 10, 0)
  talentHint:SetWidth(200)
  talentHint:SetWordWrap(false)
  talentHint:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])

  local second = kvCard(frame)
  second:SetPoint("TOPLEFT", talents, "TOPRIGHT", 12, 0)
  local third = kvCard(frame)
  third:SetPoint("TOPLEFT", talents, "BOTTOMLEFT", 0, -12)

  local hud = UI.Card(frame, CARD_W, CARD_H, L["HUD"])
  hud:SetPoint("TOPLEFT", third, "TOPRIGHT", 12, 0)
  local hudRows = {}
  for i = 1, 5 do
    local r = UI.KV(hud, CARD_W - 24)
    r:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 22)
    hudRows[i] = r
  end
  local edit = UI.Button(hud, L["Edit bars"], 120, function() UI.Open("hud") end)
  edit:SetPoint("BOTTOMLEFT", 12, 12)
  local unlock = UI.Button(hud, L["Move in game"], 130, function() ns.HUD.SetEditing(not ns.HUD.IsEditing()); view.Refresh() end, "ghost")
  unlock:SetPoint("LEFT", edit, "RIGHT", 8, 0)

  function view.Refresh()
    local model = ns.Talents.Tree()
    local cur = ns.Talents.Current()
    local total = 0
    for t, row in ipairs(trees) do
      local tree = model and model.trees[t]
      local n = 0
      for _, tal in ipairs(tree and tree.talents or {}) do n = n + (cur[tal.id] or 0) end
      total = total + n
      row.label:SetText(tree and tree.name or "")
      row.bar:SetValue(math.min(1, n / 31))
      row.bar:SetShown(tree ~= nil)
      row.num:SetText(tree and tostring(n) or "")
    end
    talents:SetNote((L["%d points"]):format(total))
    local nextTalent = model and ns.Talents.Next()
    talentHint:SetText(not model and L["Talent trees not read yet."] or nextTalent and (L["Next: %s"]):format(tostring(nextTalent.name)) or "")

    local cards = {}
    local profile = ns.Classes.Player()
    if profile.overviewCards then
      local ok, list = pcall(profile.overviewCards)
      if ok and type(list) == "table" then for _, c in ipairs(list) do cards[#cards + 1] = c end end
    end
    if #cards < 2 then cards[#cards + 1] = professionsCard() end
    if #cards < 2 then cards[#cards + 1] = classCard() end
    second:Fill(cards[1])
    third:Fill(cards[2])

    local bars, active = ns.HUD.Bars(), 0
    for _, b in ipairs(bars) do if b.enabled then active = active + 1 end end
    hud:SetNote((L["%d active bars"]):format(active))
    for i, r in ipairs(hudRows) do
      local b = bars[i]
      if b then r:Set(L[b.name], ("%dx%d"):format(b.cols, b.rows), not b.enabled and { 0.5, 0.5, 0.5 } or nil); r:Show() else r:Hide() end
    end
    unlock:SetLabel(ns.HUD.IsEditing() and L["Done"] or L["Move in game"])
  end
  return view
end, { icon = "Interface\\Icons\\INV_Misc_Book_09", order = 10 })
