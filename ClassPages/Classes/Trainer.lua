-- ClassPages: trainer book. Nothing is hard-coded: every visit to a class or pet trainer is snapshotted (name, rank,
-- level, cost, learned or not) into ClassPagesDB.classes[CLASS].trainer, so the "Trainer" tab can show any time what is
-- learnable now, in the next two levels and later, and what it costs. Works for every class, pet trainers included.
-- Profession trainers are skipped. Costs are the last seen ones (reputation discounts change them slightly).
--
-- Public API (ns.Trainer)
--   Merge(store, services, now) -> store            pure: services = { {name, rank, status, level, cost} }
--   Groups(store, level) -> { now, soon, later, learned, costNow, costSoon }   pure; soon = next SOON_LEVELS levels
--   Rows(store, level, mode, money) -> rows          rows for the guide list (mode "level" | "all")
--   Store() -> the player's class store               Snapshot() -> count read from the open trainer window
--   LevelUpLine(level) -> text | nil
local ADDON, ns = ...
local L = ns.L

local Trainer = { SOON_LEVELS = 2 }
ns.Trainer = Trainer

local function key(s) return tostring(s.name) .. "|" .. tostring(s.rank or "") end

function Trainer.Merge(store, services, now)
  store.list = type(store.list) == "table" and store.list or {}
  for _, s in ipairs(services) do
    if type(s.name) == "string" and s.status ~= "header" then
      store.list[key(s)] = { name = s.name, rank = s.rank, status = s.status, level = tonumber(s.level) or 0, cost = tonumber(s.cost) or 0 }
    end
  end
  store.when = now
  return store
end

local function byLevel(a, b)
  if a.level ~= b.level then return a.level < b.level end
  if a.name ~= b.name then return a.name < b.name end
  return tostring(a.rank) < tostring(b.rank)
end

function Trainer.Groups(store, level)
  local g = { now = {}, soon = {}, later = {}, learned = 0, costNow = 0, costSoon = 0 }
  level = tonumber(level) or 1
  for _, s in pairs(store and store.list or {}) do
    if s.status == "used" then
      g.learned = g.learned + 1
    elseif s.level <= level then
      g.now[#g.now + 1] = s
      g.costNow = g.costNow + s.cost
    elseif s.level <= level + Trainer.SOON_LEVELS then
      g.soon[#g.soon + 1] = s
      g.costSoon = g.costSoon + s.cost
    else
      g.later[#g.later + 1] = s
    end
  end
  table.sort(g.now, byLevel); table.sort(g.soon, byLevel); table.sort(g.later, byLevel)
  return g
end

local RED, GREEN, GOLD = { 1, 0.42, 0.3 }, { 0.37, 0.83, 0.37 }, { 1, 0.82, 0.45 }
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local function entry(s, level, money)
  local status
  if s.level > level then status = { (L["from level %d"]):format(s.level), GOLD }
  elseif money and s.cost > money then status = { L["too expensive"], RED }
  else status = { L["learn now"], GREEN } end
  return { kind = "note", icon = ICON, confidence = "A", minLevel = math.max(1, s.level),
    name = s.rank and s.rank ~= "" and ("%s (%s)"):format(s.name, s.rank) or s.name,
    note = s.cost > 0 and ns.Util.Money(s.cost) or L["free"], status = status }
end

function Trainer.Rows(store, level, mode, money)
  local g = Trainer.Groups(store, level)
  local rows = {}
  local function section(title, list, cost)
    if #list == 0 then return end
    rows[#rows + 1] = { header = cost and cost > 0 and ("%s  ·  %s"):format(title, ns.Util.Money(cost)) or title }
    for _, s in ipairs(list) do rows[#rows + 1] = { entry = entry(s, level, money) } end
  end
  section(L["Learn now"], g.now, g.costNow)
  section((L["Next %d levels"]):format(Trainer.SOON_LEVELS), g.soon, g.costSoon)
  if mode == "all" then section(L["Later"], g.later) end
  return rows, g
end

-- Game side ---------------------------------------------------------------------------------------
function Trainer.Store()
  local class = ns.API.PlayerClass()
  if not class then return nil end
  ns.db.classes[class] = ns.db.classes[class] or {}
  local d = ns.db.classes[class]
  d.trainer = type(d.trainer) == "table" and d.trainer or {}
  return d.trainer
end

function Trainer.Snapshot()
  if not ns.Features.Available("trainer") then return 0 end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return 0 end
  local okN, n = pcall(GetNumTrainerServices)
  local services = {}
  for i = 1, okN and tonumber(n) or 0 do
    local ok, name, rank, status = pcall(GetTrainerServiceInfo, i)
    if ok and name and not ns.Secret.Any(name, rank, status) then
      local okL, level = pcall(GetTrainerServiceLevelReq, i)
      local okC, cost = pcall(GetTrainerServiceCost, i)
      services[#services + 1] = { name = name, rank = rank, status = status, level = okL and level or 0, cost = okC and cost or 0 }
    end
  end
  local store = Trainer.Store()
  if store and #services > 0 then Trainer.Merge(store, services, time()) end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return #services
end

function Trainer.LevelUpLine(level)
  local store = Trainer.Store()
  if not store or not store.list then return nil end
  local g = Trainer.Groups(store, level)
  if #g.now == 0 then return nil end
  return (L["Trainer: %d spells to learn (%s)."]):format(#g.now, ns.Util.Money(g.costNow))
end

ns:RegisterModule("Trainer", {
  Init = function()
    for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do ns.Events:On(e, function() Trainer.Snapshot() end, "Trainer") end
    ns.Events:On("PLAYER_LEVEL_UP", function(_, level)
      local line = Trainer.LevelUpLine(tonumber(level) or ns.API.PlayerLevel() or 1)
      if line then ns.Print(line) end
    end, "Trainer")
  end,
  SelfTest = function()
    local store = Trainer.Store()
    local ok, why = ns.Features.Available("trainer")
    return { { name = "trainer book", ok = true, warn = not ok, detail = ok and ("%d services known"):format(ns.Util.Count(store and store.list)) or why } }
  end,
})
