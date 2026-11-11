-- HUD bar model: defaults, repair of damaged saves, grid layout, IDs, visibility, timer flags per content kind.
local ns, eq = ...
local Model, Kinds = ns.HUD.Model, ns.HUD.Kinds

local bar = Model.New({ name = "Shots", kind = "attacks", cols = 8 })
eq(bar.cols, 8, "model: cols kept")
eq(bar.rows, 1, "model: default rows")
eq(bar.size, 36, "model: default size")
eq(bar.point[1], "CENTER", "model: default point")

-- damaged save: wrong types, out of range, junk buttons; slots beyond the grid survive
local broken = { id = 7, name = 5, kind = "nonsense", cols = "x", rows = 99, size = 3, spacing = -4, scale = 9, alpha = 2,
  point = { "NOWHERE", 1, 2 }, timers = { readyFlash = "yes", cooldown = false },
  buttons = { [1] = { type = "spell", id = 75 }, [2] = { type = "bogus", id = 1 }, [3] = "junk", [40] = { type = "item", id = 6948 }, x = { type = "spell", id = 1 } } }
local fixed, changed = Model.Sanitize(broken)
eq(changed, true, "sanitize: reports change")
eq(fixed.kind, "free", "sanitize: unknown kind -> free")
eq(fixed.cols, 6, "sanitize: non-number cols -> default")
eq(fixed.rows, 12, "sanitize: rows clamped to max")
eq(fixed.size, 16, "sanitize: size clamped to min")
eq(fixed.spacing, 0, "sanitize: spacing clamped")
eq(fixed.scale, 2, "sanitize: scale clamped")
eq(fixed.alpha, 1, "sanitize: alpha clamped")
eq(fixed.point[1], "CENTER", "sanitize: bad anchor reset")
eq(fixed.name, "Bar 7", "sanitize: name repaired")
eq(fixed.timers.readyFlash, nil, "sanitize: non-boolean flag dropped")
eq(fixed.timers.cooldown, false, "sanitize: boolean flag kept")
eq(fixed.buttons[1].id, 75, "sanitize: valid button kept")
eq(fixed.buttons[2], nil, "sanitize: unknown button type dropped")
eq(type(fixed.unknown) == "table" and fixed.unknown[2] ~= nil, true, "sanitize: unknown button type parked, not lost")
local parked = fixed.unknown[2]
Model.BUTTON_TYPES[parked.type] = true
if type(parked.id) ~= "number" then parked.id = 1 end
Model.Sanitize(fixed)
eq(fixed.buttons[2], parked, "sanitize: parked button returns once its type is known")
Model.BUTTON_TYPES[parked.type] = nil
Model.Sanitize(fixed)
eq(fixed.buttons[3], nil, "sanitize: junk button dropped")
eq(fixed.buttons[40].id, 6948, "sanitize: slot beyond grid kept")
eq(fixed.buttons.x, nil, "sanitize: non-numeric slot dropped")
local _, again = Model.Sanitize(fixed)
eq(again, false, "sanitize: idempotent")
eq(Model.Sanitize("garbage"), nil, "sanitize: non-table")

-- layout
local grid = Model.New({ cols = 3, rows = 2, size = 40, spacing = 4 })
local layout = Model.Layout(grid)
eq(layout.width, 3 * 40 + 2 * 4, "layout: width")
eq(layout.height, 2 * 40 + 4, "layout: height")
eq(#layout.slots, 6, "layout: slot count")
eq(layout.slots[2].x, 44, "layout: second column x")
eq(layout.slots[4].x, 0, "layout: wraps to next row")
eq(layout.slots[4].y, -44, "layout: next row y")
eq(Model.Capacity(grid), 6, "layout: capacity")

-- ids
local hud = { bars = { [1] = Model.New({ id = 1 }) }, nextID = 1 }
local b2 = Model.Add(hud, { name = "B" })
eq(b2.id, 2, "add: skips used id")
local b3 = Model.Add(hud, { name = "C" })
eq(b3.id, 3, "add: increments")
eq(hud.bars[3], b3, "add: stored")

-- visibility
eq(Model.VisibilityCondition(Model.New({ enabled = false }), false), "hide", "vis: disabled")
eq(Model.VisibilityCondition(Model.New({ enabled = false }), true), "show", "vis: editing shows all")
eq(Model.VisibilityCondition(Model.New({ kind = "pet" }), false), "[pet] show; hide", "vis: pet bar")
eq(Model.VisibilityCondition(Model.New({ kind = "pet", show = { target = true }, timers = { hideOOC = true } }), false), "[pet,combat,exists] show; hide", "vis: rules combine")
eq(Model.VisibilityCondition(Model.New({ show = { stance = 2 } }), false), "[stance:2] show; hide", "vis: stance")
eq(Model.VisibilityCondition(Model.New({ show = { mouseover = true } }), false), "show", "vis: mouseover is a fade, not a driver rule")
local sv = Model.New({ show = { target = "yes", stance = 99, mouseover = true, junk = 1 }, keys = { [1] = "SHIFT-1", [2] = 5, x = "A" } })
eq(sv.show.target, nil, "sanitize: non-boolean show rule dropped")
eq(sv.show.stance, nil, "sanitize: stance out of range dropped")
eq(sv.show.mouseover, true, "sanitize: valid show rule kept")
eq(sv.show.junk, nil, "sanitize: unknown show rule dropped")
eq(sv.keys[1], "SHIFT-1", "sanitize: key kept")
eq(sv.keys[2], nil, "sanitize: non-string key dropped")
eq(sv.keys.x, nil, "sanitize: non-numeric key slot dropped")

-- key chords
eq(Model.Chord("1", false, false, true), "SHIFT-1", "chord: shift")
eq(Model.Chord("F", true, true, true), "ALT-CTRL-SHIFT-F", "chord: modifier order")
eq(Model.Chord("LSHIFT", false, false, true), nil, "chord: modifier alone")
eq(Model.Chord("ESCAPE"), nil, "chord: escape stays free")
eq(Model.ShortKey("ALT-CTRL-SHIFT-NUMPAD5"), "A-C-S-N5", "chord: short text")
eq(Model.ShortKey(nil), "", "chord: short of nil")
local kh = { bars = { [1] = Model.New({ id = 1 }), [2] = Model.New({ id = 2 }) } }
eq(Model.SetKey(kh, 1, 3, "SHIFT-1"), nil, "keys: first assignment")
local removed = Model.SetKey(kh, 2, 1, "SHIFT-1")
eq(removed and removed[1], 1, "keys: taken from the other bar")
eq(kh.bars[1].keys[3], nil, "keys: old button released")
eq(kh.bars[2].keys[1], "SHIFT-1", "keys: new button bound")
Model.SetKey(kh, 2, 1, nil)
eq(kh.bars[2].keys[1], nil, "keys: cleared")
local kr = { bars = { [1] = Model.New({ id = 1, cols = 12, rows = 1 }), [2] = Model.New({ id = 2, cols = 3, rows = 1 }) } }
Model.SetKey(kr, 1, 5, "2")
Model.SetKey(kr, 1, 6, "SHIFT-2")
local touched = Model.KeyRow(kr, 2)
eq(#touched, 2, "key row: both bars changed")
eq(kr.bars[2].keys[1] .. kr.bars[2].keys[2] .. kr.bars[2].keys[3], "123", "key row: 1-3 on a three button bar")
eq(kr.bars[2].keys[4], nil, "key row: no key beyond the grid")
eq(kr.bars[1].keys[5], nil, "key row: key taken from the other bar")
eq(kr.bars[1].keys[6], "SHIFT-2", "key row: other chords stay")
eq(Model.KeyRow(kr, 1)[1], 1, "key row: main bar")
eq(kr.bars[1].keys[10] .. kr.bars[1].keys[12], "0=", "key row: 0 and = on slots 10 and 12")
eq(kr.bars[2].keys[1], nil, "key row: taken back")
eq(#Model.KeyRow(kr, 9), 0, "key row: unknown bar")
local rp = { bars = { [1] = Model.New({ id = 1, cols = 2, rows = 1, buttons = { { type = "spell", id = 7 }, { type = "spell", id = 8 }, { type = "pet", id = 1 } } }) } }
local isStance = function(id) return id == 8 end
eq(Model.Replaces(rp, isStance).stance, true, "replaces: stance spell on an enabled bar")
eq(Model.Replaces(rp, isStance).pet, false, "replaces: pet button beyond the grid does not count")
rp.bars[1].cols = 3
eq(Model.Replaces(rp, isStance).pet, true, "replaces: pet button inside the grid")
rp.bars[1].enabled = false
eq(Model.Replaces(rp, isStance).pet, false, "replaces: disabled bar replaces nothing")
eq(Model.Replaces(rp, nil).stance, false, "replaces: no stance check without resolver")
eq(Model.VisibilityCondition(Model.New({ kind = "attacks", timers = { hideOOC = true } }), false), "[combat] show; hide", "vis: combat only")

-- kinds: professions never flash, attacks do, overrides win
local prof = Kinds.Effective({ kind = "professions", timers = {} })
eq(prof.readyFlash, false, "kinds: professions no ready flash")
eq(prof.cooldown, true, "kinds: professions follow source cooldown")
eq(Kinds.Effective({ kind = "attacks", timers = {} }).readyFlash, true, "kinds: attacks flash")
eq(Kinds.Effective({ kind = "attacks", timers = { readyFlash = false } }).readyFlash, false, "kinds: override off")
eq(Kinds.Effective({ kind = "pet", timers = { readyFlash = true } }).readyFlash, true, "kinds: override on")
eq(Kinds.Get("unknown").key, "free", "kinds: fallback")

-- empty bars, snapping, resize by corner drag
local e = Model.New({ cols = 2, rows = 1, buttons = { [5] = { type = "spell", id = 1 } } })
eq(Model.IsEmpty(e), true, "empty: buttons only beyond the grid")
e.buttons[2] = { type = "spell", id = 2 }
eq(Model.IsEmpty(e), false, "empty: button inside the grid")
eq(Model.Snap(13, 8), 16, "snap: rounds to step")
eq(Model.Snap(-11, 8), -8, "snap: negative")
eq(Model.Snap(13, 0), 13, "snap: off")
local c, r = Model.GridFromDrag(6, 1, 85, 0, 40)
eq(c, 8, "grip: two columns more")
eq(r, 1, "grip: rows unchanged")
c, r = Model.GridFromDrag(6, 1, -1000, 120, 40)
eq(c, 1, "grip: columns clamped")
eq(r, 4, "grip: rows by dragging down")

-- mover geometry: a bar at scale 2 centred on screen
local x, y = ns.HUD.Mover and ns.HUD.Mover.CenterOffset(480, 270, 960, 540, 2) or 0, 0
if ns.HUD.Mover then eq(x, 0, "mover: centred x"); eq(y, 0, "mover: centred y") end
