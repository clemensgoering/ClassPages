-- Class data page: Priest quests/items and professions. Data only (see docs/04-KLASSENSEITEN.md).
local ADDON, ns = ...

local function e(kind, minLevel, en, de, noteEn, noteDe, conf, x)
  local t = { kind = kind, name = { enUS = en, deDE = de }, minLevel = minLevel,
    note = { enUS = noteEn, deDE = noteDe }, confidence = conf }
  if x then for k, v in pairs(x) do t[k] = v end end
  return t
end

ns.Classes:AddPage("PRIEST", {
  key = "priestQuests",
  title = { enUS = "Quests", deDE = "Quests" },
  icon = "Interface\\Icons\\INV_Misc_Book_11",
  order = 40,
  intro = { enUS = "Priest class quests, candles and important wands and consumables.",
            deDE = "Priesterklassenquests, Kerzen und wichtige Zauberstäbe und Verbrauchsgüter." },
  sections = {
    { title = { enUS = "Level 1–20", deDE = "Stufe 1–20" }, entries = {
      e("quest", 1, "Starter class quests", "Einstiegs-Klassenquests",
        "Your racial priest trainer gives the first quests; they lead to Power Word: Shield and Smite.",
        "Der Priesterlehrer deiner Rasse vergibt die ersten Quests; sie führen zu Machtwort: Schild und Heilige Pein.", "B", { tags = { "quest" } }),
      e("quest", 8, "Class quest for Power Word: Fortitude", "Klassenquest für Machtwort: Seelenstärke",
        "Early quest tied to your buffs; the exact quest changes by race.",
        "Frühe Quest rund um deine Segenszauber; die genaue Quest unterscheidet sich je nach Volk.", "C", { tags = { "quest" } }),
      e("quest", 10, "Shadow priest and healer training", "Training für Schatten und Heilung",
        "Around level 10, specs unlock; talk to your trainer for class quests.",
        "Um Stufe 10 werden Talentspezialisierungen verfügbar; beim Lehrer nach Klassenquests fragen.", "C", { tags = { "quest" } }),
      e("item", 1, "Wand", "Zauberstab",
        "Priests use wands to finish mobs; always keep one equipped to save mana.",
        "Priester nutzen Zauberstäbe zum Abschließen; immer einen tragen, um Mana zu sparen.", "B", { tags = { "weapon" } }),
    } },
    { title = { enUS = "Level 20–40", deDE = "Stufe 20–40" }, entries = {
      e("quest", 20, "Fear Ward and Dwarf priest chains", "Quests für Furchtzauberschutz",
        "Racial and class chains open abilities; Dwarves and Draenei get Fear Ward.",
        "Rassen- und Klassenquests schalten Fähigkeiten frei; Zwerge und Draenei erhalten Furchtzauberschutz.", "B", { tags = { "quest" } }),
      e("item", 20, "Holy Candle", "Heilige Kerze",
        "Reagent for Prayer of Fortitude and similar group spells; stock before dungeons.",
        "Reagenz für Gebet der Seelenstärke und ähnliche Gruppenzauber; vor Dungeons einkaufen.", "B",
        { itemID = 17028, tags = { "reagent" } }),
      e("quest", 30, "Level 30 class quests", "Klassenquests der Stufe 30",
        "Several mid-level spells are gated behind short trainer quests.",
        "Mehrere Zauber der mittleren Stufen hängen an kurzen Lehrerquests.", "C", { tags = { "quest" } }),
      e("item", 30, "Mana potions", "Manatränke",
        "Healers drink often; carry a few for long fights.",
        "Heiler trinken oft; für lange Kämpfe ein paar mitnehmen.", "B"),
    } },
    { title = { enUS = "Level 40–60", deDE = "Stufe 40–60" }, entries = {
      e("item", 48, "Sacred Candle", "Geweihte Kerze",
        "Reagent for Prayer of Spirit and advanced group buffs; stock a stack.",
        "Reagenz für Gebet der Willenskraft und fortgeschrittene Gruppensegen; Stapel mitführen.", "B",
        { itemID = 17029, tags = { "reagent" } }),
      e("quest", 60, "Dungeon set and class quest chains", "Dungeon-Set und Klassenquestreihen",
        "Level 60 chains reward gear; dungeon sets suit both healers and shadow.",
        "Questreihen auf Stufe 60 belohnen mit Ausrüstung; Dungeon-Sets passen zu Heilern wie zu Schatten.", "C", { tags = { "quest" } }),
      e("quest", 56, "Higher-level class quest", "Klassenquest für hohe Stufen",
        "Upper-level quests unlock healing improvements for dungeons.",
        "Quests hoher Stufen schalten Heilverbesserungen für Dungeons frei.", "C", { tags = { "quest" } }),
      e("item", 55, "Greater Mana Potion", "Großer Manatrank",
        "Instant mana for tough boss fights.",
        "Sofortiges Mana für harte Bosskämpfe.", "B"),
      e("item", 50, "Shadow resistance gear", "Schattenwiderstandsausrüstung",
        "Useful against Shadow-heavy bosses in upper dungeons.",
        "Nützlich gegen schattenlastige Bosse in hohen Dungeons.", "C"),
      e("note", 40, "Spirit and Intellect gear", "Willenskraft und Intelligenz",
        "Both stats help priests; keep drops that boost either.",
        "Beide Werte helfen Priestern; Drops mit einem von beiden aufheben.", "B"),
    } },
  },
})

ns.Classes:AddPage("PRIEST", {
  key = "priestProfessions",
  title = { enUS = "Professions", deDE = "Berufe" },
  icon = "Interface\\Icons\\Trade_BlackSmithing",
  order = 50,
  intro = { enUS = "Professions that suit a cloth-wearing healer or shadow caster.",
            deDE = "Berufe, die zu einem Stoff tragenden Heiler oder Schattenzauberer passen." },
  sections = {
    { title = { enUS = "Recommended", deDE = "Empfohlen" }, entries = {
      e("profession", 1, "Tailoring", "Schneiderei",
        "Craft your own cloth gear and bags; you will loot plenty of cloth.",
        "Eigene Stoffrüstung und Taschen herstellen; du plünderst reichlich Stoff.", "B", { tags = { "profession" } }),
      e("profession", 1, "Enchanting", "Verzauberkunst",
        "Disenchant cloth gear and enchant your own gear; good with Tailoring.",
        "Stoffausrüstung entzaubern und eigene verzaubern; gut mit Schneiderei.", "B", { tags = { "profession" } }),
      e("profession", 1, "Alchemy", "Alchemie",
        "Mana potions and elixirs for dungeons and raids.",
        "Manatränke und Elixiere für Dungeons und Raids.", "B", { tags = { "profession" } }),
      e("profession", 1, "Herbalism", "Kräuterkunde",
        "Pairs with Alchemy and sells well while questing.",
        "Passt zu Alchemie und verkauft sich beim Questen gut.", "B", { tags = { "profession" } }),
    } },
    { title = { enUS = "Collect", deDE = "Sammeln" }, entries = {
      e("item", 1, "Cloth", "Stoff",
        "Linen, wool, silk and mageweave feed Tailoring and bandages.",
        "Leinen, Wolle, Seide und Magiestoff versorgen Schneiderei und Verbände.", "B"),
      e("item", 1, "Wands", "Zauberstäbe",
        "Look for higher-damage wands; they replace spells to save mana.",
        "Auf Zauberstäbe mit mehr Schaden achten; sie sparen Mana statt Zauber.", "B", { tags = { "weapon" } }),
      e("item", 1, "Holy and Sacred Candles", "Heilige und Große Kerzen",
        "Keep both in bags; vendor-sold and used in group spells.",
        "Beide im Beutel halten; beim Händler erhältlich und für Gruppenzauber nötig.", "B", { tags = { "reagent" } }),
      e("note", 1, "Cloth gear with Spirit", "Stoffausrüstung mit Willenskraft",
        "Spirit speeds mana regeneration for healers; save drops that have it.",
        "Willenskraft beschleunigt die Manaregeneration; Drops damit aufheben.", "B"),
    } },
  },
})
