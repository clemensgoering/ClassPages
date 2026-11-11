-- ClassPages: debug report (/cp debug). Runs every module's SelfTest and collects client, features, data, events,
-- errors, probe results and the log into one copyable text window. A bug report = this text + one sentence.
--
-- Public API (ns.Debug)
--   Report() -> text      build the report (also stored in ClassPagesDB.debug.report)
--   Run()                 build and show
local ADDON, ns = ...
local L = ns.L

local Debug = {}
ns.Debug = Debug

function Debug.Report()
  local out = {}
  local function add(s) out[#out + 1] = s end
  local function section(title) add(""); add("== " .. title .. " ==") end

  local version, build, _, interface = GetBuildInfo()
  add(("ClassPages %s · client %s (%s) · interface %s (TOC %s) · locale %s"):format(ns.version, tostring(version), tostring(build), tostring(interface), ns.INTERFACE, tostring(GetLocale and GetLocale())))
  local class = ns.API.PlayerClass()
  add(("class %s · level %s · profile %s"):format(tostring(class), tostring(ns.API.PlayerLevel()), ns.Profiles.Current()))

  section("Features")
  for _, row in ipairs(ns.Features.Status()) do add(("%s %s: %s"):format(row.ok and "[ok]" or "[--]", row.name, row.detail)) end
  local failures = {}
  for path, n in pairs(ns.API.failures) do failures[#failures + 1] = path .. " x" .. n end
  table.sort(failures)
  if #failures > 0 then add("API failures: " .. table.concat(failures, ", ")) end

  section("Modules")
  ns:EachModule(function(name, module)
    if type(module.SelfTest) ~= "function" then return end
    local ok, rows = pcall(module.SelfTest, module)
    if not ok then add(("[ERR] %s: %s"):format(name, tostring(rows))); return end
    for _, r in ipairs(rows or {}) do
      add(("%s %s / %s: %s"):format(r.ok and (r.warn and "[warn]" or "[ok]") or "[FAIL]", name, tostring(r.name), tostring(r.detail or "")))
    end
  end)

  section("Data")
  for k, v in pairs(ns.DB.Stats()) do add(("%s = %s"):format(k, tostring(v))) end

  section("Events")
  local ev = {}
  for _, row in ipairs(ns.Events:Summary()) do ev[#ev + 1] = row.event .. "(" .. row.handlers .. ")" end
  add(table.concat(ev, " "))
  add(("secret-guard skips: %d · unknown events: %s · detached: %s"):format(ns.Events.skipped, table.concat(ns.Events.unknown or {}, ", "), table.concat(ns.Health.detached, ", ")))

  section("Errors")
  for _, e in ipairs(ns.db.debug.errors or {}) do add(("%s %s: %s"):format(date and date("%m-%d %H:%M", e.t) or "", tostring(e.where), tostring(e.err))) end

  section("Probe")
  for context, lines in pairs(ns.db.probe.hud or {}) do
    add("-- " .. context)
    for _, l in ipairs(lines) do add(l) end
  end
  for _, l in ipairs(ns.db.probe.talents or {}) do add("talents: " .. l) end

  section("Log (last 40)")
  local log = ns.db.debug.log or {}
  for i = math.max(1, #log - 39), #log do add(log[i]) end

  local text = table.concat(out, "\n")
  ns.db.debug.report = text
  return text
end

local window
local function show(text)
  if not window then
    window = CreateFrame("Frame", "ClassPagesDebug", UIParent)
    window:SetSize(640, 460)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    ns.UI.Skin(window, "window")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    local title = ns.UI.Text(window, L["ClassPages report: select all (Ctrl+A), copy (Ctrl+C)"], "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    local close = ns.UI.Button(window, L["Close"], 80, function() window:Hide() end, "ghost")
    close:SetPoint("TOPRIGHT", -8, -6)
    local scroll = ns.UI.SafeCreate("ScrollFrame", window, { "UIPanelScrollFrameTemplate" })
    scroll:SetPoint("TOPLEFT", 12, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(590)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    scroll:SetScrollChild(edit)
    window.edit = edit
    if UISpecialFrames then table.insert(UISpecialFrames, "ClassPagesDebug") end
  end
  window.edit:SetText(text)
  window:Show()
  window.edit:SetFocus()
  window.edit:HighlightText()
end

function Debug.Run() show(Debug.Report()) end

ns.Slash.Register("debug", function(arg)
  local sub = (arg or ""):match("^%S*"):lower()
  if sub == "on" or sub == "off" then
    ns.db.settings.debug = (sub == "on")
    return ns.Print((L["debug %s"]):format(ns.db.settings.debug and L["on"] or L["off"]))
  end
  Debug.Run()
end, "self test and copyable report (on|off for the debug log)")
