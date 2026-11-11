-- ClassPages: talent tree model. Pure Lua; the game adapters (Talents/Reader.lua) deliver raw nodes and this file
-- turns them into the classic layout the planner works on. Nothing is hard-coded per class: the trees are read
-- live from the client and cached in ClassPagesDB.classes[CLASS].tree, so the planner also works for other classes
-- and survives talent changes in patches (a new client build simply re-reads the trees).
--
-- Model
--   { class, source = "traits"|"classic", build, trees = { { name, icon, talents = { talent, ... } } x3 } }
--   talent = { id, tree, row, col, maxRank, name, icon, spellID, prereq = id|nil, entryID, nodeID }
--   row / col are 1-based (row 1 = top, 7 rows of 4 columns in the classic trees)
--
-- Public API (ns.Talents.Model)
--   FromClassic(class, tabs) -> model      tabs = { {name, icon, talents = { {name, icon, tier, column, maxRank, prereqTier, prereqColumn} }} }
--   FromNodes(class, nodes, treeNames) -> model   nodes = { {nodeID, posX, posY, maxRanks, name, icon, spellID, entryID, subTreeID, edges = {targetNodeID}} }
--   Index(model) -> byID                    talent lookup
--   Grid(values) -> map value -> 1-based index (positions snapped to their smallest step)
local ADDON, ns = ...

ns.Talents = ns.Talents or {}
local Model = {}
ns.Talents.Model = Model

function Model.Index(model)
  local byID = {}
  for t, tree in ipairs(model.trees) do
    for _, tal in ipairs(tree.talents) do
      tal.tree = t
      byID[tal.id] = tal
    end
  end
  return byID
end

local function sortTalents(tree)
  table.sort(tree.talents, function(a, b)
    if a.row ~= b.row then return a.row < b.row end
    return a.col < b.col
  end)
end

function Model.FromClassic(class, tabs)
  local model = { class = class, source = "classic", trees = {} }
  for t, tab in ipairs(tabs) do
    local tree = { name = tab.name or ("Tree " .. t), icon = tab.icon, talents = {} }
    local byPos = {}
    for i, raw in ipairs(tab.talents) do
      local tal = { id = t * 100 + i, tree = t, row = raw.tier, col = raw.column, maxRank = raw.maxRank or 1,
        name = raw.name, icon = raw.icon, spellID = raw.spellID, index = i }
      tree.talents[#tree.talents + 1] = tal
      byPos[raw.tier .. ":" .. raw.column] = tal
      tal.prereqPos = raw.prereqTier and (raw.prereqTier .. ":" .. raw.prereqColumn) or nil
    end
    for _, tal in ipairs(tree.talents) do
      if tal.prereqPos and byPos[tal.prereqPos] then tal.prereq = byPos[tal.prereqPos].id end
      tal.prereqPos = nil
    end
    sortTalents(tree)
    model.trees[t] = tree
  end
  return model
end

-- Distinct positions -> 1-based grid index, robust against float noise and empty rows/columns:
-- the step is the smallest gap between distinct values (gaps below `eps` count as the same position).
function Model.Grid(values, eps)
  eps = eps or 1
  local distinct = {}
  table.sort(values)
  for _, v in ipairs(values) do
    if #distinct == 0 or v - distinct[#distinct] > eps then distinct[#distinct + 1] = v end
  end
  local step
  for i = 2, #distinct do
    local gap = distinct[i] - distinct[i - 1]
    if not step or gap < step then step = gap end
  end
  local min = distinct[1] or 0
  return function(v)
    if not step then return 1 end
    return math.floor((v - min) / step + 0.5) + 1
  end
end

-- Splits nodes into three trees: by subTreeID when the client provides it, otherwise by the two largest
-- horizontal gaps (the classic trees sit side by side in one trait tree).
local function groupNodes(nodes)
  local bySub, subs = {}, {}
  for _, n in ipairs(nodes) do
    if n.subTreeID then
      if not bySub[n.subTreeID] then bySub[n.subTreeID] = {}; subs[#subs + 1] = n.subTreeID end
      table.insert(bySub[n.subTreeID], n)
    end
  end
  if #subs >= 2 then
    local groups = {}
    for _, s in ipairs(subs) do bySub[s].sub = s; groups[#groups + 1] = bySub[s] end
    local function minX(g) local m = math.huge for _, n in ipairs(g) do if n.posX < m then m = n.posX end end return m end
    table.sort(groups, function(a, b) return minX(a) < minX(b) end)
    return groups
  end
  local sorted = {}
  for _, n in ipairs(nodes) do sorted[#sorted + 1] = n end
  table.sort(sorted, function(a, b) return a.posX < b.posX end)
  local gaps = {}
  for i = 2, #sorted do gaps[#gaps + 1] = { at = i, size = sorted[i].posX - sorted[i - 1].posX } end
  table.sort(gaps, function(a, b) return a.size > b.size end)
  local cuts = {}
  for i = 1, math.min(2, #gaps) do if gaps[i].size > 0 then cuts[#cuts + 1] = gaps[i].at end end
  table.sort(cuts)
  local groups, start = {}, 1
  for _, cut in ipairs(cuts) do
    local g = {}
    for i = start, cut - 1 do g[#g + 1] = sorted[i] end
    groups[#groups + 1] = g
    start = cut
  end
  local last = {}
  for i = start, #sorted do last[#last + 1] = sorted[i] end
  groups[#groups + 1] = last
  return groups
end

-- Tree names: the client's spec names only when they really name three different trees (Forever reports one spec
-- named like the class), otherwise the given fallback names (already translated). Pure, tested.
function Model.PickTreeNames(specNames, className, fallback)
  local distinct, seen = 0, {}
  for i = 1, 3 do
    local n = specNames and specNames[i] and specNames[i].name
    if n and n ~= className and not seen[n] then seen[n] = true; distinct = distinct + 1 end
  end
  if distinct == 3 then return specNames end
  local out = {}
  for i, n in ipairs(fallback or {}) do out[i] = { name = n, icon = specNames and specNames[i] and specNames[i].icon } end
  return out
end

-- namesBySub (optional): [subTreeID] = { name, icon } from the client, preferred over treeNames.
function Model.FromNodes(class, nodes, treeNames, namesBySub)
  local model = { class = class, source = "traits", trees = {} }
  local idOfNode = {}
  for _, group in ipairs(groupNodes(nodes)) do
    local xs, ys = {}, {}
    for _, n in ipairs(group) do xs[#xs + 1] = n.posX; ys[#ys + 1] = n.posY end
    local colOf, rowOf = Model.Grid(xs, 50), Model.Grid(ys, 50)
    local t = #model.trees + 1
    local names = (group.sub and namesBySub and namesBySub[group.sub]) or (treeNames and treeNames[t])
    local tree = { name = names and names.name or ("Tree " .. t), icon = names and names.icon, talents = {} }
    for _, n in ipairs(group) do
      local tal = { id = n.nodeID, nodeID = n.nodeID, entryID = n.entryID, tree = t, row = rowOf(n.posY), col = colOf(n.posX),
        maxRank = n.maxRanks or 1, name = n.name, icon = n.icon, spellID = n.spellID }
      tree.talents[#tree.talents + 1] = tal
      idOfNode[n.nodeID] = tal
    end
    sortTalents(tree)
    model.trees[t] = tree
  end
  for _, n in ipairs(nodes) do
    for _, target in ipairs(n.edges or {}) do
      if idOfNode[target] then idOfNode[target].prereq = n.nodeID end
    end
  end
  return model
end
