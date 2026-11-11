-- ClassPages: spellbook index. Class profiles name spells by their base (rank 1) spell ID; this index maps such an ID
-- to the highest rank the player knows, through the localized spell name, so presets work in every language and
-- after every new rank without hard-coded rank tables.
--
-- Public API
--   ns.Spellbook.Resolve(baseSpellID) -> known spellID (highest rank) or nil
--   ns.Spellbook.Items()              player spellbook items in book order (read live, no index)
--   ns.Spellbook.Scan()               re-read the player's spellbook (out of combat; called on SPELLS_CHANGED)
--   ns.Spellbook.BuildIndex(items)    pure: items = { {spellID, name, passive} } in book order -> index
--   ns.Spellbook.Professions()        { {name, icon, spellID, skill, maxSkill} } primary + secondary professions
--   ns.Spellbook.PetSpells()          { {spellID, name, subName, icon} } of the active pet
--   ns.Spellbook.index                byName[name] = spellID, known[spellID] = true, count
local ADDON, ns = ...

local Spellbook = { index = { byName = {}, known = {}, count = 0 } }
ns.Spellbook = Spellbook

local function bankEnum(kind)
  local e = Enum and Enum.SpellBookSpellBank
  if e then return kind == "pet" and e.Pet or e.Player end
  return kind == "pet" and "pet" or "spell"
end

-- Later entries of the same name win: the spellbook lists ranks in ascending order.
function Spellbook.BuildIndex(items)
  local index = { byName = {}, known = {}, count = 0 }
  for _, it in ipairs(items) do
    if it.spellID and it.name and not it.passive then
      index.byName[it.name] = it.spellID
      index.known[it.spellID] = true
      index.count = index.count + 1
    end
  end
  return index
end

-- Normalised spellbook item at (slot, bank) or nil.
local function readItem(slot, bank)
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
    if ok and type(info) == "table" then
      local spellID = info.spellID or info.actionID
      if ns.Secret.Any(spellID, info.name) then return nil end
      local isSpell = not Enum or not Enum.SpellBookItemType or info.itemType == nil or info.itemType == Enum.SpellBookItemType.Spell
        or info.itemType == Enum.SpellBookItemType.PetAction
      if not isSpell then return nil end
      return { spellID = spellID, name = info.name, subName = info.subName, icon = info.iconID, passive = info.isPassive and true or false, offSpec = info.isOffSpec }
    end
  end
  if GetSpellBookItemInfo then
    local ok, kind, spellID = pcall(GetSpellBookItemInfo, slot, bank)
    if ok and (kind == "SPELL" or kind == "PETACTION") and spellID and not ns.Secret.IsSecret(spellID) then
      local name, sub = GetSpellBookItemName(slot, bank)
      return { spellID = spellID, name = name, subName = sub, icon = ns.API.SpellIcon(spellID), passive = IsPassiveSpell and IsPassiveSpell(slot, bank) or false }
    end
  end
  return nil
end
Spellbook.readItem = readItem

-- Player spellbook items in book order.
function Spellbook.Items()
  local items, bank = {}, bankEnum("player")
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local okN, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    for line = 1, (okN and tonumber(n) or 0) do
      local ok, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
      if ok and type(info) == "table" and not info.isGuild then
        local offset, num = info.itemIndexOffset or 0, info.numSpellBookItems or 0
        for slot = offset + 1, offset + num do
          local it = readItem(slot, bank)
          if it and not it.offSpec then items[#items + 1] = it end
        end
      end
    end
  elseif GetNumSpellTabs then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, num = GetSpellTabInfo(tab)
      for slot = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local it = readItem(slot, bank)
        if it then items[#items + 1] = it end
      end
    end
  end
  return items
end

function Spellbook.Scan()
  if ns.Combat.InLockdown() then return false end
  Spellbook.index = Spellbook.BuildIndex(Spellbook.Items())
  Spellbook.scanned = true
  ns.Log("spellbook", Spellbook.index.count, "spells")
  return true
end

function Spellbook.Resolve(baseSpellID)
  if not baseSpellID then return nil end
  local name = ns.API.SpellName(baseSpellID)
  local id = name and Spellbook.index.byName[name]
  if id then return id end
  if Spellbook.index.known[baseSpellID] or ns.API.IsSpellKnown(baseSpellID) then return baseSpellID end
  return nil
end

function Spellbook.PetSpells()
  local list = {}
  local has = ns.API.First({ "C_SpellBook.HasPetSpells", "HasPetSpells" })
  if not has then return list end
  local ok, num = pcall(has)
  num = ok and tonumber(ns.Secret.Safe(num, 0)) or 0
  local bank = bankEnum("pet")
  for slot = 1, num do
    local it = readItem(slot, bank)
    if it and it.name then list[#list + 1] = it end
  end
  return list
end

-- Professions through GetProfessions (primary, secondary, fishing, cooking, first aid). The castable spell is the
-- first spellbook item of the profession line; the button opens the profession window like the spellbook does.
function Spellbook.Professions()
  local out = {}
  if not GetProfessions or not GetProfessionInfo then return out end
  local slots = { GetProfessions() }
  for i = 1, 6 do
    local idx = slots[i]
    if idx and not ns.Secret.IsSecret(idx) then
      local ok, name, icon, skill, maxSkill, numAbilities, offset = pcall(GetProfessionInfo, idx)
      if ok and name and not ns.Secret.Any(name, offset) then
        local it = (numAbilities or 0) > 0 and readItem((offset or 0) + 1, bankEnum("player")) or nil
        out[#out + 1] = { name = name, icon = icon, skill = skill, maxSkill = maxSkill, spellID = it and it.spellID }
      end
    end
  end
  return out
end

ns:RegisterModule("Spellbook", {
  Login = function() Spellbook.Scan() end,
  Init = function()
    local function rescan()
      if Spellbook.Scan() and ns.HUD and ns.HUD.RefreshContents then ns.HUD.RefreshContents() end
    end
    ns.Events:On("SPELLS_CHANGED", rescan, "Spellbook")
    ns.Events:On("PLAYER_REGEN_ENABLED", function() if not Spellbook.scanned then rescan() end end, "Spellbook")
  end,
  SelfTest = function()
    local n = Spellbook.index.count
    return { { name = "spellbook", ok = n > 0, warn = n == 0, detail = ("%d spells indexed"):format(n) } }
  end,
})
