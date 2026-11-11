-- ClassPages: talent planner rules (classic three-tree system). Pure Lua, tested in tools/tests/talents_test.lua.
--   * Points: one per level from level 10 (level 60 -> 51), POINTS_PER_ROW points in a tree unlock its next row.
--   * A talent with a prerequisite needs that talent at max rank.
--   * Removing a point is only allowed if every remaining point still satisfies its row and prerequisite rules.
--
-- Build = { class, ranks = { [talentID] = rank }, order = { talentID, ... } }
--   order = the points in the sequence they were planned (one entry per point). Builds without a usable order
--   (imported text, copied live talents) get a default one: main tree first, top row first.
--
-- Public API (ns.Talents.Planner)
--   PointsForLevel(level) -> n
--   New(model) -> build, Spent(build, model, tree?) -> n
--   CanAdd(build, model, byID, id, level) -> ok, reason      Add(...) -> ok, reason
--   CanRemove(build, model, byID, id) -> ok, reason          Remove(...) -> ok, reason
--   Export(build, model) -> "1-2.0.5...|0...|..."   Import(text, model) -> build | nil, reason
--   Diff(build, current) -> { {id, want, have} }        what is still to learn compared to the live talents
--   Order(build, model, byID) -> { talentID, ... }       planned sequence (stored or default)
--   Next(build, model, byID, current) -> talentID, level | nil   next point to spend and the level that grants it
local ADDON, ns = ...

ns.Talents = ns.Talents or {}
local Planner = { POINTS_PER_ROW = 5, FIRST_LEVEL = 10 }
ns.Talents.Planner = Planner

function Planner.PointsForLevel(level)
  level = tonumber(level) or 0
  return math.max(0, level - Planner.FIRST_LEVEL + 1)
end

function Planner.New(model)
  return { class = model.class, ranks = {} }
end

function Planner.Spent(build, model, tree)
  local n = 0
  for t, tr in ipairs(model.trees) do
    if not tree or tree == t then
      for _, tal in ipairs(tr.talents) do n = n + (build.ranks[tal.id] or 0) end
    end
  end
  return n
end

-- points spent in a tree in rows above `row`
local function spentAbove(build, tree, row)
  local n = 0
  for _, tal in ipairs(tree.talents) do
    if tal.row < row then n = n + (build.ranks[tal.id] or 0) end
  end
  return n
end

function Planner.CanAdd(build, model, byID, id, level)
  local tal = byID[id]
  if not tal then return false, "unknown talent" end
  local rank = build.ranks[id] or 0
  if rank >= tal.maxRank then return false, "max rank" end
  if level and Planner.Spent(build, model) >= Planner.PointsForLevel(level) then return false, "no points left" end
  local tree = model.trees[tal.tree]
  if spentAbove(build, tree, tal.row) < (tal.row - 1) * Planner.POINTS_PER_ROW then return false, "row locked" end
  if tal.prereq then
    local pre = byID[tal.prereq]
    if pre and (build.ranks[pre.id] or 0) < pre.maxRank then return false, "requires prerequisite" end
  end
  return true
end

function Planner.Add(build, model, byID, id, level)
  local ok, why = Planner.CanAdd(build, model, byID, id, level)
  if ok then
    build.ranks[id] = (build.ranks[id] or 0) + 1
    build.order = Planner.Order(build, model, byID, id)
    build.order[#build.order + 1] = id
  end
  return ok, why
end

-- Is the whole build still valid? Used to test a removal.
local function valid(build, model, byID)
  for _, tree in ipairs(model.trees) do
    for _, tal in ipairs(tree.talents) do
      local rank = build.ranks[tal.id] or 0
      if rank > 0 then
        if spentAbove(build, tree, tal.row) < (tal.row - 1) * Planner.POINTS_PER_ROW then return false, "row locked" end
        if tal.prereq then
          local pre = byID[tal.prereq]
          if pre and (build.ranks[pre.id] or 0) < pre.maxRank then return false, "requires prerequisite" end
        end
      end
    end
  end
  return true
end
Planner.Valid = valid

function Planner.CanRemove(build, model, byID, id)
  local rank = build.ranks[id] or 0
  if rank <= 0 then return false, "no points" end
  build.ranks[id] = rank - 1
  local ok, why = valid(build, model, byID)
  build.ranks[id] = rank
  if not ok then return false, "other talents depend on it" end
  return true, why
end

function Planner.Remove(build, model, byID, id)
  local ok, why = Planner.CanRemove(build, model, byID, id)
  if ok then
    local r = build.ranks[id] - 1
    build.ranks[id] = r > 0 and r or nil
    for i = #(build.order or {}), 1, -1 do
      if build.order[i] == id then table.remove(build.order, i) break end
    end
  end
  return ok, why
end

-- True when the stored order holds exactly the points of `target`.
local function orderMatches(order, target)
  if type(order) ~= "table" then return false end
  local seen, n = {}, 0
  for _, id in ipairs(order) do seen[id] = (seen[id] or 0) + 1; n = n + 1 end
  local total = 0
  for id, rank in pairs(target) do
    if rank > 0 and seen[id] ~= rank then return false end
    total = total + rank
  end
  return n == total
end

-- skip = a talent whose newest point is not part of the order yet (used by Add).
function Planner.Order(build, model, byID, skip)
  local target = {}
  for id, rank in pairs(build.ranks) do target[id] = rank end
  if skip and target[skip] then target[skip] = target[skip] - 1 end
  if orderMatches(build.order, target) then return build.order end
  -- default: main tree first (most points), then by row and column
  local perTree = {}
  for id, rank in pairs(target) do
    local tal = byID[id]
    if tal then perTree[tal.tree] = (perTree[tal.tree] or 0) + rank end
  end
  local list = {}
  for id, rank in pairs(target) do if rank > 0 and byID[id] then list[#list + 1] = byID[id] end end
  table.sort(list, function(a, b)
    local pa, pb = perTree[a.tree] or 0, perTree[b.tree] or 0
    if pa ~= pb then return pa > pb end
    if a.tree ~= b.tree then return a.tree < b.tree end
    if a.row ~= b.row then return a.row < b.row end
    return a.col < b.col
  end)
  local temp, order = { ranks = {} }, {}
  local total = 0
  for _, tal in ipairs(list) do total = total + target[tal.id] end
  for _ = 1, total do
    local placed = false
    for _, tal in ipairs(list) do
      if (temp.ranks[tal.id] or 0) < target[tal.id] and Planner.CanAdd(temp, model, byID, tal.id, nil) then
        temp.ranks[tal.id] = (temp.ranks[tal.id] or 0) + 1
        order[#order + 1] = tal.id
        placed = true
        break
      end
    end
    if not placed then break end
  end
  return order
end

function Planner.Next(build, model, byID, current)
  local seen, have = {}, 0
  for _, rank in pairs(current or {}) do have = have + rank end
  for _, id in ipairs(Planner.Order(build, model, byID)) do
    seen[id] = (seen[id] or 0) + 1
    if ((current and current[id]) or 0) < seen[id] then return id, Planner.FIRST_LEVEL + have end
  end
  return nil
end

-- Export: one digit string per tree in talent order (row, col), trees separated by "-". Same format as the
-- classic talent calculators, so builds can be shared as text.
function Planner.Export(build, model)
  local parts = {}
  for t, tree in ipairs(model.trees) do
    local digits = {}
    for i, tal in ipairs(tree.talents) do digits[i] = tostring(math.min(9, build.ranks[tal.id] or 0)) end
    parts[t] = (table.concat(digits):gsub("0+$", ""))
  end
  return table.concat(parts, "-")
end

function Planner.Import(text, model)
  if type(text) ~= "string" or not text:match("^[%d%-]*$") then return nil, "invalid text" end
  local build = Planner.New(model)
  local t = 0
  for part in (text .. "-"):gmatch("([%d]*)%-") do
    t = t + 1
    local tree = model.trees[t]
    if not tree then break end
    for i = 1, #part do
      local tal = tree.talents[i]
      local r = tonumber(part:sub(i, i))
      if tal and r and r > 0 then
        if r > tal.maxRank then return nil, "rank too high" end
        build.ranks[tal.id] = r
      end
    end
  end
  local ok, why = valid(build, model, ns.Talents.Model.Index(model))
  if not ok then return nil, why end
  return build
end

-- Talents of the plan not reached yet by the live talents (current = { [id] = rank }).
function Planner.Diff(build, current)
  local out = {}
  for id, want in pairs(build.ranks) do
    local have = current and current[id] or 0
    if want > have then out[#out + 1] = { id = id, want = want, have = have } end
  end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end
