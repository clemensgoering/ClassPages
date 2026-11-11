-- Trainer book (pure parts): merging visits, grouping by level, rows with costs; money text.
local ns, eq = ...
local Trainer, Util = ns.Trainer, ns.Util

eq(Util.Money(0), "0c", "money: zero")
eq(Util.Money(120), "1s 20c", "money: silver")
eq(Util.Money(12000), "1g 20s", "money: zero copper left out")
eq(Util.Money(10005), "1g 5c", "money: zero silver left out")

local store = {}
Trainer.Merge(store, {
  { name = "Hunter Skills", status = "header" },
  { name = "Arcane Shot", rank = "Rank 2", status = "available", level = 12, cost = 200 },
  { name = "Serpent Sting", rank = "Rank 2", status = "available", level = 10, cost = 100 },
  { name = "Raptor Strike", rank = "Rank 1", status = "used", level = 1, cost = 10 },
  { name = "Concussive Shot", status = "unavailable", level = 13, cost = 400 },
  { name = "Multi-Shot", rank = "Rank 1", status = "unavailable", level = 18, cost = 2000 },
}, 100)
eq(ns.Util.Count(store.list), 5, "merge: headers skipped")
eq(store.when, 100, "merge: time stored")

local g = Trainer.Groups(store, 12)
eq(#g.now, 2, "groups: learnable now")
eq(g.now[1].name, "Serpent Sting", "groups: sorted by level")
eq(g.costNow, 300, "groups: cost now")
eq(#g.soon, 1, "groups: next two levels")
eq(g.costSoon, 400, "groups: cost soon")
eq(#g.later, 1, "groups: later")
eq(g.learned, 1, "groups: learned counted")

-- second visit: learned spell updates, nothing duplicates
Trainer.Merge(store, { { name = "Serpent Sting", rank = "Rank 2", status = "used", level = 10, cost = 100 } }, 200)
eq(ns.Util.Count(store.list), 5, "merge: no duplicate")
eq(#Trainer.Groups(store, 12).now, 1, "merge: learned leaves the list")

local rows = Trainer.Rows(store, 12, "level", 150)
eq(#rows, 4, "rows: two headers and two entries")
eq(rows[1].header ~= nil, true, "rows: header first")
eq(rows[2].entry.name, "Arcane Shot (Rank 2)", "rows: name with rank")
eq(rows[2].entry.note, "2s", "rows: cost as note")
eq(rows[2].entry.status[1], "too expensive", "rows: not affordable with 1s 50c")
eq(rows[4].entry.status[1], "from level 13", "rows: upcoming level")
eq(#Trainer.Rows(store, 12, "all", 150), 6, "rows: all levels adds later")
eq(#Trainer.Rows({}, 12, "level"), 0, "rows: empty store")
