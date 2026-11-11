-- ClassPages: list view (UI.GuideView) and renderer for data-only class pages (docs/04-KLASSENSEITEN.md). One window tab per page of every class;
-- the window shows only the pages of the player's class (classTab). Layout (body 752 x 476):
--   top: intro (left), "for my level / all" filter and entry count (right)
--   list card: section headers and entry rows (icon, name, level · zone, note, live status), mouse wheel scrolls
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

local ROW_H, LIST_W, LIST_H, TOP_H = 42, 752, 436, 30
local VISIBLE = math.floor((LIST_H - 20) / ROW_H)
local FILTERS = { { "level", "For my level" }, { "all", "All levels" } }

local function levelText(e)
  if e.maxLevel and e.maxLevel ~= e.minLevel then return (L["Level %d-%d"]):format(e.minLevel, e.maxLevel) end
  return (L["Level %d"]):format(e.minLevel)
end

local function buildPage(page)
  return function(frame)
    local view = { offset = 0, mode = "level", rows = {} }
    local Guide = ns.Guide

    local intro = UI.Text(frame, type(page.intro) == "string" and L[page.intro] or Guide.Text(page.intro))
    intro:SetPoint("TOPLEFT", 2, -2)
    intro:SetWidth(470)
    intro:SetWordWrap(false)
    intro:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
    local filter = UI.Cycle(frame, 170, FILTERS, "level", function(v) view.mode = v; view.offset = 0; view.Refresh() end)
    filter:SetPoint("TOPRIGHT", 0, 0)
    local count = UI.Text(frame, "")
    count:SetPoint("RIGHT", filter, "LEFT", -10, 0)
    count:SetJustifyH("RIGHT")
    count:SetWidth(80)
    count:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])

    local list = UI.Card(frame, LIST_W, LIST_H)
    list:SetPoint("TOPLEFT", 0, -TOP_H - 8)
    list:EnableMouseWheel(true)
    local empty = UI.Text(list, L[page.empty or "Nothing for your level here. Switch to all levels."])
    empty:SetPoint("CENTER")

    local lines = {}
    for i = 1, VISIBLE do
      local row = CreateFrame("Button", nil, list)
      row:SetSize(LIST_W - 32, ROW_H - 2)
      row:SetPoint("TOPLEFT", 10, -10 - (i - 1) * ROW_H)
      row.hl = UI.Slice(row, "rr3", 6, "BACKGROUND", -5)
      row.hl:SetColor(1, 0.8, 0.4, 0.08)
      row.hl:SetShown(false)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(28, 28)
      row.icon:SetPoint("LEFT", 6, 0)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      UI.Round(row, row.icon)
      row.name = UI.Text(row, "", "GameFontHighlightSmall")
      row.name:SetPoint("TOPLEFT", 44, -6)
      row.name:SetWidth(230)
      row.name:SetWordWrap(false)
      row.sub = UI.Text(row, "")
      row.sub:SetPoint("BOTTOMLEFT", 44, 6)
      row.sub:SetWidth(230)
      row.sub:SetWordWrap(false)
      row.sub:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3])
      row.note = UI.Text(row, "")
      row.note:SetPoint("LEFT", 286, 0)
      row.note:SetWidth(320)
      row.note:SetHeight(ROW_H - 12)
      row.note:SetJustifyV("MIDDLE")
      row.note:SetTextColor(0.85, 0.82, 0.76)
      row.status = UI.Text(row, "")
      row.status:SetPoint("RIGHT", -6, 0)
      row.status:SetWidth(96)
      row.status:SetJustifyH("RIGHT")
      row.header = UI.Text(row, "", "GameFontNormal")
      row.header:SetPoint("BOTTOMLEFT", 6, 8)
      row.header:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
      row.rule = UI.Divider(row)
      row.rule:SetPoint("BOTTOMLEFT", 0, 3); row.rule:SetPoint("BOTTOMRIGHT", 0, 3)
      row:SetScript("OnEnter", function(self)
        local e = self.entry
        self.hl:SetShown(e ~= nil)
        if not e or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.kind == "item" and e.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.itemID)
        elseif e.kind == "spell" and e.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(e.spellID)
        else GameTooltip:AddLine(Guide.Name(e), 1, 0.82, 0.45) end
        GameTooltip:AddLine(Guide.Text(e.note), 1, 1, 1, true)
        if e.confidence ~= "A" then GameTooltip:AddLine(L["~ not yet confirmed for Forever"], 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function(self) self.hl:SetShown(false); if GameTooltip then GameTooltip:Hide() end end)
      lines[i] = row
    end

    local thumb = UI.Art(list, "pill", "OVERLAY")
    thumb:SetWidth(5)
    thumb:SetVertexColor(1, 0.82, 0.45, 0.55)

    local function draw()
      local total = #view.rows
      for i, row in ipairs(lines) do
        local item = view.rows[view.offset + i]
        row.entry = item and item.entry
        local isHeader = item and item.header ~= nil
        row.header:SetShown(isHeader)
        row.rule:SetShown(isHeader)
        for _, part in ipairs({ row.icon, row.name, row.sub, row.note, row.status }) do part:SetShown(row.entry ~= nil) end
        if isHeader then
          row.header:SetText(item.header)
        elseif row.entry then
          local e = row.entry
          row.icon:SetTexture(Guide.Icon(e))
          row.name:SetText((e.confidence ~= "A" and "|cff9b9283~|r " or "") .. Guide.Name(e))
          local zone = e.zone and Guide.Text(e.zone)
          row.sub:SetText(levelText(e) .. (zone and zone ~= "" and ("  ·  " .. zone) or ""))
          row.note:SetText(Guide.Text(e.note))
          local text, color = Guide.Status(e)
          row.status:SetText(text or "")
          if color then row.status:SetTextColor(color[1], color[2], color[3]) end
        end
        row.hl:SetShown(false)
        row:SetShown(item ~= nil)
      end
      empty:SetShown(total == 0)
      thumb:SetShown(total > VISIBLE)
      if total > VISIBLE then
        local trackH = LIST_H - 20
        local h = math.max(20, trackH * VISIBLE / total)
        local y = (trackH - h) * view.offset / (total - VISIBLE)
        thumb:ClearAllPoints()
        thumb:SetHeight(h)
        thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -10 - y)
      end
    end

    list:SetScript("OnMouseWheel", function(_, delta)
      local maxOffset = math.max(0, #view.rows - VISIBLE)
      view.offset = math.max(0, math.min(maxOffset, view.offset - delta * 3))
      draw()
    end)

    function view.Refresh()
      local level = ns.API.PlayerLevel() or 1
      -- dynamic pages (e.g. the trainer book) build their rows from live data
      view.rows = page.dynamic and page.dynamic(level, view.mode) or Guide.Rows(page, level, view.mode)
      local n = 0
      for _, r in ipairs(view.rows) do if r.entry then n = n + 1 end end
      count:SetText((L["%d entries"]):format(n))
      view.offset = math.min(view.offset, math.max(0, #view.rows - VISIBLE))
      draw()
    end
    return view
  end
end

UI.GuideView = buildPage

for _, page in ipairs(ns.Classes.AllPages()) do
  UI.RegisterTab(page.key, page.title, buildPage(page), { classTab = true, icon = page.icon, order = page.order or 50 })
end
