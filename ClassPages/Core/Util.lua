-- ClassPages: small shared helpers. Pure Lua so the headless tests can load this file.
--
-- Public API (ns.Util)
--   DeepCopy(t) -> copy                    recursive, keeps shared references and cycles
--   Money(copper) -> "12g 34s 56c"         zero parts left out
--   Clamp(x, lo, hi) -> number             non-numbers become lo
--   Round(x, digits) -> number
--   Count(t) -> n                          number of entries of any table (nil = 0)
--   FormatRemaining(seconds) -> text       "1:05", "42", "2.4"; "" when nothing is left
--   EncodeNumbers(list) -> "1.2.3", DecodeNumbers(text) -> list | nil   flat number lists for import/export
--   CharKey() -> "Name - Realm" | nil      stable character key
local ADDON, ns = ...

local Util = {}
ns.Util = Util

function Util.DeepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[Util.DeepCopy(k, seen)] = Util.DeepCopy(v, seen) end
  return out
end

-- Copper as "12g 34s 56c" (zero parts left out).
function Util.Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

function Util.Clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function Util.Round(x, digits)
  local m = 10 ^ (digits or 0)
  return math.floor(x * m + 0.5) / m
end

function Util.Count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Countdown text like the default UI: "1:05" from 60 s, "42" from 3 s, "2.4" below.
function Util.FormatRemaining(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "" end
  if seconds >= 3600 then return ("%dh"):format(math.ceil(seconds / 3600)) end
  if seconds >= 60 then return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60)) end
  if seconds >= 3 then return ("%d"):format(math.ceil(seconds)) end
  return ("%.1f"):format(seconds)
end

-- Compact, stable string encoding of a flat list of numbers for import/export ("0-5-3-..." style).
function Util.EncodeNumbers(list)
  local parts = {}
  for i, v in ipairs(list) do parts[i] = tostring(math.floor(tonumber(v) or 0)) end
  return table.concat(parts, ".")
end

function Util.DecodeNumbers(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for part in text:gmatch("[^%.]+") do
    local n = tonumber(part)
    if not n then return nil end
    out[#out + 1] = n
  end
  return out
end

-- Character key "Name - Realm" (realm without spaces), stable across sessions.
function Util.CharKey()
  if not UnitFullName then return nil end
  local name, realm = UnitFullName("player")
  if ns.Secret.Any(name, realm) or not name then return nil end
  if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() or "?" end
  if ns.Secret.IsSecret(realm) then realm = "?" end
  return name .. " - " .. tostring(realm)
end
