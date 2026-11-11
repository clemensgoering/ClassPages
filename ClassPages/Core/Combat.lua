-- ClassPages: combat lockdown guard. Secure frames (action buttons, bar headers) may only be created, moved, shown,
-- hidden or re-attributed out of combat. Every such change goes through ns.Combat.Run, which runs it now or queues it
-- (deduplicated by key, last one wins) until PLAYER_REGEN_ENABLED.
--
-- Public API
--   ns.Combat.Run(key, fn)    run fn() now, or after combat; returns true when it ran immediately
--   ns.Combat.InLockdown()    InCombatLockdown() that never raises
--   ns.Combat.Pending()       number of queued changes
--   ns.Combat.Flush()         run the queued changes now (on PLAYER_REGEN_ENABLED; each in isolation)
local ADDON, ns = ...

local Combat = { queue = {}, order = {} }
ns.Combat = Combat

function Combat.InLockdown()
  return InCombatLockdown and InCombatLockdown() and true or false
end

function Combat.Run(key, fn)
  if not Combat.InLockdown() then
    fn()
    return true
  end
  if not Combat.queue[key] then Combat.order[#Combat.order + 1] = key end
  Combat.queue[key] = fn
  return false
end

function Combat.Pending() return #Combat.order end

function Combat.Flush()
  local order, queue = Combat.order, Combat.queue
  Combat.order, Combat.queue = {}, {}
  for _, key in ipairs(order) do
    local ok, err = pcall(queue[key])
    if not ok then ns.Health.Record("after combat: " .. tostring(key), err) end
  end
end

ns.Events:On("PLAYER_REGEN_ENABLED", Combat.Flush, "Combat")
