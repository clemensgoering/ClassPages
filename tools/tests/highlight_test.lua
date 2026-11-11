-- Ready flash state machine: never compares secrets, ignores the global cooldown, degrades to "no flash".
local ns, eq = ...
local H = ns.HUD.Highlight

eq(H.ReadActive(nil), nil, "read: no info")
eq(H.ReadActive({ isActive = true }), true, "read: isActive true")
eq(H.ReadActive({ isActive = false }), false, "read: isActive false")
eq(H.ReadActive({ isActive = "SECRET" }), nil, "read: secret isActive -> fallback")
eq(H.ReadActive({ isActive = "SECRET", startTime = "SECRET", duration = "SECRET" }), nil, "read: all secret -> unknown")
eq(H.ReadActive({ isActive = true, isOnGCD = true }), false, "read: GCD is not a cooldown")
eq(H.ReadActive({ isActive = true, isOnGCD = "SECRET" }), true, "read: secret isOnGCD ignored")
eq(H.ReadActive({ startTime = 100, duration = 8 }), true, "read: legacy fields active")
eq(H.ReadActive({ startTime = 0, duration = 0 }), false, "read: legacy fields idle")

local s = {}
eq(H.Step(s, true, 10), false, "step: becomes active")
eq(H.Step(s, true, 11), false, "step: stays active")
eq(H.Step(s, false, 18), true, "step: long cooldown ends -> flash")
eq(H.Step(s, false, 19), false, "step: no repeat")

local gcd = {}
H.Step(gcd, true, 10)
eq(H.Step(gcd, false, 11.5), false, "step: short active phase (GCD) -> no flash")

local unknown = { active = true, since = 0 }
eq(H.Step(unknown, nil, 50), false, "step: unknown keeps state")
eq(unknown.active, true, "step: unknown does not reset")
eq(H.Step(unknown, false, 51), true, "step: later readable end flashes")

-- counters: low and empty warnings, secrets are never compared
eq(H.CountState(nil), "none", "count: missing")
eq(H.CountState("SECRET"), "none", "count: secret")
eq(H.CountState(0), "empty", "count: empty")
eq(H.CountState(5), "low", "count: default threshold")
eq(H.CountState(6), "ok", "count: above threshold")
eq(H.CountState(150, 200), "low", "count: custom threshold (ammunition)")
