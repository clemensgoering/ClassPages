-- ClassPages: secret-value helpers (Midnight rules, active on Forever).
-- A secret value may be handed to a widget (SetText, SetCooldown, SetValue ...) but never compared, used for
-- arithmetic, used as a table key or saved. Code that only *displays* passes values straight through; code that
-- *decides* checks IsSecret first and degrades (e.g. hides a ready-flash) instead of erroring.
--
-- Public API (ns.Secret)
--   IsSecret(v) -> bool                    false when the client has no secret values
--   Any(...) -> bool                       true if any argument is secret
--   Safe(v, fallback) -> v | fallback      fallback when v is secret
local ADDON, ns = ...

ns.Secret = {}

local issecretvalue = issecretvalue

function ns.Secret.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- True if any argument is secret.
function ns.Secret.Any(...)
  if not issecretvalue then return false end
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return true end
  end
  return false
end

-- v when it is safe to use, otherwise fallback.
function ns.Secret.Safe(v, fallback)
  if ns.Secret.IsSecret(v) then return fallback end
  return v
end
