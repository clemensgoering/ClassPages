-- ClassPages: SavedVariables lifecycle and profiles. Guarantees for users who update the addon (docs/03-ARCHITEKTUR.md §4):
--   1. Data is never reset. Defaults only fill missing keys; unknown keys (from newer or older versions) stay untouched.
--   2. Structure changes are schema migrations: numbered, additive, run once, each covered by tools/tests/db_test.lua.
--   3. Before any migration the whole database is copied to ClassPagesBackupDB (one generation), restorable with
--      /cp restore confirm. Destructive user commands (profile reset/delete) back up first as well.
--   4. Every table read from disk is sanitised by its owner (HUD bars: ns.HUD.Model.Sanitize) so a damaged or
--      hand-edited file degrades to defaults for that entry instead of breaking the session.
--
-- Data layout
--   ClassPagesDB (account)
--     schema, settings, debug, probe
--     profiles[name] = { hud = { bars = { [id] = bar }, nextID, seeded }, window = { point } }
--     profileKeys[charKey] = profile name   (default: the character's own profile)
--     classes[CLASS] = { tree = talent model cache, builds = { [name] = build }, activeBuild }
--     families[familyKey] = { diet = {...}, abilities = {...}, seen }   observed pet family facts
--   ClassPagesCharDB (character)
--     pets = { stable = {...}, training = {...}, current = {...} }, firstRun
--
-- Public API
--   ns.db / ns.cdb / ns.profile         account DB / character DB / active profile
--   ns.DB.Prepare(db), ns.DB.Backup(reason), ns.DB.RestoreBackup(), ns.DB.Stats()
--   ns.DB.PrepareChar(cdb) -> cdb             fill character defaults (ClassPagesCharDB)
--   ns.DB.HasBackup() -> bool                 ClassPagesBackupDB holds data
--   ns.DB.RestoreBackup(slot) -> ok, err      slot nil = latest backup, "migration" = last pre-migration backup
--   Backup slots: ClassPagesBackupDB (latest) and ClassPagesBackupDB.migration (last migration, kept by later backups)
--   ns.Profiles.Current() -> name, List(), Use(name), Copy(from, to), Delete(name), Reset(name)
local ADDON, ns = ...
local L = ns.L

ns.INTERFACE = 16001
local SCHEMA = 1

local DEFAULTS = {
  schema = SCHEMA,
  settings = { debug = false, language = "auto", hudEnabled = true },
  profiles = {},
  profileKeys = {},
  classes = {},
  families = {},
  probe = {},
  debug = { errors = {}, log = {} },
}

local PROFILE_DEFAULTS = {
  hud = { bars = {}, nextID = 1, seeded = false, locked = true, hideMain = false },
  window = {},
}

local CHAR_DEFAULTS = {
  pets = { stable = {}, training = {}, current = {} },
}

-- Fills missing keys only. Existing values, including unknown keys, are never changed.
local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      if next(v) ~= nil then applyDefaults(dst[k], v) end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Migrations run in order from the stored schema to SCHEMA: [toVersion] = function(db) end.
-- Rules: additive only (rename/move, never delete user data), idempotent, each one tested.
local MIGRATIONS = {}

ns.DB = { MIGRATIONS = MIGRATIONS, SCHEMA = SCHEMA, applyDefaults = applyDefaults }

-- Two slots: the latest backup (ClassPagesBackupDB itself) and the last migration backup (.migration), which later
-- backups do not overwrite. Debug logs and the talent tree cache are left out: they are rebuilt, not user data.
function ns.DB.Backup(reason, db)
  db = db or ns.db
  local data = ns.Util.DeepCopy(db)
  if type(data) == "table" then
    data.debug = nil
    for _, class in pairs(type(data.classes) == "table" and data.classes or {}) do
      if type(class) == "table" then class.tree = nil end
    end
  end
  local kept = type(ClassPagesBackupDB) == "table" and ClassPagesBackupDB.migration or nil
  local snapshot = { when = time(), reason = reason, schema = db and db.schema, version = ns.version, data = data }
  if type(reason) == "string" and reason:find("^migration") then
    kept = { when = snapshot.when, reason = reason, schema = snapshot.schema, version = ns.version, data = data }
  end
  snapshot.migration = kept
  ClassPagesBackupDB = snapshot
  return ClassPagesBackupDB
end

function ns.DB.HasBackup()
  return type(ClassPagesBackupDB) == "table" and type(ClassPagesBackupDB.data) == "table"
end

-- Replaces the live database with the backup. Takes effect fully after /reload (modules keep references).
function ns.DB.RestoreBackup(slot)
  if not ns.DB.HasBackup() then return false, L["no backup available"] end
  local source = ClassPagesBackupDB
  if slot == "migration" then
    source = ClassPagesBackupDB.migration
    if type(source) ~= "table" or type(source.data) ~= "table" then return false, L["no backup available"] end
  end
  local restored = ns.Util.DeepCopy(source.data)
  for k in pairs(ClassPagesDB) do ClassPagesDB[k] = nil end
  for k, v in pairs(restored) do ClassPagesDB[k] = v end
  ns.db = ClassPagesDB
  return true
end

local function migrate(db, schema)
  schema = schema or SCHEMA
  local from = tonumber(db.schema) or 1
  if from >= schema then return false end
  ns.DB.Backup(("migration %d -> %d"):format(from, schema), db)
  for v = from + 1, schema do
    local fn = MIGRATIONS[v]
    if fn then
      local ok, err = pcall(fn, db)
      if not ok then ns.Health.Record("migration " .. v, err) end
    end
    db.schema = v
  end
  ns.Log("migrated schema", from, "->", schema)
  return true
end

-- Defaults + migrations on an arbitrary table (used by tests and ADDON_LOADED). The stored schema is read BEFORE the
-- defaults: a brand-new database starts at SCHEMA, an existing one without a schema field counts as schema 1.
-- A database from a NEWER addon version (schema > SCHEMA) is left as it is; unknown fields are kept.
function ns.DB.Prepare(db, schema)
  local isNew = next(db) == nil
  local from = tonumber(db.schema) or (isNew and (schema or SCHEMA) or 1)
  applyDefaults(db, DEFAULTS)
  db.schema = from
  return migrate(db, schema)
end

function ns.DB.PrepareChar(cdb)
  applyDefaults(cdb, CHAR_DEFAULTS)
  return cdb
end

function ns.DB.Stats()
  local bars = ns.profile and ns.Util.Count(ns.profile.hud.bars) or 0
  return {
    schema = ns.db.schema, profiles = ns.Util.Count(ns.db.profiles), profile = ns.Profiles.Current(), bars = bars,
    classes = ns.Util.Count(ns.db.classes), errors = #(ns.db.debug.errors or {}),
    backup = ns.DB.HasBackup() and (tostring(ClassPagesBackupDB.reason) .. " @ " .. tostring(ClassPagesBackupDB.when)) or "none",
  }
end

-- Profiles -------------------------------------------------------------------------------------
local Profiles = {}
ns.Profiles = Profiles

local function charKey() return ns.Util.CharKey() or "default" end

function Profiles.Current()
  return ns.db.profileKeys[charKey()] or charKey()
end

local function activate(name)
  ns.db.profiles[name] = ns.db.profiles[name] or {}
  applyDefaults(ns.db.profiles[name], PROFILE_DEFAULTS)
  ns.profile = ns.db.profiles[name]
  return ns.profile
end
Profiles.activate = activate

function Profiles.List()
  local names = {}
  for name in pairs(ns.db.profiles) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Switching takes effect immediately for data; the HUD rebuilds out of combat.
function Profiles.Use(name)
  if type(name) ~= "string" or name == "" then return false end
  ns.db.profileKeys[charKey()] = name
  activate(name)
  if ns.HUD and ns.HUD.Rebuild then ns.HUD.Rebuild() end
  return true
end

function Profiles.Copy(from, to)
  local src = ns.db.profiles[from]
  if not src or not to or to == "" then return false end
  if ns.db.profiles[to] then ns.DB.Backup("profile copy over " .. to) end
  ns.db.profiles[to] = ns.Util.DeepCopy(src)
  return true
end

function Profiles.Delete(name)
  if not ns.db.profiles[name] or name == Profiles.Current() then return false end
  ns.DB.Backup("profile delete " .. name)
  ns.db.profiles[name] = nil
  for k, v in pairs(ns.db.profileKeys) do if v == name then ns.db.profileKeys[k] = nil end end
  return true
end

function Profiles.Reset(name)
  name = name or Profiles.Current()
  ns.DB.Backup("profile reset " .. name)
  ns.db.profiles[name] = {}
  activate(name)
  if ns.HUD and ns.HUD.Rebuild then ns.HUD.Rebuild() end
  return true
end

-- Lifecycle ------------------------------------------------------------------------------------
ns.Events:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ClassPagesDB = ClassPagesDB or {}
  ClassPagesCharDB = ClassPagesCharDB or {}
  ns.db = ClassPagesDB
  ns.cdb = ns.DB.PrepareChar(ClassPagesCharDB)
  ns.DB.Prepare(ns.db)
  ns.Locale.Set(ns.db.settings.language)
  -- the character key may be incomplete before PLAYER_LOGIN; it is re-resolved there
  activate(Profiles.Current())
  ns:RunHook("Init")
  ns.Log("loaded", ns.version, "schema", ns.db.schema)
end, "DB")

ns.Events:On("PLAYER_LOGIN", function()
  activate(Profiles.Current())
  local _, build, _, interface = GetBuildInfo()
  if not ns.Secret.Any(build, interface) then
    if interface ~= ns.INTERFACE then
      ns.Print((L["Warning: client interface %s, addon built for %s. Please run /cp debug and pass on the report."]):format(tostring(interface), tostring(ns.INTERFACE)))
    elseif ns.db.debug.lastBuild and ns.db.debug.lastBuild ~= build then
      ns.Print((L["New client build %s detected. /cp debug checks that everything still works."]):format(tostring(build)))
    end
    ns.db.debug.lastBuild = build
  end
  ns:RunHook("Login")
end, "DB")

ns.Slash.Register("backup", function()
  ns.DB.Backup("manual")
  ns.Print(L["Data backed up. Restore with /cp restore confirm."])
end, "copy all ClassPages data into the backup slot")

ns.Slash.Register("restore", function(arg)
  if arg == "migration" then
    local ok, err = ns.DB.RestoreBackup("migration")
    return ns.Print(ok and L["Backup restored. Please /reload."] or (L["Restore failed: %s"]):format(tostring(err)))
  end
  if arg ~= "confirm" then
    local s = ns.DB.HasBackup() and ((L["%s, schema %s"]):format(tostring(ClassPagesBackupDB.reason), tostring(ClassPagesBackupDB.schema))) or L["no backup"]
    return ns.Print((L["Backup: %s. To restore: /cp restore confirm (then /reload)."]):format(s))
  end
  local ok, err = ns.DB.RestoreBackup()
  ns.Print(ok and L["Backup restored. Please /reload."] or (L["Restore failed: %s"]):format(tostring(err)))
end, "restore the backup slot (restore confirm | restore migration)")

ns.Slash.Register("profile", function(arg)
  local sub, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  sub = sub:lower()
  if sub == "use" and rest ~= "" then
    Profiles.Use(rest); return ns.Print((L["Profile: %s"]):format(rest))
  elseif sub == "copy" and rest ~= "" then
    local ok = Profiles.Copy(rest, Profiles.Current())
    if ok then Profiles.Use(Profiles.Current()) end
    return ns.Print(ok and L["Profile copied."] or L["Profile not found."])
  elseif sub == "delete" and rest ~= "" then
    return ns.Print(Profiles.Delete(rest) and L["Profile deleted."] or L["Profile not found or active."])
  elseif sub == "reset" then
    Profiles.Reset(); return ns.Print(L["Profile reset (backup made)."])
  end
  ns.Print((L["Profile: %s"]):format(Profiles.Current()) .. "  [" .. table.concat(Profiles.List(), ", ") .. "]")
  ns.Print(L["usage: /cp profile use|copy|delete <name> | reset"])
end, "show, switch, copy or reset HUD profiles")
