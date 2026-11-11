--[[ Classes/Data/HUNTER.lua
Purpose : Hunter class pages (tameable beasts, quests & gear), pure data.
API     : ns.Classes:AddPage("HUNTER", {...}) - format in docs/04-KLASSENSEITEN.md
Data    : static; no saved variables. Facts in own words, checked against Classic sources
          (Petopia Classic, warcraft.wiki.gg, Warcraft Tavern); Classic-derived = confidence B.
]]
local ADDON, ns = ...

-- Entry builders (pure Lua, no game API).
local function Z(en, de) return { enUS = en, deDE = de or en } end

-- level: a number, or { min, max } for a creature level range.
local function pet(nameEn, nameDe, family, level, zone, note, conf, tags)
  local lo, hi = level, nil
  if type(level) == "table" then lo, hi = level[1], level[2] end
  return {
    kind = "pet", name = Z(nameEn, nameDe), family = family, minLevel = lo, maxLevel = hi,
    zone = zone, note = note, tags = tags, confidence = conf or "B",
  }
end

local function item(nameEn, nameDe, level, itemID, note, conf, tags)
  return {
    kind = "item", name = Z(nameEn, nameDe), minLevel = level, itemID = itemID,
    note = note, tags = tags, confidence = conf or "B",
  }
end

local function quest(nameEn, nameDe, level, note, conf, tags)
  return {
    kind = "quest", name = Z(nameEn, nameDe), minLevel = level,
    note = note, tags = tags or { "quest" }, confidence = conf or "B",
  }
end

local BA = Z("The Barrens", "Brachland")
local DU = Z("Durotar", "Durotar")
local MU = Z("Mulgore", "Mulgore")
local DW = Z("Duskwood", "Dämmerwald")
local STV = Z("Stranglethorn Vale", "Schlingendorntal")
local TN = Z("Thousand Needles", "Tausend Nadeln")
local UG = Z("Un'Goro Crater", "Krater von Un'Goro")
local WS = Z("Winterspring", "Winterquell")
local AS = Z("Ashenvale", "Eschental")
local DS = Z("Darkshore", "Dunkelküste")
local DM = Z("Dustwallow Marsh", "Düstermarschen")
local BS = Z("Burning Steppes", "Brennende Steppe")
local TE = Z("Teldrassil", "Teldrassil")
local BL = Z("Badlands", "Ödland")
local AM = Z("Alterac Mountains", "Alteracgebirge")
local FE = Z("Feralas", "Feralas")
local HI = Z("The Hinterlands", "Hinterland")
local BFD = Z("Blackfathom Deeps", "Tiefschwarze Grotte")
local BRS = Z("Blackrock Spire", "Schwarzfelsspitze")

ns.Classes:AddPage("HUNTER", {
  key = "hunterTames",
  title = { enUS = "Beasts", deDE = "Tiere" },
  icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
  order = 35,
  intro = {
    enUS = "Beasts worth taming per level: looks, speed or ability ranks.",
    deDE = "Lohnende Tiere je Stufe: Aussehen, Tempo oder Fähigkeitsränge.",
  },
  sections = {
    { title = Z("Level 1–20", "Stufe 1–20"), entries = {
      pet("Echeyakee", nil, "Cat", 16, BA,
        Z("White lion that only appears through a Horde quest in the Barrens; a classic showpiece pet.", "Weißer Löwe, der nur durch eine Horde-Quest im Brachland erscheint; klassisches Schmuckstück."), "B"),
      pet("Sarkoth", nil, "Scorpid", 4, DU,
        Z("Weak scorpid by the Valley of Trials; teaches the first Claw rank.", "Schwacher Skorpid beim Tal der Prüfungen; lehrt den ersten Klaue-Rang."), "B"),
      pet("Mazzranache", nil, "Tallstrider", 9, MU,
        Z("Rare pink tallstrider, one of the earliest rare looks; also teaches Cower 1.", "Seltener rosa Läufer, eines der frühesten seltenen Aussehen; lehrt außerdem Kauern 1."), "B", { "rare" }),
      pet("Prairie Wolf", nil, "Wolf", { 5, 6 }, MU,
        Z("Easy early wolf; teaches Bite rank 1.", "Leichter früher Wolf; lehrt Biss Rang 1."), "B"),
      pet("Strigid Owl", nil, "Owl", { 5, 6 }, TE,
        Z("Early owl; teaches Claw rank 1.", "Früher Uhu; lehrt Klaue Rang 1."), "B"),
      pet("Ghost Saber", nil, "Cat", { 19, 20 }, DS,
        Z("Ghostly white cat that is summoned by opening cat figurines in the ruins; teaches Claw 3.", "Geisterhafte weiße Katze, die durch das Öffnen von Katzenfiguren in den Ruinen erscheint; lehrt Klaue 3."), "B"),
      pet("Takk the Leaper", nil, "Raptor", 19, BA,
        Z("Rare elite raptor around the Sludge Fen; needs a strong group or a pet to hold it.", "Seltener Elite-Raptor am Schlammfenn; braucht eine starke Gruppe oder ein Tier zum Halten."), "B", { "rare", "elite" }),
    } },
    { title = Z("Level 20–30", "Stufe 20–30"), entries = {
      pet("Humar the Pridelord", nil, "Cat", 23, BA,
        Z("Rare black lion on the cliffs above Ratchet; long respawn.", "Seltener schwarzer Löwe auf den Klippen über Ratchet; lange Wiederkehrzeit."), "B", { "rare" }),
      pet("Lupos", nil, "Wolf", 23, DW,
        Z("Rare wolf roaming the Brightwood Grove area; teaches Bite 3.", "Seltener Wolf im Gebiet des Brightwood-Hains; lehrt Biss 3."), "B", { "rare" }),
      pet("Mist Howler", nil, "Wolf", 22, AS,
        Z("Rare wolf that teaches Furious Howl rank 1.", "Seltener Wolf, der Wildes Heulen Rang 1 lehrt."), "B", { "rare" }),
      pet("Naraxis", nil, "Spider", 27, DW,
        Z("Rare red spider with a unique look; teaches Bite 4.", "Seltene rote Spinne mit einzigartigem Aussehen; lehrt Biss 4."), "B", { "rare" }),
      pet("Elder Ashenvale Bear", nil, "Bear", { 25, 26 }, AS,
        Z("Sturdy bear that teaches Claw rank 4.", "Robuster Bär, der Klaue Rang 4 lehrt."), "B"),
      pet("Aku'mai Snapjaw", nil, "Turtle", { 26, 27 }, BFD,
        Z("Dungeon turtle that teaches Shell Shield, a strong defensive skill.", "Turtle im Dungeon, der Panzerschild lehrt, eine starke Defensivfähigkeit."), "B"),
      pet("Cloud Serpent", nil, "Wind Serpent", { 25, 26 }, TN,
        Z("Wind serpent that teaches Lightning Breath rank 3.", "Windnatter, die Blitzatem Rang 3 lehrt."), "B"),
    } },
    { title = Z("Level 30–40", "Stufe 30–40"), entries = {
      pet("Broken Tooth", nil, "Cat", 37, BL,
        Z("Rare cat with 1.0 attack speed, the fastest of any pet. Teaches Dash 1. Long respawn.", "Seltene Katze mit Angriffstempo 1,0, dem schnellsten aller Tiere. Lehrt Spurt 1. Lange Wiederkehrzeit."), "B", { "rare" }),
      pet("Sin'Dall", nil, "Cat", 37, STV,
        Z("Legendary tiger north of Grom'gol; teaches Dash 1.", "Legendäre Tigerin nördlich von Grom'gol; lehrt Spurt 1."), "B"),
      pet("Bhag'thera", nil, "Cat", 40, STV,
        Z("Elite panther in Bambala; teaches Dash 2.", "Elite-Panther in Bambala; lehrt Spurt 2."), "B", { "elite" }),
      pet("Shadowmaw Panther", nil, "Cat", { 37, 38 }, STV,
        Z("Black panther that teaches Prowl rank 1.", "Schwarzer Panther, der Schleichen Rang 1 lehrt."), "B"),
      pet("Mistvale Gorilla", nil, "Gorilla", { 32, 33 }, STV,
        Z("Heavy-hitting gorilla that teaches Thunderstomp rank 1.", "Starker Gorilla, der Donnerstampfer Rang 1 lehrt."), "B"),
      pet("Scorpid Terror", nil, "Scorpid", { 33, 34 }, TN,
        Z("Scorpid that teaches Scorpid Poison rank 2.", "Skorpid, der Skorpidgift Rang 2 lehrt."), "B"),
      pet("Araga", nil, "Cat", 35, AM,
        Z("Rare cat with a brown and tan coat found nowhere else.", "Seltene Katze mit braun-beigem Fell, das es sonst nirgends gibt."), "B", { "rare" }),
    } },
    { title = Z("Level 40–50", "Stufe 40–50"), entries = {
      pet("Snarler", nil, "Wolf", 42, FE,
        Z("Rare wolf; teaches Bite 6 and Furious Howl rank 3.", "Seltener Wolf; lehrt Biss 6 und Wildes Heulen Rang 3."), "B", { "rare" }),
      pet("Old Cliff Jumper", nil, "Wolf", 42, HI,
        Z("Rare dark grey worg; teaches Bite 6 and Dash 2.", "Seltener dunkelgrauer Worg; lehrt Biss 6 und Spurt 2."), "B", { "rare" }),
      pet("Elder Shadowmaw Panther", nil, "Cat", { 42, 43 }, STV,
        Z("Black panther that teaches Prowl rank 2 and Dash 2.", "Schwarzer Panther, der Schleichen Rang 2 und Spurt 2 lehrt."), "B"),
      pet("King Bangalash", nil, "Cat", 43, STV,
        Z("Elite white tiger; teaches Dash 2 and Claw 6.", "Weißer Elite-Tiger; lehrt Spurt 2 und Klaue 6."), "B", { "elite" }),
      pet("Ironfur Bear", nil, "Bear", { 41, 42 }, FE,
        Z("Bear that teaches Claw rank 6.", "Bär, der Klaue Rang 6 lehrt."), "B"),
      pet("Hayoc", nil, "Wind Serpent", 41, DM,
        Z("Rare white wind serpent.", "Seltene weiße Windnatter."), "B", { "rare" }),
      pet("Arash-ethis", nil, "Wind Serpent", 49, FE,
        Z("Rare white wind serpent; teaches Lightning Breath 5 and Dive 2.", "Seltene weiße Windnatter; lehrt Blitzatem 5 und Sturzflug 2."), "B", { "rare" }),
    } },
    { title = Z("Level 50–60", "Stufe 50–60"), entries = {
      pet("Rak'shiri", nil, "Cat", 57, WS,
        Z("Rare frostsaber near Frostsaber Rock; teaches Dash 3.", "Seltener Frostsäbler nahe dem Frostsäblerfelsen; lehrt Spurt 3."), "B", { "rare" }),
      pet("Deathmaw", nil, "Wolf", 53, BS,
        Z("Rare wolf with a striking coat; long respawn.", "Seltener Wolf mit auffälligem Fell; lange Wiederkehrzeit."), "B", { "rare" }),
      pet("Uhk'loc", nil, "Gorilla", 52, UG,
        Z("Rare white gorilla in Fungal Rock; teaches Bite 7.", "Seltener weißer Gorilla im Pilzfelsen; lehrt Biss 7."), "B", { "rare" }),
      pet("Un'Goro Thunderer", nil, "Gorilla", { 52, 53 }, UG,
        Z("Gorilla that teaches Thunderstomp rank 3, the highest.", "Gorilla, der Donnerstampfer Rang 3 lehrt, den höchsten."), "B"),
      pet("Elder Shardtooth", nil, "Bear", { 57, 58 }, WS,
        Z("Bear that teaches Claw rank 8, the highest.", "Bär, der Klaue Rang 8 lehrt, den höchsten."), "B"),
      pet("Frostsaber Stalker", nil, "Cat", { 59, 60 }, WS,
        Z("Frostsaber that teaches Prowl rank 3 and Dash 3.", "Frostsäbler, der Schleichen Rang 3 und Spurt 3 lehrt."), "B"),
      pet("Bloodaxe Worg", nil, "Wolf", { 56, 57 }, BRS,
        Z("Dungeon worg that teaches the top ranks of Bite 8, Furious Howl 4 and Dash 3.", "Worg im Dungeon, der die höchsten Ränge von Biss 8, Wildes Heulen 4 und Spurt 3 lehrt."), "B"),
    } },
  },
})

ns.Classes:AddPage("HUNTER", {
  key = "hunterQuests",
  title = { enUS = "Quests", deDE = "Quests" },
  icon = "Interface\\Icons\\INV_Weapon_Bow_07",
  order = 45,
  intro = {
    enUS = "Class quests, quivers, ammo and handy items up to 60.",
    deDE = "Klassenquests, Köcher, Munition und Nützliches bis Stufe 60.",
  },
  sections = {
    { title = Z("Class quests", "Klassenquests"), entries = {
      quest("Taming the Beast", nil, 10,
        Z("Level-10 chain from your trainer: tame three beasts with the taming rod; unlocks Tame Beast.", "Questreihe auf Stufe 10 vom Lehrer: drei Tiere mit dem Zähmstab zähmen; schaltet Wildtier zähmen frei."), "B"),
      quest("Training the Beast", nil, 10,
        Z("Final step in your capital; teaches Beast Training, Feed Pet and Revive Pet.", "Letzter Schritt in deiner Hauptstadt; lehrt Wildtierausbildung, Tier füttern und Tier wiederbeleben."), "B"),
      quest("Vyrin's Revenge", nil, 15,
        Z("Alliance quest in Loch Modan; rewards the Hunting Quiver or the Hunting Ammo Sack.", "Allianz-Quest in Loch Modan; belohnt mit dem Jagdköcher oder dem Jagdmunitionssack."), "B"),
      quest("The Night Watch", nil, 18,
        Z("Alliance quest in Duskwood; rewards a quiver or ammo pouch with more slots.", "Allianz-Quest im Dämmerwald; belohnt mit einem Köcher oder Munitionsbeutel mit mehr Plätzen."), "B"),
      quest("The Ancient Leaf", nil, 60,
        Z("Start of the long Rhok'delar chain; begins by using the Ancient Petrified Leaf from Molten Core.", "Beginn der langen Rhok'delar-Reihe; startet mit dem Ancient Petrified Leaf aus dem Geschmolzenen Kern."), "B", { "quest", "weapon", "unique" }),
    } },
    { title = Z("Ammo & quivers", "Munition & Köcher"), entries = {
      item("Light Quiver", nil, 1, 2101,
        Z("Starter quiver with 6 slots, part of hunter starting gear.", "Startköcher mit 6 Plätzen, Teil der Jäger-Startausrüstung."), "B"),
      item("Small Ammo Pouch", nil, 1, 2102,
        Z("Starter ammo pouch with 6 slots for gun users.", "Start-Munitionsbeutel mit 6 Plätzen für Schusswaffen."), "B"),
      item("Hunting Quiver", nil, 10, 3573,
        Z("10-slot quiver, reward of Vyrin's Revenge in Loch Modan (Alliance).", "Köcher mit 10 Plätzen, Belohnung von Vyrin's Revenge in Loch Modan (Allianz)."), "B"),
      item("Heavy Quiver", nil, 30, 7371,
        Z("14-slot quiver crafted by leatherworkers (skill 150).", "Köcher mit 14 Plätzen, von Lederern hergestellt (Fertigkeit 150)."), "B"),
      item("Quickdraw Quiver", nil, 40, 8217,
        Z("16-slot quiver crafted by leatherworkers (skill 225).", "Köcher mit 16 Plätzen, von Lederern hergestellt (Fertigkeit 225)."), "B"),
      item("Ribbly's Quiver", nil, 50, 2662,
        Z("16-slot quiver dropped by Ribbly Screwspigot in Blackrock Depths.", "Köcher mit 16 Plätzen, Drop von Ribbly Screwspigot in den Schwarzfelstiefen."), "B"),
      item("Thick Leather Ammo Pouch", nil, 40, 8218,
        Z("16-slot ammo pouch crafted by leatherworkers (skill 225).", "Munitionsbeutel mit 16 Plätzen, von Lederern hergestellt (Fertigkeit 225)."), "B"),
      item("Jagged Arrow", nil, 40, 11285,
        Z("Mid-to-late arrow ammunition.", "Pfeilmunition für die mittleren bis späten Stufen."), "C"),
      item("Thorium Headed Arrow", nil, 55, 18042,
        Z("Strong arrow ammunition for the final levels.", "Starke Pfeilmunition für die letzten Stufen."), "B"),
    } },
    { title = Z("Useful items", "Nützliche Gegenstände"), entries = {
      item("Rhok'delar, Longbow of the Ancient Keepers", nil, 60, 18713,
        Z("Epic bow created at the end of the level-60 hunter chain.", "Epischer Bogen, am Ende der Stufe-60-Jägerreihe hergestellt."), "B", { "weapon", "unique" }),
      item("Ancient Petrified Leaf", nil, 60, 18703,
        Z("Starts the Rhok'delar chain; drops from the Cache of the Firelord in Molten Core.", "Startet die Rhok'delar-Reihe; Drop aus dem Cache of the Firelord im Geschmolzenen Kern."), "B", { "quest", "unique" }),
      item("Ancient Sinew Wrapped Lamina", nil, 60, 18714,
        Z("18-slot quiver, reward of the chain's quest of the same name; adds ranged attack speed.", "Köcher mit 18 Plätzen, Belohnung der gleichnamigen Quest der Reihe; erhöht das Fernkampftempo."), "B", { "quest", "unique" }),
    } },
  },
})
