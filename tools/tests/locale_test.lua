-- Locale coverage (no game needed):
--   1. every L["..."] key used in the addon has a German translation in Locales/deDE*.lua
--   2. each translation keeps the format placeholders of its key (same ones, same order)
--   3. no German text is left in code outside the locale files (umlauts or common German words in string literals);
--      a line that must keep game-client text is marked with the comment "locale-ok"
local ns, eq, T = ...

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local root = here:gsub("/tools/tests/[^/]*$", "")
local addon = root .. "/ClassPages/"

local function tocFiles()
  local files = {}
  local f = assert(io.open(addon .. "ClassPages.toc", "r"))
  for line in f:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return files
end

local de = ns.Locale and ns.Locale.tables.deDE or {}
local function placeholders(s)
  local out = {}
  for p in s:gmatch("%%[%-%d%.]*[%a%%]") do out[#out + 1] = p end
  return table.concat(out, " ")
end

local GERMAN_WORDS = { "und", "nicht", "oder", "noch", "kein", "keine", "mit", "bei", "ist", "sind", "wird", "werden", "nach",
  "auf", "zum", "zur", "dem", "der", "das", "ein", "eine", "einen", "vom", "jetzt", "alle", "Fenster", "Beruf", "Berufe" }
local function looksGerman(s)
  if s:find("[\195][\132\150\156\164\182\188\159]") then return true end -- Ä Ö Ü ä ö ü ß
  local padded = " " .. s:gsub("[%p]", " ") .. " "
  for _, w in ipairs(GERMAN_WORDS) do if padded:find(" " .. w .. " ", 1, true) then return true end end
  return false
end

local missing, badFormat, leftovers, used = {}, {}, {}, 0
for _, rel in ipairs(tocFiles()) do
  if not rel:match("^Locales/") and not rel:match("^Libs/") and not rel:match("^Classes/Data/") then  -- class pages are bilingual data
    local f = io.open(addon .. rel, "r")
    if f then
      local n = 0
      for line in f:lines() do
        n = n + 1
        local code = line:match("^%s*%-%-") and "" or line
        for key in code:gmatch("L%[\"(.-[^\\])\"%]") do
          used = used + 1
          if not de[key] then missing[#missing + 1] = rel .. ":" .. n .. "  " .. key
          elseif placeholders(de[key]) ~= placeholders(key) then badFormat[#badFormat + 1] = rel .. ":" .. n .. "  " .. key end
        end
        if not code:find("locale-ok", 1, true) then
          local stripped = code:gsub("L%[\".-[^\\]\"%]", "")
          for lit in stripped:gmatch("\"([^\"\\]*)\"") do
            if looksGerman(lit) then leftovers[#leftovers + 1] = rel .. ":" .. n .. "  \"" .. lit .. "\"" end
          end
        end
      end
      f:close()
    end
  end
end

-- keys that reach L[] through data (titles, families, labels), collected from the loaded addon
local indirect = {}
local function want(key, where) if type(key) == "string" and key ~= "" and not de[key] then indirect[#indirect + 1] = where .. "  " .. key end end
for _, k in ipairs(ns.HUD.Kinds.List()) do want(ns.HUD.Kinds.Get(k).title, "kind") end
for class, profile in pairs(ns.Classes.profiles) do
  for _, p in ipairs(profile.presets) do want(p.title, class .. " preset") end
  for _, r in ipairs(profile.reactive) do want(r.hint, class .. " reactive") end
end
for _, p in ipairs(ns.Classes.GENERIC.presets) do want(p.title, "generic preset") end
for _, trees in pairs(ns.Classes.TREES) do for _, t in ipairs(trees) do want(t, "talent tree") end end
for _, f in ipairs(ns.HunterPets.FAMILIES) do
  want(f.key, "family"); want(f.unique, "family ability")
  for _, d in ipairs(f.diet) do want(d, "diet") end
end
for _, lvl in ipairs({ 1, 2, 3, 0 }) do want((ns.HunterPets.HappinessText(lvl)), "happiness") end
for _, l in ipairs(ns.Locale.LANGUAGES) do want(l[2], "language") end
for _, k in ipairs({ "Overview", "Talents", "Pets", "HUD", "Ammunition", "Pet", "Happiness", "Training points",
  "Cooldown", "Ready flash", "Reactive glow", "Proc glow", "Range tint", "Only in combat", "For my level", "All levels",
  "Low count warning", "Layout", "Timers", "Visibility", "Show", "Only with a target", "Fade in on mouseover", "Any", "Trainer",
  "What your trainer teaches now and soon, with costs.", "Visit your class trainer once to fill this list.",
  "Move in game", "Bind keys", "Refill from preset", "Undo", "Clear buttons", "Delete bar",
  "Opens the edit mode with this bar selected.", "Hover a button, press a key · Delete clears · Esc ends",
  "Replaces the buttons with the known spells of the class preset. Undo restores them.",
  "Already at max rank.", "No points left for this level.", "Spend more points in this tree first (5 per row).", "Requires the talent above at max rank.",
  "Other talents depend on this point.", "No point to remove.", "invalid text", "rank too high", "row locked", "requires prerequisite",
  "Columns (buttons per row)", "Rows", "Button size", "Spacing", "Scale", "Opacity", "Columns", "Scale %", "Opacity %",
  "In the quiver", "Note", "Ammunition", "Name", "Family", "Level", "Loyalty", "Class", "Known spells", "Class page",
  "No professions learned.", "Professions" }) do want(k, "label") end
missing = missing or {}
for _, m in ipairs(indirect) do missing[#missing + 1] = m end

local function report(title, list)
  if #list == 0 then return end
  print(("%s (%d):"):format(title, #list))
  local limit = os.getenv("CP_ALL_KEYS") and #list or 40
  for i = 1, math.min(#list, limit) do print("  " .. list[i]) end
  if #list > 40 then print(("  ... %d more"):format(#list - 40)) end
end
report("locale: keys without German translation", missing)
report("locale: translation changes the format placeholders", badFormat)
report("locale: German text left in code (translate via L or mark the line locale-ok)", leftovers)
eq(#missing, 0, "locale: every key translated")
eq(#badFormat, 0, "locale: placeholders kept")
eq(#leftovers, 0, "locale: no German text in code")
eq(used > 0, true, "locale: keys found")

-- switching works and falls back to the key
local before = ns.Locale.active
ns.Locale.Set("deDE")
eq(ns.L["Talents"], "Talente", "locale: German active")
eq(ns.L["__no such key__"], "__no such key__", "locale: fallback to key")
ns.Locale.Set("enUS")
eq(ns.L["Talents"], "Talents", "locale: English active")
eq(ns.Locale.Resolve("xxXX"), ns.Locale.Client(), "locale: unknown code resolves to game language")
ns.Locale.Set(before)
local _ = T
