# ClassPages – Klassenseiten (Datenformat)

Jede Klasse kann beliebig viele eigene Tabs („Seiten“) mitbringen. Eine Seite ist reine Daten. Das Addon rendert alle Seiten einheitlich:

- Stufenfilter: „Für meine Stufe“ oder „Alle“.
- Bereiche als Zwischenüberschriften.
- Eine Zeile je Eintrag mit Symbol, Name, Stufe, Zone und Notiz.
- Live-Status rechts: „gelernt“, „3 im Inventar“, „erledigt“, „fehlt“.

## Datei und Registrierung
`ClassPages/Classes/Data/<KLASSE>.lua`, eingetragen in `ClassPages.toc` nach `Classes\Registry.lua`:
```lua
local ADDON, ns = ...
ns.Classes:AddPage("MAGE", {
  key = "mageQuests",                 -- eindeutig über alle Klassen, camelCase
  title = { enUS = "Class quests & items", deDE = "Klassenquests & Gegenstände" },
  icon = "Interface\\Icons\\INV_Misc_Book_11",
  order = 40,                         -- Tab-Reihenfolge (Übersicht 10, Talente 20, Klassenseiten 30–80, HUD 90)
  intro = { enUS = "...", deDE = "..." },   -- ein Satz, worum es geht
  sections = {
    { title = { enUS = "Level 1–20", deDE = "Stufe 1–20" }, entries = { ... } },
  },
})
```

## Eintrag
| Feld | Pflicht | Bedeutung |
|---|---|---|
| `kind` | ja | `"item"`, `"spell"`, `"quest"`, `"pet"`, `"profession"`, `"note"` |
| `name` | ja | `{ enUS = "...", deDE = "..." }`. Bei `item`/`spell` mit ID wird der Name live aus dem Spiel gelesen; `name` ist nur Ersatz. |
| `minLevel` | ja | 1–60 |
| `maxLevel` | nein | Ende des sinnvollen Bereichs (Standard 60) |
| `itemID` | bei `item` empfohlen | Nur wenn sicher bekannt (Classic-ID). Sonst weglassen. |
| `spellID` | bei `spell` empfohlen | Rang-1-ID, nur wenn sicher bekannt |
| `questID` | nein | Nur wenn sicher bekannt; dann wird „erledigt“ live geprüft |
| `zone` | nein | `{ enUS = "Elwynn Forest", deDE = "Wald von Elwynn" }` |
| `family` | bei `pet` | englischer Familienname wie in `Classes/HunterPets.lua` (`"Cat"`, `"Wolf"`, …) |
| `note` | ja | `{ enUS = "...", deDE = "..." }`, kurz (max. ~110 Zeichen), eigener Wortlaut |
| `tags` | nein | Liste aus `"rare"`, `"elite"`, `"reagent"`, `"quest"`, `"weapon"`, `"unique"`, `"profession"` |
| `confidence` | ja | `"A"` (Forever bestätigt), `"B"` (Classic-Fakt, für Forever wahrscheinlich), `"C"` (unsicher) |

## Regeln
- Nur Fakten, eigener Wortlaut. Keine Texte, Tabellen oder Datenbanken aus anderen Addons (OneForAll, Questie) oder Seiten (Wowhead, Petopia) kopieren.
- IDs nur, wenn sicher. Eine falsche ID ist schlechter als keine.
- Forever hat Klassen verändert (z. B. Jäger-Talente, neue Pet-Familie Fuchs). Was nur aus Classic stammt, bekommt `confidence = "B"` und wird in der Anzeige mit `~` markiert.
- Deutsch mit den Begriffen des deutschen Clients.
- Kurz und prägnant: Tab-Titel höchstens 12 Zeichen, Bereichstitel 24, Einleitung 90, Notiz 110, selbst gewählte Namen 40.
- `tools/tests/classdata_test.lua` prüft jede Seite: Pflichtfelder, Stufen 1–60, beide Sprachen, eindeutige Keys, Feldtypen.
