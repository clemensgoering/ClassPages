-- Talent model and planner rules on a synthetic three-tree class (no game data needed).
local ns, eq = ...
local Model, Planner = ns.Talents.Model, ns.Talents.Planner

eq(Planner.PointsForLevel(60), 51, "points: level 60")
eq(Planner.PointsForLevel(10), 1, "points: level 10")
eq(Planner.PointsForLevel(5), 0, "points: below 10")

-- tree 1: A (1:1, 5 ranks), B (1:2, 5 ranks), C (2:1, 3 ranks, needs A), D (3:2, 1 rank)
local function tab(name)
  return { name = name, talents = {
    { name = "A", tier = 1, column = 1, maxRank = 5 },
    { name = "B", tier = 1, column = 2, maxRank = 5 },
    { name = "C", tier = 2, column = 1, maxRank = 3, prereqTier = 1, prereqColumn = 1 },
    { name = "D", tier = 3, column = 2, maxRank = 1 },
  } }
end
local model = Model.FromClassic("HUNTER", { tab("Beast Mastery"), tab("Marksmanship"), tab("Survival") })
local byID = Model.Index(model)
eq(#model.trees, 3, "model: three trees")
local A, B, C, D = 101, 102, 103, 104
eq(byID[C].prereq, A, "model: prereq resolved")
eq(byID[D].row, 3, "model: row")

local build = Planner.New(model)
eq((Planner.Add(build, model, byID, C, 60)), false, "rule: row 2 locked at 0 points")
for _ = 1, 5 do Planner.Add(build, model, byID, B, 60) end
eq(build.ranks[B], 5, "rule: 5 points in B")
eq((Planner.Add(build, model, byID, B, 60)), false, "rule: max rank")
local ok, why = Planner.Add(build, model, byID, C, 60)
eq(ok, false, "rule: C needs A maxed")
eq(why, "requires prerequisite", "rule: reason prerequisite")
for _ = 1, 5 do Planner.Add(build, model, byID, A, 60) end
eq((Planner.Add(build, model, byID, C, 60)), true, "rule: C allowed now")
eq((Planner.Remove(build, model, byID, A)), false, "rule: cannot remove prerequisite point")
eq((Planner.Remove(build, model, byID, C)), true, "rule: remove leaf point")
eq(Planner.Spent(build, model), 10, "spent total")
eq(Planner.Spent(build, model, 2), 0, "spent tree 2")

-- B points unlock row 2; removing one B point must fail while C has points that need 5 above
Planner.Add(build, model, byID, C, 60)
eq((Planner.Remove(build, model, byID, B)), true, "rule: A alone still unlocks row 2")
local low = Planner.New(model)
eq((Planner.Add(low, model, byID, A, 9)), false, "rule: no points below level 10")
eq((Planner.Add(low, model, byID, A, 10)), true, "rule: one point at level 10")
eq((Planner.Add(low, model, byID, A, 10)), false, "rule: level limits points")

-- export / import round trip, invalid input
local text = Planner.Export(build, model)
eq(text, "541--", "export: digits per tree")
local back = Planner.Import(text, model)
eq(back and back.ranks[A], 5, "import: A")
eq(back and back.ranks[C], 1, "import: C")
eq((Planner.Import("abc", model)), nil, "import: rejects letters")
eq((Planner.Import("0090", model)), nil, "import: rejects rank above max")
eq((Planner.Import("0010", model)), nil, "import: rejects locked row")
eq(#Planner.Diff(build, { [A] = 5 }), 2, "diff: B and C still to learn")

-- trait nodes: three trees side by side, positions in arbitrary units, edges as prerequisites
local nodes = {}
local function node(id, x, y, maxRanks, edges) nodes[#nodes + 1] = { nodeID = id, posX = x, posY = y, maxRanks = maxRanks, name = "N" .. id, edges = edges } end
for t = 0, 2 do
  local ox = t * 5000  -- trees further apart than talents inside a tree, like the client layout
  node(t * 10 + 1, ox + 0, 0, 5, { t * 10 + 3 })
  node(t * 10 + 2, ox + 600, 0, 5)
  node(t * 10 + 3, ox + 0, 600, 3)
  node(t * 10 + 4, ox + 1800, 1800, 1)
end
local tm = Model.FromNodes("HUNTER", nodes, { { name = "BM" }, { name = "MM" }, { name = "SV" } })
local tby = Model.Index(tm)
eq(#tm.trees, 3, "traits: three trees by gaps")
eq(tm.trees[2].name, "MM", "traits: tree names in order")
eq(tby[13].prereq, 11, "traits: edge -> prerequisite")
eq(tby[14].row, 4, "traits: row from y with empty row")
eq(tby[14].col, 4, "traits: col from x with empty cols")
eq(tby[22].col, 2, "traits: second tree col")

local sub = { { nodeID = 1, posX = 0, posY = 0, subTreeID = 9 }, { nodeID = 2, posX = 10, posY = 0, subTreeID = 8 }, { nodeID = 3, posX = 5000, posY = 0, subTreeID = 7 } }
local sm = Model.FromNodes("X", sub)
eq(#sm.trees, 3, "traits: grouping by subTreeID")
eq(sm.trees[1].talents[1].id, 1, "traits: subtrees sorted by x")

-- tree names: Forever reports one spec named like the class -> classic names
local spec = { { name = "Magier", icon = 1 } }
local picked = Model.PickTreeNames(spec, "Magier", { "Arkan", "Feuer", "Frost" })
eq(picked[1].name, "Arkan", "names: class-named spec replaced")
eq(picked[1].icon, 1, "names: icon kept")
eq(picked[3].name, "Frost", "names: third")
local real = { { name = "A" }, { name = "B" }, { name = "C" } }
eq(Model.PickTreeNames(real, "Magier", { "X" })[2].name, "B", "names: real spec names win")
eq(#Model.PickTreeNames({ { name = "A" }, { name = "A" }, { name = "A" } }, "M", {}), 0, "names: duplicates rejected")
local named = Model.FromNodes("X", sub, nil, { [9] = { name = "Sub9" } })
eq(named.trees[1].name, "Sub9", "names: subtree name preferred")

local grid = Model.Grid({ 100, 100.2, 700, 1300 }, 1)
eq(grid(100.2), 1, "grid: float noise snaps")
eq(grid(1300), 3, "grid: index")

-- level plan: the order of planned points, default order for builds without one, next point
local lp = Planner.New(model)
Planner.Add(lp, model, byID, B, 60); Planner.Add(lp, model, byID, A, 60); Planner.Add(lp, model, byID, B, 60)
eq(table.concat(lp.order, ","), B .. "," .. A .. "," .. B, "order: as planned")
local nid, nlevel = Planner.Next(lp, model, byID, {})
eq(nid, B, "next: first planned point")
eq(nlevel, 10, "next: first point comes at level 10")
nid, nlevel = Planner.Next(lp, model, byID, { [B] = 1 })
eq(nid, A, "next: second planned point")
eq(nlevel, 11, "next: level follows spent points")
eq((Planner.Next(lp, model, byID, { [B] = 2, [A] = 1 })), nil, "next: plan complete")
Planner.Remove(lp, model, byID, B)
eq(table.concat(lp.order, ","), B .. "," .. A, "order: remove drops the latest point of that talent")
-- imported build has no order: main tree first, rows top down, prerequisites respected
local imp = Planner.Import("541--", model)
local ord = Planner.Order(imp, model, byID)
eq(#ord, 10, "order: default covers every point")
eq(ord[1], A, "order: default starts top left")
local firstC
for i, id in ipairs(ord) do if id == C and not firstC then firstC = i end end
eq(firstC, 10, "order: talent with prerequisite comes after it")
imp.order = { A, A }
eq(#Planner.Order(imp, model, byID), 10, "order: stale stored order is replaced")
