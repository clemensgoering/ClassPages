# Gemeinsame Gestaltungsregeln (ClassPages und Goldweaver)

Stand: 10.11.2026. Ziel: Beide Addons wirken wie aus einem Guss. Die Werte stammen aus `ClassPages/UI/Kit.lua` und den Rückmeldungen von Clemens zu den Vorschaubildern. Im Spiel ist das Aussehen noch nicht bestätigt, nur im Simulator.

## 1. Grundsätze
1. **Ruhig statt verspielt.** Dunkle, warme Flächen, ein feiner Bronzerand, Gold als einzige Akzentfarbe. Keine Deko-Elemente vor Überschriften.
2. **Rundungen sparsam.** Rund ist nur, was dadurch klarer wird (Schalter). Symbole und Kacheln bleiben eckig wie im Spiel.
3. **Kurz und prägnant.** Reiter ein Wort, Knöpfe ein bis zwei Wörter, Erklärungen in den Tooltip.
4. **Luft.** Texte berühren weder einander noch den Rand ihrer Karte.
5. **Eine Aktion pro Knopf**, die wichtigste je Bereich als goldener Knopf, alle anderen zurückhaltend.

## 2. Farben (RGB 0–1)
| Rolle | Wert | Verwendung |
|---|---|---|
| Fensterfläche | 0.063, 0.055, 0.047 · Deckkraft 0.97 | Fensterhintergrund |
| Kartenfläche | 0.100, 0.086, 0.068 · 0.94 | Karten, Listenfelder |
| Kopfplatte | 0.082, 0.066, 0.046 | Fensterkopf und Reiterleiste |
| Feld (vertieft) | 0.032, 0.029, 0.026 · 0.92 | Eingabefelder, Balkenspur, Vorschauflächen |
| Rand normal | 0.29, 0.23, 0.16 | Karten |
| Rand Fenster | 0.52, 0.40, 0.21 | Fensterrahmen |
| Gold (Rand, aktiv) | 0.80, 0.62, 0.30 | aktive Reiter, Auswahl, Popups |
| Gold (Text) | 1.00, 0.82, 0.45 | Überschriften, Knopftext, Akzente |
| Text | 0.93, 0.90, 0.85 | normaler Text |
| Text gedämpft | 0.62, 0.57, 0.50 | Beschriftungen, Hinweise |
| Gut / Warnung / Fehler | 0.37, 0.83, 0.37 · 1.00, 0.60, 0.20 · 1.00, 0.42, 0.30 | Status |
| Knopf primär | Fläche 0.36, 0.25, 0.09 · Rand 0.86, 0.67, 0.33 | eine Hauptaktion je Bereich |
| Knopf normal | Fläche 0.115, 0.098, 0.080 · Rand 0.34, 0.27, 0.19 | alle anderen Aktionen |
| Knopf Gefahr | Fläche 0.30, 0.085, 0.06 · Rand 0.78, 0.33, 0.24 | Löschen, mit zweitem Klick zur Bestätigung |

ClassPages nutzt zusätzlich die Klassenfarbe für Titel, Symbolrahmen, Balkenfüllung und den Verlauf im Kopf. Goldweaver hat keine Klassenfarbe und nimmt dafür Gold.

## 3. Formen
| Element | Eckenradius |
|---|---|
| Fenster, Karten, Popups | 5 px |
| Knöpfe, Listenzeilen, Eingabefelder, Balken | 3 px |
| Reiter | 4 px, nur oben |
| Schalter, Scroll-Griff | Pillenform |
| Zauber- und Talentsymbole, Leistenkacheln | eckig, 1 px Rahmen |
| Logo im Fensterkopf | quadratisch, Radius wie das Fenster, 1 px Rahmen |

- Rand überall 1 px. Schatten nur unter Fenster und Popups (schwarz, Deckkraft 0.65–0.7, etwa 14 px Überstand).
- Leichter Glanz oben auf Karten und Knöpfen (warmes Weiß, Deckkraft 0.03–0.14, 14 px hoch).
- Aktiver Reiter: goldener Rand und eine weiche goldene Leuchtlinie am unteren Rand.

## 4. Maße
| Was | Wert |
|---|---|
| Fensterkopf | 64 px hoch; Logo 36 px, 16 px vom linken Rand, 13 px von oben |
| Reiter | 28 px hoch, 3 px Abstand, Symbol 16 px + Text |
| Rand Fenster → Inhalt | 14 px |
| Abstand zwischen Karten | 12 px |
| Innenrand Karte | 12 px; Titel bündig mit dem Inhalt; darunter eine auslaufende Trennlinie bei 29 px |
| Knopfhöhe | 22 px (Hauptaktion in Leisten 28 px) |
| Listenzeile mit zwei Textzeilen | 42 px; Symbol 28 px |
| Schlüssel-Wert-Zeile | 22 px Raster |
| Abstand übereinanderstehender Texte | mindestens 3 px; ebenso zum Kartenrand |

## 5. Bausteine
- **Schalter** statt Kästchen für an/aus; Beschriftung rechts daneben.
- **Aufklappmenü** für Auswahl aus einer Liste; Häkchen am aktuellen Eintrag; schließt bei Klick daneben.
- **Stepper** (− Wert +) für Zahlen; Shift = Fünferschritte. Keine Schieberegler.
- **Symbol-Knöpfe** für wiederkehrende Aktionen: Auge (ein-/ausblenden), Plus/Minus, Kreuz (schließen).
- **Listen** mit Bereichsüberschrift in Gold und auslaufender Linie; Zeile hebt sich beim Überfahren dezent ab; Status rechtsbündig in Statusfarbe.
- **Leere Zustände** bekommen einen Satz, was zu tun ist („Besuche einmal deinen Lehrer …“).
- **Unbestätigte Daten** tragen „~“ und einen Tooltip-Hinweis.

## 6. Texte
- Reiter höchstens 12 Zeichen, Bereichstitel 24, Einleitung 90, Notiz 110.
- Knöpfe als Verb oder Verb + Objekt: „Verschieben“, „Neu füllen“, „Löschen“.
- Deutsch und Englisch gleichwertig; Spielbegriffe wie im Client.

## 7. Umsetzung in ClassPages
- Grafikset: `ClassPages/Media` (22 weiße Formen, per `SetVertexColor` getönt), erzeugt von `tools/assets/make_assets.py`.
- Bausteine: `ClassPages/UI/Kit.lua` (`UI.Skin` mit den Stilen aus Abschnitt 2, `UI.Slice`, `Button`, `Check`, `Dropdown`, `Stepper`, `Card`, `Icon`, `Bar`, `Edit`).
- Absicherung: `tools/tests/layout.lua` prüft Überstand, Überlappung, Abstände und Knopftexte in beiden Sprachen; `tools/preview.ps1` erzeugt Vorschaubilder.
- Goldweaver kann Grafikset und Kit übernehmen (gleiche Lizenz, gleicher Autor) oder die Werte in seinem eigenen Kit nachbauen.
