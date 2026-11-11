-- Class pages: every data file in Classes/Data validates against docs/04-KLASSENSEITEN.md, keys are unique,
-- the level filter and row building behave.
local ns, eq, T = ...
local Guide = ns.Guide

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local root = here:gsub("/tools/tests/[^/]*$", "")
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
for _, class in ipairs(CLASSES) do
  local chunk = loadfile(root .. "/ClassPages/Classes/Data/" .. class .. ".lua")
  eq(chunk ~= nil, true, "classdata: file loads " .. class)
  if chunk then chunk("ClassPages", ns) end
end

local keys, pages = {}, ns.Classes.AllPages()
eq(#pages >= 18, true, "classdata: at least two pages per class")
for _, page in ipairs(pages) do
  eq(keys[page.key], nil, "classdata: unique key " .. page.key)
  keys[page.key] = true
  local problems = Guide.Validate(page)
  for i = 1, math.min(#problems, 10) do print("  " .. problems[i]) end
  eq(#problems, 0, "classdata: valid " .. page.key)
end
for _, class in ipairs(CLASSES) do
  local profile = ns.Classes.Get(class)
  eq(profile.class, class, "classdata: profile for " .. class)
  eq(#profile.pages >= 2, true, "classdata: pages for " .. class)
end

-- pure helpers
eq(Guide.Text({ enUS = "A", deDE = "B" }) ~= "", true, "guide: text")
eq(Guide.Relevant({ minLevel = 30 }, 26), true, "guide: shown 5 levels early")
eq(Guide.Relevant({ minLevel = 30 }, 41), false, "guide: hidden 11 levels later")
eq(Guide.Relevant({ minLevel = 10, maxLevel = 60 }, 55), true, "guide: maxLevel extends")
local page = { key = "x", sections = {
  { title = { enUS = "S1", deDE = "S1" }, entries = { { minLevel = 50, name = { enUS = "b" } }, { minLevel = 5, name = { enUS = "a" } } } },
  { title = { enUS = "S2", deDE = "S2" }, entries = { { minLevel = 58, name = { enUS = "c" } } } } } }
local rows = Guide.Rows(page, 5, "level")
eq(#rows, 2, "guide: header + one entry for level 5")
eq(rows[1].header, "S1", "guide: header first")
local all = Guide.Rows(page, 5, "all")
eq(#all, 5, "guide: all levels")
eq(all[2].entry.minLevel, 5, "guide: sorted by level")
local bad = Guide.Validate({ key = "Bad Key", title = { enUS = "x" }, order = 5, sections = { { title = { enUS = "a", deDE = "b" },
  entries = { { kind = "nope", minLevel = 70, itemID = "12", name = { enUS = "n" }, note = { enUS = "n", deDE = "n" }, confidence = "Z" } } } } })
eq(#bad >= 6, true, "guide: invalid page reported")
local _ = T
