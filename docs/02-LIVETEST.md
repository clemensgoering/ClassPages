# ClassPages – Live-Test im Spiel

Die Junction ist angelegt (`_forever_\Interface\AddOns\ClassPages`). Vor dem Start: `/console scriptErrors 1`.

## A. Laden und Grundfunktion
1. Mit dem Jäger einloggen. Erwartet: Chatzeile „N Leisten für deine Klasse angelegt …“.
2. `/cp`: Fenster mit Übersicht · Talente · Begleiter · HUD. Jeden Tab einmal öffnen.
3. `/cp debug`: Bericht ohne `[FAIL]`/`[ERR]`-Zeilen. **Bei Problemen diesen Bericht komplett kopieren und weitergeben.**

## B. HUD
1. Die Leisten „Schüsse“, „Nahkampf & Reaktiv“, „Begleiter“ (nur mit Pet sichtbar) und „Fallen & Aspekte“ sind sichtbar und enthalten deine Zauber in höchstem Rang.
2. Einen Zauber mit Abklingzeit wirken (z. B. Arkaner Schuss): Sweep und Zahl laufen; am Ende blitzt der Knopf kurz (Bereit-Blitz). Nach GCD-only-Zaubern darf es **nicht** blitzen.
3. Konterattacke (falls geskillt): Nach einem Parieren leuchtet der Knopf, solange er nutzbar ist. Mungobiss nach einem Ausweichen des Gegners.
4. Minimap-Rechtsklick (oder `/cp unlock`) öffnet den Bearbeitungsmodus:
   - Oben erscheint die Werkzeugleiste.
   - Leiste anklicken: Das Popover erscheint, −/+ ändert die Leiste sofort.
   - Ziehen rastet ein, der Eckgriff ändert das Raster.
   - „Fertig“ beendet den Modus.
5. Regression: Im HUD-Tab alle Leisten löschen, „+ Neue Leiste“ anlegen. Die leere Leiste ist mit ihren Plätzen und „Zauber hierher ziehen“ sichtbar. Eine gelöschte Vorlage kommt über ihren Chip zurück.
6. Einen Zauber aus dem Zauberbuch auf eine Leiste ziehen, `/reload`: Er ist noch da.
7. Im Kampf: `/cp unlock` wird abgelehnt; Änderungen im HUD-Tab werden nach dem Kampf angewendet, keine „Aktion blockiert“-Meldung.
8. Pet-Leiste: Angriff/Folgen/Bleiben/Fähigkeiten per Klick; Autocast-Rahmen sichtbar.

## B2. Speichern und Pet-Abklingzeit (aus der Addon-Recherche)
1. Eine Leiste verschieben, **ausloggen und wieder einloggen** (nicht nur `/reload`): Die Position ist noch da. Andere Addons meldeten auf der Beta verlorene Einstellungen.
2. Im Kampf eine Tierfähigkeit mit Abklingzeit auslösen: Läuft die Abklingzeit auf der Begleiter-Leiste?

## B3. Neue Funktionen (10.11.)
1. **Sichtbarkeit:** HUD-Tab → Abschnitt „Sichtbarkeit“. „Nur mit Ziel“ blendet die Leiste ohne Ziel aus, auch im Kampf. „Bei Mouseover einblenden“ macht sie unsichtbar, bis die Maus darüber ist.
2. **Tasten:** `/cp keys`, Maus über einen Knopf, Taste (auch mit Shift/Strg/Alt) drücken. Das Kürzel steht oben rechts auf dem Knopf, die Taste löst den Zauber aus. Entf löscht, Esc beendet. Nach `/reload` ist die Belegung noch da.
3. **Zähler:** Auf „Automatischer Schuss“ steht die Munitionszahl; unter 200 wird sie orange. Ein Gegenstand auf einer Leiste zeigt seine Anzahl, bei 5 oder weniger orange.
4. **Lehrer:** Klassenlehrer (und Tierlehrer) einmal ansprechen. Der Tab „Lehrer“ zeigt danach, was jetzt und in den nächsten zwei Stufen lernbar ist, mit Kosten. Steht der Lehrer-Filter im Spiel nicht auf „alle“, fehlen Einträge.
5. **Stufenplan:** Im Talent-Tab ein paar Punkte planen. Unten steht „Als Nächstes: …“, das Talent ist golden umrandet. Beim Stufenaufstieg kommt eine Chatzeile.

## B4. Eigene Hauptleiste (10.11.)
1. **Kacheln:** Symbole sitzen mittig in einem 1 px Rahmen, auch auf der Begleiterleiste (Autocast-Ecken) und auf leeren Plätzen.
2. **Spielleiste aus:** HUD-Tab → Schalter „Spielleiste aus“. Die Hauptleiste des Spiels verschwindet, nach Ausschalten kommt sie zurück. `/cp debug` nennt unter „game main bar“ den gefundenen Frame.
3. **Tasten 1–0:** Leiste wählen → „Tasten 1–0“. Die ersten zwölf Knöpfe tragen 1–0, - und =, die Tasten lösen sie aus. Auf einer zweiten Leiste wiederholen: die erste verliert die Tasten.
4. **Fahrzeug/Übernahme:** In einem Fahrzeug oder bei übernommener Einheit lösen 1–6 die Fahrzeugaktionen aus, danach wieder die eigene Leiste. Bei Übernahme ohne Fahrzeugleiste erscheint die Spielleiste von selbst.

5. **Begleiter- und Haltungsleiste:** Mit „Spielleisten aus“ verschwindet die Begleiterleiste des Spiels nur, solange eine eigene aktive Leiste Begleiteraktionen trägt; die Haltungsleiste nur, solange eine eigene Leiste eine Haltung/Gestalt trägt. Eigene Leiste ausblenden (Auge) → die Spielleiste kommt zurück. Mit Hexenmeister, Krieger oder Druide prüfen: Vorlagen „Begleiter“ und „Haltungen“ im HUD-Tab unter „Klassen-Vorlagen“.

## C. Probe (wichtig für die Secret-Value-Regeln)
1. Außerhalb des Kampfes `/cp probe`.
2. Makro `/cp probe` anlegen und **im Kampf** ausführen.
3. `/cp debug` → Abschnitt „Probe“ zeigt, welche Werte im Kampf `SECRET` sind. Diesen Abschnitt weitergeben, dann justieren wir Bereit-Blitz und Reaktiv-Leuchten.

## D. Talente
1. Tab „Talente“: drei Bäume mit Symbolen. Wenn nicht, `/cp talents dump` ausführen und das Ergebnis weitergeben.
2. Punkte setzen (Links), entfernen (Rechts), Regeln prüfen (5 Punkte je Reihe, Voraussetzungen).
3. „Live-Talente übernehmen“, „Vergleichen“, „Exportieren“ und den Text wieder einfügen und mit Enter importieren.

## E. Begleiter
1. Tab „Begleiter“ mit aktivem Pet: Name, Familie, Zufriedenheit, Treue, Trainingspunkte und Ernährung.
2. Den Stallmeister besuchen. Der Stall füllt sich.
3. Wildtierausbildung einmal öffnen. Die Liste füllt sich: grün gelernt, gelb verfügbar, grau nicht verfügbar.

## Offene API-Fragen (werden durch A–E beantwortet)
| Frage | Wo sichtbar |
|---|---|
| Sind `isActive` / `IsSpellUsable` im Kampf geheim? | Probe, Kampf |
| Gibt es `Region:SetAlphaFromBoolean` und `ActionButtonSpellAlertManager`? | Probe, Fähigkeiten |
| Liefert `C_ClassTalents.GetActiveConfigID` die drei Bäume? | `/cp talents dump` |
| Existieren `GetPetHappiness`, `GetPetLoyalty`, `GetPetTrainingPoints`? | Debug, Modul HunterPets |
| Heißt das Fenster der Wildtierausbildung wie Zauber 5149? | Begleiter-Tab nach dem Öffnen |
