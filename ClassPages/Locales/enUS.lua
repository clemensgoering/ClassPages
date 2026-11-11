-- ClassPages: localisation core. The English text in the code is the key; Locales/deDE.lua holds the German table.
-- The language follows settings.language ("auto" = game language, "deDE", "enUS"). It is applied in ADDON_LOADED
-- before any module Init, so ns.L is read only at display time, never in file-level constants (those keep the
-- English key and translate where they are shown).
--
-- Public API
--   ns.L[key] -> text in the active language (falls back to the English key)
--   ns.Locale.Set(code) -> active code       code = "auto" | "deDE" | "enUS"; Resolve(code) without switching
--   ns.Locale.active, ns.Locale.tables[code], ns.Locale.LANGUAGES
local ADDON, ns = ...

local Locale = { active = "enUS", tables = { enUS = {} } }
ns.Locale = Locale
Locale.LANGUAGES = { { "auto", "Automatic (game language)" }, { "deDE", "Deutsch" }, { "enUS", "English" } }

function Locale.Client()
  local code = GetLocale and GetLocale()
  return Locale.tables[code] and code or "enUS"
end

function Locale.Resolve(code)
  if code == nil or code == "auto" or not Locale.tables[code] then return Locale.Client() end
  return code
end

function Locale.Set(code)
  Locale.active = Locale.Resolve(code)
  return Locale.active
end

ns.L = setmetatable({}, { __index = function(_, key)
  local t = Locale.tables[Locale.active]
  return t and t[key] or key
end })
