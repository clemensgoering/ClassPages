-- ClassPages: engine for data-only class pages (docs/04-KLASSENSEITEN.md). Knows no class: pages come from
-- Classes/Data/<CLASS>.lua via ns.Classes:AddPage. Pure logic (texts, level filter, list rows, validation) is tested
-- headless; the live status (owned, learned, done) asks the game through capability checks.
--
-- Public API (ns.Guide)
--   Text(t) -> string                        { enUS, deDE } or plain string in the active language
--   Relevant(entry, level) -> bool           entry worth showing at this player level
--   Rows(page, level, mode) -> rows          mode "level" | "all"; rows = { {header = text} | {entry = e} }
--   Validate(page) -> problems               list of strings (empty = valid)
--   Status(entry) -> text, color | nil        live state: owned count, learned, done, "from level X"
--   Icon(entry) -> texture
--   Name(entry) -> string                    live localized name for items and spells, else the data text
--   IconProviders[kind] = fn(entry) -> texture   (class files may add, e.g. pet family icons)
local ADDON, ns = ...
local L = ns.L

local Guide = { IconProviders = {} }
ns.Guide = Guide

Guide.KINDS = { item = true, spell = true, quest = true, pet = true, profession = true, note = true }
Guide.CONFIDENCE = { A = true, B = true, C = true }

local KIND_ICONS = {
  item = "Interface\\Icons\\INV_Misc_Bag_10", spell = "Interface\\Icons\\INV_Misc_Book_09", quest = "Interface\\GossipFrame\\AvailableQuestIcon",
  pet = "Interface\\Icons\\Ability_Hunter_BeastTaming", profession = "Interface\\Icons\\Trade_BlackSmithing", note = "Interface\\Icons\\INV_Misc_Note_01",
}

function Guide.Text(t)
  if type(t) == "string" then return t end
  if type(t) ~= "table" then return "" end
  local lang = ns.Locale.active
  return t[lang] or t.enUS or t.deDE or ""
end

-- Shown "for my level" from 5 levels before the entry until its end (maxLevel, or 10 levels after minLevel).
function Guide.Relevant(entry, level)
  level = tonumber(level) or 1
  local from = (entry.minLevel or 1) - 5
  local to = entry.maxLevel or ((entry.minLevel or 1) + 10)
  return level >= from and level <= to
end

function Guide.Rows(page, level, mode)
  local rows = {}
  for _, section in ipairs(page.sections or {}) do
    local list = {}
    for _, e in ipairs(section.entries or {}) do
      if mode == "all" or Guide.Relevant(e, level) then list[#list + 1] = e end
    end
    if #list > 0 then
      rows[#rows + 1] = { header = Guide.Text(section.title) }
      table.sort(list, function(a, b) if a.minLevel ~= b.minLevel then return (a.minLevel or 0) < (b.minLevel or 0) end return Guide.Text(a.name) < Guide.Text(b.name) end)
      for _, e in ipairs(list) do rows[#rows + 1] = { entry = e } end
    end
  end
  return rows
end

-- visible length (UTF-8 characters) of the longer language
local function len(t)
  local n = 0
  for _, s in pairs(type(t) == "table" and t or {}) do
    local c = 0
    for _ in tostring(s):gmatch("[^\128-\191]") do c = c + 1 end
    if c > n then n = c end
  end
  return n
end
Guide.LIMITS = { title = 12, section = 24, name = 40, note = 110, intro = 90 }

local function bilingual(t) return type(t) == "table" and type(t.enUS) == "string" and t.enUS ~= "" and type(t.deDE) == "string" and t.deDE ~= "" end

function Guide.Validate(page)
  local p = {}
  local function bad(msg) p[#p + 1] = tostring(page.key) .. ": " .. msg end
  if type(page.key) ~= "string" or not page.key:match("^%l[%w]*$") then bad("key must be camelCase") end
  if not bilingual(page.title) then bad("title needs enUS and deDE") end
  if len(page.title) > Guide.LIMITS.title then bad("title longer than " .. Guide.LIMITS.title) end
  if len(page.intro) > Guide.LIMITS.intro then bad("intro longer than " .. Guide.LIMITS.intro) end
  if page.intro ~= nil and not bilingual(page.intro) then bad("intro needs enUS and deDE") end
  if type(page.order) ~= "number" or page.order < 30 or page.order > 80 then bad("order must be 30-80") end
  if type(page.sections) ~= "table" or #page.sections == 0 then bad("no sections") return p end
  for s, section in ipairs(page.sections) do
    if not bilingual(section.title) then bad(("section %d title needs enUS and deDE"):format(s)) end
    if len(section.title) > Guide.LIMITS.section then bad(("section %d title longer than %d"):format(s, Guide.LIMITS.section)) end
    for i, e in ipairs(section.entries or {}) do
      local where = ("section %d entry %d (%s)"):format(s, i, Guide.Text(e.name))
      if not Guide.KINDS[e.kind] then bad(where .. ": unknown kind " .. tostring(e.kind)) end
      if not bilingual(e.name) then bad(where .. ": name needs enUS and deDE") end
      if not bilingual(e.note) then bad(where .. ": note needs enUS and deDE") end
      if len(e.note) > Guide.LIMITS.note then bad(where .. ": note longer than " .. Guide.LIMITS.note) end
      -- names with an ID come localized from the game; only data-chosen names are bounded
      if not e.itemID and not e.spellID and len(e.name) > Guide.LIMITS.name then bad(where .. ": name longer than " .. Guide.LIMITS.name) end
      if e.zone ~= nil and not bilingual(e.zone) then bad(where .. ": zone needs enUS and deDE") end
      if type(e.minLevel) ~= "number" or e.minLevel < 1 or e.minLevel > 60 then bad(where .. ": minLevel 1-60") end
      if e.maxLevel ~= nil and (type(e.maxLevel) ~= "number" or e.maxLevel < (e.minLevel or 1) or e.maxLevel > 60) then bad(where .. ": maxLevel") end
      for _, f in ipairs({ "itemID", "spellID", "questID" }) do
        if e[f] ~= nil and (type(e[f]) ~= "number" or e[f] <= 0 or e[f] % 1 ~= 0) then bad(where .. ": " .. f .. " must be a positive integer") end
      end
      if not Guide.CONFIDENCE[e.confidence] then bad(where .. ": confidence A/B/C") end
      if e.kind == "pet" and type(e.family) ~= "string" then bad(where .. ": pet needs family") end
      if e.tags ~= nil and type(e.tags) ~= "table" then bad(where .. ": tags must be a list") end
    end
  end
  return p
end

-- Live state ------------------------------------------------------------------------------------
local GREEN, GOLD, GREY = { 0.37, 0.83, 0.37 }, { 1, 0.82, 0.45 }, { 0.6, 0.6, 0.6 }

local function professionKnown(name)
  for _, p in ipairs(ns.Spellbook.Professions()) do
    if p.name == name then return true end
  end
  return false
end

function Guide.Status(e)
  if e.status then return e.status[1], e.status[2] end -- dynamic rows bring their own state
  local level = ns.API.PlayerLevel() or 1
  if e.kind == "item" and e.itemID then
    local n = ns.API.Call and select(2, ns.API.Call("C_Item.GetItemCount", e.itemID, true))
    n = tonumber(ns.Secret.Safe(n, 0)) or 0
    if n > 0 then return (L["%d owned"]):format(n), GREEN end
    return L["missing"], GREY
  elseif e.kind == "spell" and e.spellID then
    if ns.API.IsSpellKnown(e.spellID) then return L["learned"], GREEN end
  elseif e.kind == "quest" and e.questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, e.questID)
    if ok and done and not ns.Secret.IsSecret(done) then return L["done"], GREEN end
  elseif e.kind == "profession" then
    if professionKnown(Guide.Text(e.name)) then return L["learned"], GREEN end
    return "", GREY
  elseif e.kind == "pet" then
    if (e.minLevel or 1) > level then return (L["from level %d"]):format(e.minLevel), GOLD end
    return L["tameable"], GREEN
  end
  if (e.minLevel or 1) > level then return (L["from level %d"]):format(e.minLevel), GOLD end
  return "", GREY
end

function Guide.Icon(e)
  if e.icon then return e.icon end
  local provider = Guide.IconProviders[e.kind]
  local tex = provider and provider(e)
  if tex then return tex end
  if e.kind == "item" and e.itemID then tex = ns.API.Call and select(2, ns.API.Call("C_Item.GetItemIconByID", e.itemID)) end
  if e.kind == "spell" and e.spellID then tex = ns.API.SpellIcon(e.spellID) end
  return tex or KIND_ICONS[e.kind] or KIND_ICONS.note
end

-- Display name: live from the game for items and spells (already localized), else the data text.
function Guide.Name(e)
  if e.kind == "item" and e.itemID then
    local ok, n = ns.API.Call("C_Item.GetItemNameByID", e.itemID)
    if ok and type(n) == "string" and not ns.Secret.IsSecret(n) then return n end
  elseif e.kind == "spell" and e.spellID then
    local n = ns.API.SpellName(e.spellID)
    if n then return n end
  end
  return Guide.Text(e.name)
end
