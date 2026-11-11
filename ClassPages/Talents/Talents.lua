-- ClassPages: talent module. Reads the trees once per client build (cached per class in ClassPagesDB), keeps the
-- live ranks up to date and stores named plans. Plans are never deleted by updates; a plan whose talents no longer
-- exist after a patch keeps its data and shows the unknown points as "outdated" instead.
--
-- Public API (ns.Talents)
--   Tree() -> model, byID             cached tree of the player's class (reads on first use)
--   Current() -> { [id] = rank }      live ranks
--   LastError() -> text | nil         error of the last read (nil when it worked)
--   Reload()                          read again (after a patch or on demand)
--   Next() -> talent, level           next point of the active plan compared to the live talents (nil when done)
--   Plans() -> sorted names, Plan(name) -> build (created on demand), DeletePlan(name), ActivePlanName(), SetActivePlan(name)
local ADDON, ns = ...
local L = ns.L

ns.Talents = ns.Talents or {}
local Talents = ns.Talents

local current, byID, lastError = {}, nil, nil
local readThisSession = false -- the cached layout survives /reload, the live ranks must be read once per session

local function classData()
  local class = ns.API.PlayerClass()
  if not class then return nil end
  ns.db.classes[class] = ns.db.classes[class] or {}
  local d = ns.db.classes[class]
  d.builds = type(d.builds) == "table" and d.builds or {}
  return d, class
end

function Talents.Reload()
  if ns.Combat.InLockdown() then return false end
  local d, class = classData()
  if not d then return false end
  local _, classID = ns.API.PlayerClass()
  local model, cur, err = Talents.Reader.Read(class, classID)
  lastError = err
  if not model then ns.Log("talents read failed", err) return false end
  local _, build = GetBuildInfo()
  model.build = not ns.Secret.IsSecret(build) and build or nil
  d.tree = model
  byID = Talents.Model.Index(model)
  current = cur or {}
  readThisSession = true
  return true
end

function Talents.Tree()
  local d = classData()
  if not d then return nil end
  local _, build = GetBuildInfo()
  local outdated = d.tree and d.tree.build and build and not ns.Secret.IsSecret(build) and d.tree.build ~= build
  if not d.tree or outdated or not readThisSession then Talents.Reload() end
  if d.tree and not byID then byID = Talents.Model.Index(d.tree) end
  return d.tree, byID
end

function Talents.Current() return current end
function Talents.LastError() return lastError end

function Talents.Plans()
  local d = classData()
  local names = {}
  for name in pairs(d and d.builds or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Talents.Plan(name)
  local d = classData()
  if not d then return nil end
  name = name or Talents.ActivePlanName()
  if type(d.builds[name]) ~= "table" then d.builds[name] = { ranks = {} } end
  local b = d.builds[name]
  if type(b.ranks) ~= "table" then b.ranks = {} end
  if b.order ~= nil and type(b.order) ~= "table" then b.order = nil end
  return b
end

function Talents.Next()
  local model, index = Talents.Tree()
  local plan = model and Talents.Plan()
  if not plan or next(plan.ranks) == nil then return nil end
  local id, level = Talents.Planner.Next(plan, model, index, current)
  return id and index[id] or nil, level
end

function Talents.ActivePlanName()
  local d = classData()
  return d and type(d.activeBuild) == "string" and d.activeBuild or "Plan 1"
end

function Talents.SetActivePlan(name)
  local d = classData()
  if d and type(name) == "string" and name ~= "" then d.activeBuild = name; Talents.Plan(name) end
end

function Talents.DeletePlan(name)
  local d = classData()
  if not d or not d.builds[name] then return false end
  ns.DB.Backup("delete talent plan " .. name)
  d.builds[name] = nil
  if d.activeBuild == name then d.activeBuild = nil end
  return true
end

-- Talent events arrive several at a time; the tree is read once per burst.
local function reread()
  local d = classData()
  if not d or not d.tree then return end
  if Talents.Reload() and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end
local function refreshCurrent() ns.Events.Later("talents", 0.5, reread) end

ns:RegisterModule("Talents", {
  Init = function()
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
      ns.Events:On(e, refreshCurrent, "Talents")
    end
    ns.Events:On("PLAYER_LEVEL_UP", function()
      local tal = Talents.Next()
      if tal then ns.Print((L["Talent point: your plan says %s."]):format(tostring(tal.name))) end
    end, "Talents")
  end,
  SelfTest = function()
    local model = Talents.Tree()
    if not model then return { { name = "talent trees", ok = false, warn = true, detail = tostring(lastError or "not read yet") } } end
    local counts = {}
    for t, tree in ipairs(model.trees) do counts[t] = ("%s %d"):format(tostring(tree.name), #tree.talents) end
    return {
      { name = "talent trees", ok = #model.trees == 3, warn = #model.trees ~= 3, detail = model.source .. ": " .. table.concat(counts, ", ") },
      { name = "live ranks", ok = true, detail = ("%d talents with points"):format(ns.Util.Count(current)) },
    }
  end,
})

ns.Slash.Register("talents", function(arg)
  if arg == "dump" then
    local lines = Talents.Reader.Dump()
    ns.db.probe.talents = lines
    for _, l in ipairs(lines) do ns.Print(l) end
    return
  end
  if arg == "reload" then
    ns.Print(Talents.Reload() and L["Talent trees read again."] or (L["Talent trees could not be read: %s"]):format(tostring(lastError)))
    return
  end
  if ns.UI then ns.UI.Open("talents") end
end, "open the talent planner (dump | reload)")
