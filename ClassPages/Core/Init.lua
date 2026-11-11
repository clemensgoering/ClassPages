-- ClassPages: namespace bootstrap. Loaded first after the locales; every other file starts with `local ADDON, ns = ...`.
--
-- Module contract (docs/03-ARCHITEKTUR.md)
--   ns:RegisterModule(name, module)  module = {
--     Init     = function(self) end,  -- once after ADDON_LOADED, SavedVariables ready (ns.db, ns.cdb, ns.profile)
--     Login    = function(self) end,  -- once at PLAYER_LOGIN (spellbook, class and talents are known) (optional)
--     SelfTest = function(self) -> { {name, ok, warn?, detail?} },  -- rows for /cp debug (optional)
--   }
--   Modules talk to each other only through ns.<Module> functions and check existence first (`if ns.Talents then`).
--
-- Public API of this file
--   ns.name, ns.version                addon name and version ("dev" in an unpackaged checkout)
--   ns.Print(...), ns.Log(...)         chat line / debug ring buffer (printed with /cp debug on)
--   ns:RegisterModule(name, module), ns:EachModule(fn)
--   ns:RunHook("Init"|"Login")           run that hook of every module, each in isolation (errors recorded)
--   ns.Slash.Register(cmd, fn, help)   /cp <cmd> <rest> -> fn(rest)
local ADDON, ns = ...

ns.name = ADDON
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
if type(ns.version) ~= "string" or ns.version:find("@", 1, true) or ns.version == "" then ns.version = "dev" end
ns.modules = {}
local L = ns.L

-- Single global: slash commands and the optional public API for other addons.
ClassPages = ClassPages or {}
ClassPages.ns = ns

local PREFIX = "|cffaad372ClassPages|r: "

function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

-- Debug log: ring buffer (last 200 lines) in ClassPagesDB.debug.log; printed only with /cp debug on.
function ns.Log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local line = (date and date("%H:%M:%S") or "") .. " " .. table.concat(parts, " ")
  if ns.db then
    ns.db.debug = ns.db.debug or {}
    ns.db.debug.log = ns.db.debug.log or {}
    table.insert(ns.db.debug.log, line)
    while #ns.db.debug.log > 200 do table.remove(ns.db.debug.log, 1) end
    if ns.db.settings and ns.db.settings.debug then ns.Print("[debug]", table.concat(parts, " ")) end
  end
end

function ns:RegisterModule(name, module)
  assert(type(name) == "string" and type(module) == "table", "RegisterModule(name, table)")
  assert(not self.modules[name], "module already registered: " .. name)
  module.name = name
  self.modules[name] = module
  return module
end

-- Sorted iteration (deterministic Init order and report order).
function ns:EachModule(fn)
  local names = {}
  for name in pairs(self.modules) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do fn(name, self.modules[name]) end
end

-- Runs a lifecycle hook ("Init" or "Login") of every module in isolation: one broken module never stops the others.
function ns:RunHook(hook)
  self:EachModule(function(modName, module)
    if type(module[hook]) == "function" then
      local ok, err = pcall(module[hook], module)
      if not ok then
        ns.Health.Record(hook:lower() .. " " .. modName, err)
        ns.Print((L["Module %s could not start: %s"]):format(modName, tostring(err)))
      end
    end
  end)
end

-- Slash: /cp <command> [args]
ns.Slash = { handlers = {} }
function ns.Slash.Register(cmd, fn, help)
  ns.Slash.handlers[cmd] = { fn = fn, help = help }
end

local function printHelp()
  ns.Print(L["Commands:"])
  local names = {}
  for name in pairs(ns.Slash.handlers) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local entry = ns.Slash.handlers[name]
    ns.Print("  /cp " .. name .. (entry.help and (" - " .. L[entry.help]) or ""))
  end
end

function ns.Slash.Dispatch(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if not (ns.UI and ns.UI.Toggle) then return printHelp() end
    local ok, err = pcall(ns.UI.Toggle)
    if not ok then ns.Health.Record("/cp window", err); ns.Print((L["Command failed: %s"]):format(tostring(err))) end
    return
  end
  if cmd == "help" then return printHelp() end
  local h = ns.Slash.handlers[cmd]
  if h then
    local ok, err = pcall(h.fn, rest)
    if not ok then ns.Health.Record("/cp " .. cmd, err); ns.Print((L["Command failed: %s"]):format(tostring(err))) end
    return
  end
  ns.Print((L["Unknown command: %s"]):format(cmd))
  printHelp()
end

SLASH_CLASSPAGES1 = "/cp"
SLASH_CLASSPAGES2 = "/classpages"
SlashCmdList.CLASSPAGES = ns.Slash.Dispatch
