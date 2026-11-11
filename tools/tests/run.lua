-- ClassPages headless test runner (Lua 5.1 / LuaJIT). Usage: luajit tools/tests/run.lua <repo root>
-- Loads the pure-logic addon files with a minimal WoW stub environment, fires ADDON_LOADED, then runs the inline
-- smoke tests and every tools/tests/*_test.lua (called as chunk(ns, eq, T)). The whole addon including UI and the
-- secure HUD is exercised by tools/tests/sim.lua.
local root = arg[1] or "."
local ADDON, ns = "ClassPages", {}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) io.write(msg, "\n") end }
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Timer = { After = function(_, fn) fn() end }
GetTime = os.clock
time, date = os.time, os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
-- In the game `issecretvalue` exists at load time; Core/Secret.lua captures it as an upvalue.
issecretvalue = function(v) return v == "SECRET" end
UnitFullName = function() return "Testhunter", "Forever" end
UnitClassBase = function() return "HUNTER", 3 end
UnitLevel = function() return 60 end
GetNormalizedRealmName = function() return "Forever" end
InCombatLockdown = function() return false end
GetBuildInfo = function() return "1.60.1", "70862", "Nov 6 2026", 16001 end
GetLocale = function() return "enUS" end
-- spell names for Spellbook.Resolve (rank 1 ids -> names)
local SPELL_NAMES = { [75] = "Auto Shot", [3044] = "Arcane Shot", [14281] = "Arcane Shot", [19306] = "Counterattack", [1130] = "Hunter's Mark", [2973] = "Raptor Strike" }
C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] end, GetSpellTexture = function() return 1 end, GetSpellCooldown = function() return nil end }
C_SpellBook = { IsSpellKnown = function() return false end }
CreateFrame = function()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.onEvent = fn end
  return f
end

local function loadAddonFile(rel)
  local chunk, err = loadfile(root .. "/ClassPages/" .. rel)
  assert(chunk, err)
  chunk(ADDON, ns)
end

for _, rel in ipairs({
  "Locales/enUS.lua", "Locales/deDE.lua", "Core/Init.lua", "Core/Util.lua", "Core/Secret.lua", "Core/Events.lua", "Core/API.lua",
  "Core/DB.lua", "Core/Combat.lua", "Core/Spellbook.lua",
  "Classes/Registry.lua", "Classes/Guide.lua", "Classes/Trainer.lua", "Classes/Hunter.lua", "Classes/HunterPets.lua",
  "HUD/Kinds.lua", "HUD/Model.lua", "HUD/Content.lua", "HUD/Highlight.lua",
  "Talents/Model.lua", "Talents/Planner.lua",
}) do loadAddonFile(rel) end

ClassPagesDB, ClassPagesCharDB, ClassPagesBackupDB = nil, nil, nil
ns.Events.frame.onEvent(nil, "ADDON_LOADED", ADDON)
assert(ns.db and ns.db.settings and ns.profile, "DB not initialised")

local T = { passed = 0, failed = 0 }
local function eq(a, b, label)
  if a == b then T.passed = T.passed + 1
  else T.failed = T.failed + 1; print(string.format("FAIL %s: expected %s, got %s", label or "", tostring(b), tostring(a))) end
end
T.root = root

-- Smoke tests for the bootstrap files
eq(ns.Secret.IsSecret("SECRET"), true, "secret detected")
eq(ns.Secret.Any(1, "SECRET"), true, "any secret")
eq(ns.Secret.Safe("SECRET", "x"), "x", "safe fallback")
eq(ns.Util.FormatRemaining(65), "1:05", "remaining minutes")
eq(ns.Util.FormatRemaining(4.2), "5", "remaining seconds")
eq(ns.Util.FormatRemaining(1.24), "1.2", "remaining tenths")
eq(ns.Util.CharKey(), "Testhunter - Forever", "char key")
local called, secretCalls = 0, 0
ns.Events:On("TEST_EVENT", function() called = called + 1 end)
ns.Events:On("TEST_EVENT", function() secretCalls = secretCalls + 1 end, "Test", { allowSecret = true })
ns.Events.frame.onEvent(nil, "TEST_EVENT", 1, 2)
ns.Events.frame.onEvent(nil, "TEST_EVENT", "SECRET")
eq(called, 1, "plain handler skipped on secret")
eq(secretCalls, 2, "allowSecret handler runs on secret")
local errors = 0
ns.Events:On("BROKEN_EVENT", function() errors = errors + 1; error("boom") end, "Test")
for _ = 1, 7 do ns.Events.frame.onEvent(nil, "BROKEN_EVENT") end
eq(errors, 5, "broken handler detached after 5 errors")
local laterRuns, laterValue = 0, nil
local realTimer = C_Timer
local queued = {}
C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
ns.Events.Later("t", 0.1, function() laterRuns = laterRuns + 1; laterValue = "a" end)
ns.Events.Later("t", 0.1, function() laterRuns = laterRuns + 1; laterValue = "b" end)
eq(#queued, 1, "later: one timer per burst")
for _, fn in ipairs(queued) do fn() end
eq(laterRuns, 1, "later: runs once")
eq(laterValue, "b", "later: newest call wins")
C_Timer = realTimer

local files = {}
local onWindows = package.config:sub(1, 1) == "\\"
local listCmd = onWindows and ('dir /b "' .. root:gsub("/", "\\") .. '\\tools\\tests"') or ('ls "' .. root .. '/tools/tests"')
local p = io.popen(listCmd)
if p then
  for file in p:lines() do if file:match("_test%.lua$") then files[#files + 1] = file end end
  p:close()
end
table.sort(files)
for _, file in ipairs(files) do
  local chunk, err = loadfile(root .. "/tools/tests/" .. file)
  if not chunk then T.failed = T.failed + 1; print("FAIL load " .. file .. ": " .. tostring(err))
  else
    local ok, runErr = pcall(chunk, ns, eq, T)
    if not ok then T.failed = T.failed + 1; print("FAIL " .. file .. ": " .. tostring(runErr)) end
  end
end

print(string.format("tests: %d passed, %d failed (%d test files)", T.passed, T.failed, #files))
os.exit(T.failed == 0 and 0 or 1)
