# ClassPages – Architektur und Erweiterung

## 1. Schichten (TOC-Reihenfolge = Abhängigkeitsrichtung)
```
Libs/       LibStub · CallbackHandler-1.0 · LibActionButton-1.0 (unverändert eingebettet)
Locales/    enUS (Sprachkern, ns.L) · deDE
Core/       Init (Module, Slash) · Util · Secret · Events (Secret-Guard, Fehlerisolation) · API (Features)
            DB (Schema, Migrationen, Backup, Profile) · Combat (Queue für geschützte Änderungen) · Spellbook (Rang-Auflösung)
Classes/    Registry (Profil-Vertrag, Generic-Fallback) · Guide (Klassenseiten) · Trainer (Lehrerbuch) · Hunter · HunterPets · Data/<KLASSE>
HUD/        Kinds (Inhaltsarten) · Model (rein: Sanitize, Layout, Sichtbarkeit, Tasten) · Content (Vorlagen, Drag&Drop-Abbildung)
            Highlight (Bereit-Blitz, Reaktiv, Zähler) · PetButton · Bars (Laufzeit, LAB) · Mover (Bearbeitungsmodus) · Binder (Tastenmodus)
            Blizzard (Spielleisten ausblenden: Haupt-, Begleiter-, Haltungsleiste)
Talents/    Model (rein: Knoten → 3 Bäume) · Planner (rein: Regeln, Export) · Reader (Traits / klassisch) · Talents (Cache, Pläne)
Media/      eigenes Grafikset (weiße Formen, per Farbe getönt): Flächen, Ränder, Schatten, Verläufe, Symbole
UI/         Kit (Stile, 9-Slice, Widgets) · Window (Tabs) · TabOverview · TabTalents · TabPets · TabHUD · TabGuide · TabTrainer · Minimap
Modules/    Probe (Live-Messung) · Debug (Bericht)
```

## 2. Modul-Vertrag
```lua
local ADDON, ns = ...
ns:RegisterModule("Name", {
  Init = function() end,      -- nach ADDON_LOADED (ns.db, ns.cdb, ns.profile bereit), Events hier anmelden
  Login = function() end,     -- PLAYER_LOGIN (Zauberbuch, Klasse, Talente bekannt)
  SelfTest = function() return { { name = "...", ok = true, warn = false, detail = "..." } } end,
})
```
Jeder Hook läuft isoliert (`pcall`). Ein defektes Modul wird gemeldet, die anderen laufen weiter.

## 3. Erweiterungspunkte
| Was | Wo | Wie |
|---|---|---|
| Neue Klasse | `Classes/<Klasse>.lua` | `ns.Classes:Register{ class, color, icon, spells = {key = baseID}, reactive, presets, tabs, overview }`, TOC-Eintrag |
| Klassenseite (Daten) | `Classes/Data/<KLASSE>.lua` | `ns.Classes:AddPage(class, { key, title, order, sections = {...} })`, Format in `docs/04-KLASSENSEITEN.md`; erscheint automatisch als Tab |
| Klassen-Tab mit eigener Logik | `UI/Tab<Name>.lua` | `ns.UI.RegisterTab(key, title, builder, { classTab = true, order })`, Key in `profile.tabs` |
| Neue Inhaltsart | `HUD/Kinds.lua` oder Klassenprofil | `ns.HUD.Kinds.Register(key, { title, defaults = { cooldown, readyFlash, reactive, procGlow, range, hideOOC } })` |
| Neuer Vorlagen-Generator | `HUD/Content.lua` | `ns.HUD.Content.generators[name] = function(preset) return { {type, id} } end` |
| Neues Feature-Gate | `Core/API.lua` | `Features.Define(name, { label, requires })`, im Modul `Features.Available(name)` |
| Slash-Befehl | eigenes Modul | `ns.Slash.Register(cmd, fn, help)` |

## 4. Datensicherheit
1. `applyDefaults` ergänzt nur fehlende Schlüssel. Unbekannte Schlüssel bleiben erhalten (Vorwärtskompatibilität).
2. Migrationen sind nummeriert, additiv und idempotent und laufen mit einem Backup vorab (`ClassPagesBackupDB`). Eine neuere Datenbank wird nicht angefasst.
3. Löschen und Zurücksetzen (Leiste, Profil, Talentplan) legen vorher ein Backup an. Zurück mit `/cp restore confirm`.
4. Jede gelesene Leiste läuft durch `Model.Sanitize`: Typen, Wertebereiche, Anker und Knöpfe werden repariert. Knöpfe außerhalb des Rasters bleiben erhalten.
5. Zauber werden mit ihrer Basis-ID gespeichert und zur Laufzeit auf den höchsten bekannten Rang aufgelöst. Neue Ränge brauchen keine Änderung.
6. Der Talentbaum-Cache wird bei neuem Client-Build neu gelesen. Pläne bleiben erhalten.

## 5. Tests
- `tools/tests/*_test.lua` (Unit): HUD-Modell, Bereit-Blitz-Zustandsmaschine, Talentregeln und Trait-Layout, DB/Migration/Profile, Vorlagen/Rang-Auflösung/Pets, Lokalisierung.
- `tools/tests/sim.lua` (Sitzungen, je „modern“ und „minimal“) deckt ab:
  - Erstinstallation, zweiter Login mit beschädigter Leiste, andere Klasse, neuer Client-Build.
  - Kampf mit geheimen Werten (Sentinel, jeder Vergleich wirft) und geschützte Aufrufe im Kampf (lassen den Lauf fehlschlagen).
  - Drag & Drop, Bearbeitungsmodus, alle Tabs, alle Slash-Befehle und der Debug-Bericht.
