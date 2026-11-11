-- ClassPages: single event frame with a handler table, a secret-value guard and error isolation.
--
-- Public API
--   ns.Events:On(event, fn, owner?, opts?)  register fn(event, ...); owner = module name for error reports (defaults to
--                                     the registering file). opts.allowSecret = true: the handler also runs when an
--                                     argument is secret (it promises to only pass values on to widgets, never compare)
--   ns.Events:Off(event, fn)          remove a handler
--   ns.Events:Summary()               { {event, handlers} } for the debug report
--   ns.Events.Later(key, delay, fn)   run fn once after delay seconds; calls with the same key in between collapse
--                                     into that one run (the newest fn wins). For bursts of update events.
--   ns.Events.skipped                 how many deliveries the secret-value guard skipped
--   ns.Health.Record(where, err)      store an error (session list + ClassPagesDB.debug.errors)
--   ns.Health.errors / .detached      error entries / handlers detached after MAX_ERRORS failures
--
-- Rules: handlers are skipped when any event argument is a secret value; a handler that fails MAX_ERRORS times is
-- detached so one broken module cannot spam the session. Display handlers (allowSecret) drive the HUD in combat, so
-- they are only paused for PAUSE seconds and then get a fresh start. Handlers run newest-first.
local ADDON, ns = ...
local L = ns.L

local frame = CreateFrame("Frame")
local handlers = {}
local MAX_ERRORS = 5
local PAUSE = 30
local pending = {}

ns.Events = { frame = frame, skipped = 0 }
ns.Health = { errors = {}, detached = {} }

function ns.Health.Record(where, err)
  local entry = { t = time and time() or 0, where = where, err = tostring(err) }
  table.insert(ns.Health.errors, entry)
  while #ns.Health.errors > 30 do table.remove(ns.Health.errors, 1) end
  if ns.db then
    ns.db.debug = ns.db.debug or {}
    ns.db.debug.errors = ns.db.debug.errors or {}
    table.insert(ns.db.debug.errors, entry)
    while #ns.db.debug.errors > 50 do table.remove(ns.db.debug.errors, 1) end
  end
end

-- Owner name from the call stack when none is given: "Modules/Mail.lua" -> "Mail".
local function inferOwner()
  local stack = debugstack and debugstack(3, 1, 0) or (debug and debug.traceback and debug.traceback("", 3)) or ""
  local file = stack:match("ClassPages[/\\]([%w_/\\]+)%.lua")
  if file then return (file:match("([%w_]+)$")) end
  return "?"
end

-- Returns true when registered. An event unknown to this client (renamed or removed by a patch) is recorded in
-- ns.Health and skipped instead of raising, so the registering module still starts (verified need: Forever has no
-- BROWSE_SEARCH_RESULTS_UPDATED).
function ns.Events:On(event, fn, owner, opts)
  assert(type(event) == "string" and type(fn) == "function", "Events:On(event, fn, owner?, opts?)")
  owner = owner or inferOwner()
  if not handlers[event] then
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
      ns.Health.Record("RegisterEvent " .. event .. " (" .. owner .. ")", err)
      ns.Events.unknown = ns.Events.unknown or {}
      ns.Events.unknown[#ns.Events.unknown + 1] = event .. " (" .. owner .. ")"
      return false
    end
    handlers[event] = {}
  end
  table.insert(handlers[event], { fn = fn, owner = owner, errors = 0, allowSecret = opts and opts.allowSecret or false })
  return true
end

function ns.Events.Later(key, delay, fn)
  local waiting = pending[key] ~= nil
  pending[key] = fn
  if waiting then return end
  if not (C_Timer and C_Timer.After) then pending[key] = nil; fn(); return end
  C_Timer.After(delay, function()
    local run = pending[key]
    pending[key] = nil
    if run then run() end
  end)
end

function ns.Events:Off(event, fn)
  local list = handlers[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].fn == fn then table.remove(list, i) end
  end
  if #list == 0 then
    handlers[event] = nil
    frame:UnregisterEvent(event)
  end
end

function ns.Events:Summary()
  local rows = {}
  for event, list in pairs(handlers) do rows[#rows + 1] = { event = event, handlers = #list } end
  table.sort(rows, function(a, b) return a.event < b.event end)
  return rows
end

local function deliver(list, i, event, ...)
  local h = list[i]
  if h.pausedUntil then
    if GetTime() < h.pausedUntil then return end
    h.pausedUntil = nil
  end
  local ok, err = pcall(h.fn, event, ...)
  if ok then return end
  h.errors = h.errors + 1
  ns.Health.Record(event .. " (" .. h.owner .. ")", err)
  if h.errors == 1 then ns.Print((L["Error in %s (%s): %s"]):format(event, h.owner, tostring(err))) end
  if h.errors >= MAX_ERRORS then
    if h.allowSecret and GetTime then
      h.errors, h.pausedUntil = 0, GetTime() + PAUSE
      if not h.reported then
        h.reported = true
        ns.Print(L["Handler for %s (%s) paused after %d errors. /cp debug shows details."]:format(event, h.owner, MAX_ERRORS))
      end
      return
    end
    table.remove(list, i)
    ns.Health.detached[#ns.Health.detached + 1] = event .. " (" .. h.owner .. ")"
    ns.Print(L["Handler for %s (%s) disabled after %d errors. /cp debug shows details."]:format(event, h.owner, MAX_ERRORS))
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local secret = ns.Secret.Any(...)
  if secret then ns.Events.skipped = ns.Events.skipped + 1 end
  for i = #list, 1, -1 do
    -- handlers that compare or store their arguments never see a secret value
    if list[i] and (not secret or list[i].allowSecret) then deliver(list, i, event, ...) end
  end
end)
