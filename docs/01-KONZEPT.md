# ClassPages – Konzept

Stand: 09.11.2026 · Zielclient: World of Warcraft: Forever 1.60.x (Interface 16001)

## 1. Ziel
Zwei Kerne:
1. **Klassenfenster** (`/cp`): Pro Klasse alle relevanten Inhalte in Tabs. Generisch für jede Klasse: Übersicht, Talentplaner, HUD. Klassenspezifisch über das Klassenprofil, beim Jäger der Tab „Begleiter“ (aktives Pet, Zufriedenheit, Treue, Trainingspunkte, Ernährung, Fähigkeiten, Wildtierausbildung, Stall, Familien).
2. **HUD**: Beliebig viele eigene Aktionsleisten mit freier Größe, Position, Spalten-/Reihenzahl, Skalierung und Transparenz. Jede Leiste hat eine **Inhaltsart** (Angriffe, Hilfsmittel, Begleiter, Berufe, Gegenstände, Frei), die festlegt, welche Timer und Hervorhebungen sinnvoll sind. Berufe blitzen nie „bereit“, zeigen aber eine Abklingzeit, wenn die Quelle eine hat (z. B. Transmutation).

## 2. Rechercheergebnisse (Vertrauensgrad A bestätigt · B wahrscheinlich · C unsicher)
| Thema | Ergebnis | Grad | Folge |
|---|---|---|---|
| Secret Values auf Forever | Midnight-Regeln gelten (Goldweaver-Recherche, Warcraft Wiki 12.0). Cooldowns sind im Kampf geheim, `Cooldown:SetCooldown`/`SetCooldownFromDurationObject` nehmen Secrets an, `isActive` ist seit 12.0.1 nicht geheim. | B | Timer-Anzeige über Widgets; Bereit-Blitz über `isActive` mit Zeitfilter gegen den GCD; ohne lesbaren Wert bleibt der Blitz aus. `/cp probe` misst live. |
| Talent-API | Forever nutzt die Trait-API (`C_ClassTalents.InitializeViewLoadout(specID, 60)`, `C_Traits.*`) für die drei klassischen Bäume. Belegt durch den Code von OneForAll Forever. | B | Reader mit zwei Backends (Traits, klassisch); Layout wird live gelesen und gecacht, nichts hartkodiert. |
| Talente Jäger | Drei Bäume, Stufen 11/16/21/31-Punkte-Talente, Dual-Spec ab 40, viele neue Talente (z. B. Sniper Shot, Lone Wolf). Konterattacke ist ein 16-Punkte-Talent in Überleben. | A | Planer arbeitet mit Live-Daten, kein Talentkatalog im Addon. |
| Pets | Klassisches System (Zufriedenheit, Treue, Trainingspunkte), Wildtierausbildung im Craft-Fenster, Stall über `C_StableInfo`/`GetStablePetInfo`, Pet-Zauber über `C_SpellBook`. Neue Familie Fuchs, Eule heißt Raubvogel. | B/C | Live-Snapshots; Familienfakten klein und überschreibbar durch Beobachtung. |
| Aktionsleisten-Addons | Bartender4, Dominos und ElvUI laufen auf Forever. WeakAuras und OmniCC laufen nicht. Der Blizzard Cooldown Manager ist vorhanden, aber standardmäßig aus. | B | Wir bauen auf **LibActionButton-1.0** auf (Basis von Bartender4): BSD-Lizenz, die TOC listet 16001, unterstützt DurationObjects, Usable-State, Reichweite und Drag & Drop. |
| Proc-Glow | LAB zeigt Proc-Glows nur mit LibButtonGlow an. | A (Quellcode) | Eigene Behandlung von `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` über Blizzards `ActionButtonSpellAlertManager`, sonst über eine eigene Leuchttextur. |
| OneForAll Forever | All-in-One, GPL-3. Pet- und Talentdaten stammen aus Fremdquellen (Petopia, talentsforever.com). | A | Nur als Ideengeber. Kein Code und keine Daten übernommen. |

Quellen: Warcraft Wiki (Secret Values, Patch 12.0.0/12.0.1 API changes), Blizzard „Forever Class Deep Dive: Hunter and Druid“, OneForAll_Forever-Quellcode, LibActionButton-1.0-Quellcode, kami-labs.fr (Addon-Kompatibilität Forever), warcrafttavern.com (Pets).

## 3. Entscheidungen
1. **Nichts von Grund auf neu:** Knöpfe aus LibActionButton (wie Bartender4), Blizzard-Widgets für Cooldowns, Blizzard-Alert-Manager für Procs, Masque-Unterstützung automatisch, wenn installiert.
2. **Eigene dünne Schicht** nur dort, wo es nichts gibt: Leistenmodell mit Inhaltsarten, Bereit-Blitz, Reaktiv-Leuchten (Konterattacke, Mungobiss), Pet-Knöpfe (LAB kennt `pet` nicht), Bearbeitungsmodus.
3. **Live vor hartkodiert:** Talente, Zauberränge (Basis-ID → höchster bekannter Rang über den lokalisierten Namen), Pet-Zustand, Stall und Wildtierausbildung werden gelesen. Statische Daten sind nur Startwerte.
4. **Robustheit:** Fähigkeiten statt Versionen prüfen, Fehler isolieren (pro Handler, pro Modul, pro Tab), Daten nie zurücksetzen, Migrationen mit Backup, Sanitize beim Laden, geschützte Änderungen nach dem Kampf.

## 4. Bedienung
- `/cp` öffnet das Klassenfenster. Tabs: Übersicht · Talente · Begleiter (Jäger) · HUD.
- Erster Login legt die Vorlagen-Leisten der Klasse an (Jäger: Schüsse, Nahkampf & Reaktiv, Begleiter, Fallen & Aspekte; aus: Begleiterpflege, Abklingzeiten, Berufe). Nur bekannte Zauber werden eingetragen.
- Zauber, Gegenstände und Makros per Drag & Drop auf Leisten ziehen; Shift+Ziehen nimmt einen Knopf herunter.
- Bearbeitungsmodus (Minimap-Rechtsklick, „Im Spiel verschieben“ oder `/cp unlock`), aufgebaut wie Blizzards Edit Mode:
  - Werkzeugleiste oben mit „+ Neue Leiste“, „Raster einrasten“ und „Fertig“.
  - Leiste anklicken öffnet ein Popover: −/+ für Spalten, Reihen, Größe und Abstand, dazu „Weitere Einstellungen“, „Ausblenden“ und „Löschen“ mit Bestätigung.
  - Ziehen verschiebt (rastet auf 8 px ein), der Eckgriff ändert Spalten und Reihen, das Mausrad ändert die Spalten.
- HUD-Tab:
  - Links die Leistenliste mit Augen-Schalter, „+ Neue Leiste“ mit Inhaltsart und die Vorlagen der Klasse als Chips. Gelöschte Vorlagen kommen mit einem Klick zurück.
  - Rechts der Editor mit Live-Vorschau, Steppern, Timer-Schaltern (grau = wie die Inhaltsart) und Aktionen.
- Je Leiste drei Abschnitte im HUD-Tab: Raster, Timer, Sichtbarkeit (nur im Kampf, nur mit Ziel, je Haltung, bei Mouseover).
- Tasten belegen mit `/cp keys`: Maus über Knopf, Taste drücken. Die Belegung gehört zur Leiste und ändert die Tastenbelegung des Spiels nicht.
- Tab „Lehrer“: merkt sich jeden Lehrerbesuch und zeigt, was jetzt und bald lernbar ist, mit Kosten.
- Talentplan mit Reihenfolge: „Als Nächstes“ zeigt den nächsten Punkt laut Plan.
- Leere Leisten zeigen ihre Plätze und den Hinweis „Zauber hierher ziehen“, bis der erste Knopf darauf liegt.
- Profile: `/cp profile` (pro Charakter, kopierbar), `/cp backup`, `/cp restore confirm`.

## 5. Ausbau (nächste Schritte)
- Tastenbelegung für eigene Leisten (LibKeyBound oder eigener Bindungsmodus).
- Weitere Klassenprofile (`Classes/<Klasse>.lua`): Spells, Reaktive, Vorlagen, Klassentabs.
- Auto-Shot-Timer über Forevers nativen Swing-Timer (nur, wenn ohne Combat-Log lesbar).
- Talentplan: nächster zu lernender Punkt in der Übersicht, Dual-Spec-Pläne.
