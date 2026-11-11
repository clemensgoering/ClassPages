-- Presets and spell resolution: highest known rank by name, only known spells, seed once, refill with undo.
local ns, eq = ...
local SB, Content, Classes = ns.Spellbook, ns.HUD.Content, ns.Classes

local index = SB.BuildIndex({
  { spellID = 75, name = "Auto Shot" },
  { spellID = 3044, name = "Arcane Shot" },
  { spellID = 14281, name = "Arcane Shot" },  -- rank 2 after rank 1
  { spellID = 99999, name = "Passive Thing", passive = true },
})
eq(index.byName["Arcane Shot"], 14281, "spellbook: highest rank wins")
eq(index.byName["Passive Thing"], nil, "spellbook: passives skipped")
eq(index.count, 3, "spellbook: count")
SB.index = index
eq(SB.Resolve(3044), 14281, "resolve: rank 1 -> highest known")
eq(SB.Resolve(14281), 14281, "resolve: any rank -> highest known")
eq(SB.Resolve(19306), nil, "resolve: unknown spell")

local hunter = Classes.Get("HUNTER")
eq(hunter.class, "HUNTER", "classes: hunter registered")
eq(Classes.Get("DEATHKNIGHT").class, "GENERIC", "classes: generic fallback")
local shots
for _, p in ipairs(hunter.presets) do if p.key == "shots" then shots = p end end
local buttons = Content.PresetButtons(hunter, shots)
eq(#buttons, 2, "preset: only known spells (Auto Shot, Arcane Shot)")
eq(buttons[2].id, 3044, "preset: stores base id")
eq(#Content.PresetButtons(hunter, { generator = "pet" }), 10, "preset: pet generator")
eq(Classes.ReactiveSet(hunter)[19306] ~= nil, true, "classes: counterattack is reactive")

local ok = pcall(Classes.Register, Classes, { class = "TEST", spells = {}, presets = { { key = "x", spells = { "missing" } } } })
eq(ok, false, "classes: preset with unknown spell key rejected")

local hud = { bars = {}, nextID = 1, seeded = false }
local n = Content.Seed(hud, hunter)
eq(n, #hunter.presets, "seed: one bar per preset")
eq(Content.Seed(hud, hunter), 0, "seed: only once")
local shotsBar
for _, bar in pairs(hud.bars) do if bar.preset == "shots" then shotsBar = bar end end
eq(shotsBar.kind, "attacks", "seed: kind from preset")
eq(shotsBar.cols, 8, "seed: grid from preset")

shotsBar.buttons[5] = { type = "item", id = 6948 }
SB.index = SB.BuildIndex({ { spellID = 75, name = "Auto Shot" }, { spellID = 3044, name = "Arcane Shot" }, { spellID = 1130, name = "Hunter's Mark" } })
eq(Content.Refill(shotsBar, hunter), true, "refill: works")
eq(shotsBar.buttons[5], nil, "refill: replaced buttons")
eq(shotsBar.buttons[2].id, 1130, "refill: newly known spell in order")
eq(Content.Undo(shotsBar), true, "undo: works")
eq(shotsBar.buttons[5].id, 6948, "undo: user button back")
eq(Content.Undo(shotsBar), false, "undo: only once")

eq(Content.FromLAB("item", "item:6948").id, 6948, "lab: item string")
eq(Content.FromLAB("spell", 75).id, 75, "lab: spell")
eq(Content.FromLAB("empty", nil), nil, "lab: empty clears slot")
local kind, value = Content.Runtime({ type = "spell", id = 3044 })
eq(kind .. ":" .. tostring(value), "spell:3044", "runtime: spell")
kind, value = Content.Runtime({ type = "item", id = 6948 })
eq(value, "item:6948", "runtime: item")
eq((Content.Runtime(nil)), "empty", "runtime: empty")

-- pets: family facts matched through the locale and merged with observations
local fam = ns.HunterPets.Family("Wolf")
eq(fam.unique, "Furious Howl", "pets: static family fact")
eq(fam.dietConfirmed, nil, "pets: static diet unconfirmed")
ns.db.families.Wolf = { diet = { "Meat", "Fish" } }
eq(ns.HunterPets.Family("Wolf").dietConfirmed, true, "pets: observed diet wins")
local text = ns.HunterPets.HappinessText(3)
eq(text, "Happy", "pets: happiness text")
