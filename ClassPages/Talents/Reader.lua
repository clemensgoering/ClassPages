-- ClassPages: reads the player's talent trees from the client. Two backends, chosen by capability:
--   traits  : C_ClassTalents / C_Traits (Forever exposes the trait API for its three classic trees)
--   classic : GetNumTalentTabs / GetTalentInfo / GetTalentPrereqs
-- Both return raw data for ns.Talents.Model plus the live ranks. Nothing here decides rules.
--
-- Public API (ns.Talents.Reader)
--   Read(class, classID) -> model, current, err      current = { [talentID] = rank }
--   ReadTraits(class, classID) -> model, current, err   backend: C_ClassTalents / C_Traits
--   ReadClassic(class) -> model, current, err           backend: GetTalentInfo
--   Dump() -> lines                                  raw facts for /cp talents dump and the debug report
local ADDON, ns = ...

ns.Talents = ns.Talents or {}
local Reader = {}
ns.Talents.Reader = Reader

local Secret = ns.Secret

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h
end

local function treeNames(classID, class)
  local names = {}
  for i = 1, 3 do
    local _, name, _, icon = safe(GetSpecializationInfoForClassID, classID, i)
    if name and not Secret.IsSecret(name) then names[i] = { name = name, icon = icon } end
  end
  if #names < 3 and GetTalentTabInfo then
    for i = 1, 3 do
      local a, b, _, d = safe(GetTalentTabInfo, i)
      if type(a) == "number" then names[i] = names[i] or { name = b, icon = d }
      elseif type(a) == "string" then names[i] = names[i] or { name = a, icon = b } end
    end
  end
  local className = UnitClass and UnitClass("player")
  local fallback = {}
  for i, key in ipairs(ns.Classes.TREES[class] or {}) do fallback[i] = ns.L[key] end
  return ns.Talents.Model.PickTreeNames(names, not Secret.IsSecret(className) and className or nil, fallback)
end

local function subTreeNames(configID, nodes)
  local out = {}
  if not (C_Traits and C_Traits.GetSubTreeInfo) then return out end
  for _, n in ipairs(nodes) do
    if n.subTreeID and not out[n.subTreeID] then
      local info = safe(C_Traits.GetSubTreeInfo, configID, n.subTreeID)
      if type(info) == "table" and info.name and not Secret.IsSecret(info.name) then out[n.subTreeID] = { name = info.name, icon = info.iconElementID } end
    end
  end
  return out
end

local function viewConfigID(classID)
  local consts = Constants and Constants.TraitConsts
  if not (consts and consts.VIEW_TRAIT_CONFIG_ID and C_ClassTalents and C_ClassTalents.InitializeViewLoadout) then return nil end
  local specID = safe(GetSpecializationInfoForClassID, classID, 1)
  if not specID then return nil end
  safe(C_ClassTalents.InitializeViewLoadout, specID, 60)
  safe(C_ClassTalents.ViewLoadout, {})
  return consts.VIEW_TRAIT_CONFIG_ID
end

function Reader.ReadTraits(class, classID)
  if not ns.Features.Available("talentsTraits") then return nil, nil, "trait API missing" end
  local configID = safe(C_ClassTalents.GetActiveConfigID)
  local viewOnly = false
  if not configID or Secret.IsSecret(configID) then configID, viewOnly = viewConfigID(classID), true end
  if not configID then return nil, nil, "no trait config" end
  local info = safe(C_Traits.GetConfigInfo, configID)
  if type(info) ~= "table" or type(info.treeIDs) ~= "table" or #info.treeIDs == 0 then return nil, nil, "no trait trees" end

  local nodes, current = {}, {}
  local multi = #info.treeIDs > 1
  for _, treeID in ipairs(info.treeIDs) do
    for _, nodeID in ipairs(safe(C_Traits.GetTreeNodes, treeID) or {}) do
      local n = safe(C_Traits.GetNodeInfo, configID, nodeID)
      if type(n) == "table" and n.ID ~= 0 and n.isVisible ~= false and (n.maxRanks or 0) > 0 and n.entryIDs and n.entryIDs[1]
        and not Secret.Any(n.posX, n.posY, n.maxRanks) then
        local entryID = n.entryIDs[1]
        local entry = safe(C_Traits.GetEntryInfo, configID, entryID)
        local def = entry and entry.definitionID and safe(C_Traits.GetDefinitionInfo, entry.definitionID)
        local spellID = def and (def.spellID or def.overriddenSpellID)
        local edges = {}
        for _, e in ipairs(n.visibleEdges or {}) do if e.targetNode then edges[#edges + 1] = e.targetNode end end
        nodes[#nodes + 1] = {
          nodeID = nodeID, entryID = entryID, posX = n.posX, posY = n.posY, maxRanks = n.maxRanks, edges = edges,
          subTreeID = n.subTreeID or (multi and treeID or nil), spellID = spellID,
          name = def and def.overrideName or (spellID and ns.API.SpellName(spellID)) or ("#" .. nodeID),
          icon = def and def.overrideIcon or (spellID and ns.API.SpellIcon(spellID)),
        }
        local rank = n.ranksPurchased or n.currentRank or 0
        if not viewOnly and not Secret.IsSecret(rank) and rank > 0 then current[nodeID] = rank end
      end
    end
  end
  if #nodes == 0 then return nil, nil, "no talent nodes" end
  local model = ns.Talents.Model.FromNodes(class, nodes, treeNames(classID, class), subTreeNames(configID, nodes))
  model.raw = { treeIDs = #info.treeIDs, nodes = #nodes, subTrees = ns.Util.Count(subTreeNames(configID, nodes)) }
  return model, current
end

function Reader.ReadClassic(class)
  if not ns.Features.Available("talentsClassic") then return nil, nil, "classic talent API missing" end
  local numTabs = safe(GetNumTalentTabs) or 0
  local tabs, current = {}, {}
  for t = 1, numTabs do
    local a, b, _, d = safe(GetTalentTabInfo, t)
    local tab = { talents = {} }
    if type(a) == "number" then tab.name, tab.icon = b, d else tab.name, tab.icon = a, b end
    local num = safe(GetNumTalents, t) or 0
    for i = 1, num do
      local name, icon, tier, column, rank, maxRank = safe(GetTalentInfo, t, i)
      if name and tier and column then
        local pt, pc = safe(GetTalentPrereqs, t, i)
        tab.talents[#tab.talents + 1] = { name = name, icon = icon, tier = tier, column = column, maxRank = maxRank, prereqTier = pt, prereqColumn = pc }
        if rank and rank > 0 then current[t * 100 + #tab.talents] = rank end
      end
    end
    tabs[t] = tab
  end
  if #tabs == 0 then return nil, nil, "no talent tabs" end
  return ns.Talents.Model.FromClassic(class, tabs), current
end

function Reader.Read(class, classID)
  local model, current, err = Reader.ReadTraits(class, classID)
  if model then return model, current end
  local model2, current2, err2 = Reader.ReadClassic(class)
  if model2 then return model2, current2 end
  return nil, nil, tostring(err) .. "; " .. tostring(err2)
end

function Reader.Dump()
  local lines = {}
  local function add(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  for _, f in ipairs({ "talentsTraits", "talentsClassic" }) do
    local ok, why = ns.Features.Available(f)
    add(f, ok and "ok" or why)
  end
  add("activeConfigID", tostring(safe(C_ClassTalents and C_ClassTalents.GetActiveConfigID)))
  add("numTalentTabs", tostring(safe(GetNumTalentTabs)))
  local class, classID = ns.API.PlayerClass()
  local model, current, err = Reader.Read(class, classID)
  if not model then add("read failed:", tostring(err)); return lines end
  add("source", model.source)
  for t, tree in ipairs(model.trees) do
    local maxRow, maxCol = 0, 0
    for _, tal in ipairs(tree.talents) do
      if tal.row > maxRow then maxRow = tal.row end
      if tal.col > maxCol then maxCol = tal.col end
    end
    add(("tree %d %s: %d talents, %d rows, %d cols, first: %s"):format(t, tostring(tree.name), #tree.talents, maxRow, maxCol, tostring(tree.talents[1] and tree.talents[1].name)))
  end
  if model.raw then add(("traits raw: %d trees, %d nodes, %d named subtrees"):format(model.raw.treeIDs, model.raw.nodes, model.raw.subTrees)) end
  add("ranked talents", tostring(ns.Util.Count(current)))
  return lines
end
