-- Saved data: defaults never overwrite, unknown keys survive, migrations back up first, profiles never lose data.
local ns, eq = ...
local DB = ns.DB

-- new database
local fresh = {}
DB.Prepare(fresh)
eq(fresh.schema, DB.SCHEMA, "db: new database at current schema")
eq(type(fresh.profiles), "table", "db: profiles table")

-- existing database: values and unknown keys are kept
local old = { schema = DB.SCHEMA, settings = { debug = true, futureOption = 42 }, somethingNew = { a = 1 } }
DB.Prepare(old)
eq(old.settings.debug, true, "db: existing value kept")
eq(old.settings.futureOption, 42, "db: unknown setting kept")
eq(old.somethingNew.a, 1, "db: unknown top-level key kept")
eq(old.settings.hudEnabled, true, "db: missing default filled")

-- a database from a newer addon version is left alone
local newer = { schema = DB.SCHEMA + 5, settings = {} }
DB.Prepare(newer)
eq(newer.schema, DB.SCHEMA + 5, "db: newer schema untouched")

-- migration framework: a test migration runs once, after a backup, and is idempotent
local saveBackup = ClassPagesBackupDB
DB.MIGRATIONS[DB.SCHEMA + 1] = function(db)
  for _, p in pairs(db.profiles or {}) do
    if p.hud and p.hud.bars then for _, bar in pairs(p.hud.bars) do bar.migrated = (bar.migrated or 0) + 1 end end
  end
end
local legacy = { schema = DB.SCHEMA, profiles = { P = { hud = { bars = { [1] = { id = 1, cols = 4 } } } } } }
eq(DB.Prepare(legacy, DB.SCHEMA + 1), true, "migration: ran")
eq(legacy.schema, DB.SCHEMA + 1, "migration: schema advanced")
eq(legacy.profiles.P.hud.bars[1].migrated, 1, "migration: applied")
eq(legacy.profiles.P.hud.bars[1].cols, 4, "migration: data kept")
eq(ClassPagesBackupDB and ClassPagesBackupDB.data.profiles.P.hud.bars[1].migrated, nil, "migration: backup taken before")
eq(DB.Prepare(legacy, DB.SCHEMA + 1), false, "migration: runs only once")
DB.MIGRATIONS[DB.SCHEMA + 1] = nil
ClassPagesBackupDB = saveBackup

-- profiles
local P = ns.Profiles
local me = P.Current()
eq(me, "Testhunter - Forever", "profiles: default per character")
ns.profile.hud.bars[1] = ns.HUD.Model.New({ id = 1, name = "Mine" })
eq(P.Copy(me, "Shared"), true, "profiles: copy")
eq(ns.db.profiles.Shared.hud.bars[1].name, "Mine", "profiles: copied content")
ns.db.profiles.Shared.hud.bars[1].name = "Changed"
eq(ns.profile.hud.bars[1].name, "Mine", "profiles: copy is deep")
eq(P.Delete(me), false, "profiles: active profile not deletable")
P.Use("Shared")
eq(ns.profile.hud.bars[1].name, "Changed", "profiles: switched")
eq(P.Delete(me), true, "profiles: delete other")
eq(ClassPagesBackupDB.data.profiles[me] ~= nil, true, "profiles: backup before delete")
P.Reset("Shared")
eq(next(ns.profile.hud.bars), nil, "profiles: reset empties")
eq(ClassPagesBackupDB.data.profiles.Shared.hud.bars[1].name, "Changed", "profiles: backup before reset")
P.Use(me)
eq(DB.RestoreBackup(), true, "restore: works")
eq(ns.db.profiles.Shared.hud.bars[1].name, "Changed", "restore: data back")

-- backup slots: the migration backup survives later backups; caches are not copied
ns.db.debug = { errors = { "x" }, log = {} }
DB.Backup("migration 1 -> 2")
ns.db.profiles.Shared.hud.bars[1].name = "Later"
DB.Backup("manual")
eq(ClassPagesBackupDB.reason, "manual", "backup: latest slot")
eq(ClassPagesBackupDB.migration and ClassPagesBackupDB.migration.reason, "migration 1 -> 2", "backup: migration slot kept")
eq(ClassPagesBackupDB.data.debug, nil, "backup: debug log not copied")
eq(ns.db.debug.errors[1], "x", "backup: live debug log untouched")
eq(DB.RestoreBackup("migration"), true, "restore: migration slot")
eq(ns.db.profiles.Shared.hud.bars[1].name, "Changed", "restore: migration data back")

-- character DB
local cdb = DB.PrepareChar({ pets = { stable = { pets = { { name = "Fang" } } } } })
eq(cdb.pets.stable.pets[1].name, "Fang", "char db: stable kept")
eq(type(cdb.pets.training), "table", "char db: training default")
