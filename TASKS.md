# Tasks — Stellwerk

Stand: 2026-11-21 · Beschreibung und Technik in `AGENTS.md`

## Als Nächstes (Martin, 2026-11-21)

- [ ] **Programmprofile ausbauen und im Alltag testen.** Grundlage steht: Modus „Im aktiven Programm“, Profile pro Gerät, Kürzel für Tasten und Drehregler, Menüeintrag neben jedem Kürzel. Zu klären: welche Programme zuerst (Photoshop? Premiere? Finder?), sinnvolle Vorgaben je Programm, ob Drehregler mehr als Kürzel brauchen (z. B. Scrollen, Pinselgröße)
- [ ] **Icon: Weiche** (2026-11-22). Symbol = die Alt-/Option-Taste **⌥** (Unicode `U+2325`), sieht aus wie eine Weiche → passt zum Namen Stellwerk.
  - **Menüleiste:** SF Symbol **`option`** (am Mac verfügbar, geprüft). In `app/Stellwerk/StellwerkApp.swift` das jetzige `dial.medium` / `dial.medium.fill` ersetzen. `option` hat keine `.fill`-Variante → Verbindungsstatus anders zeigen, z. B. getrennt = gedimmt (`.opacity(0.4)`) oder kleiner Punkt daneben. Als Template-Symbol lassen (passt sich hell/dunkel an)
  - **App-Icon:** gibt es noch nicht, das Projekt hat kein `Assets.xcassets`. Anlegen, `AppIcon` mit dem ⌥-Glyph (SF Symbol `option` als Vorlage, kräftige Strichstärke) in Dunkel auf Markenfarbe **Lime `#C7D300`**, macOS-Rundquadrat. Alle Größen 16–1024 px
  - Ausweichsymbol, falls ⌥ zu sehr nach „Taste" aussieht: SF Symbol **`arrow.triangle.branch`** (Abzweig, ebenfalls geprüft)

## Erledigt

- [x] Universelle Architektur festgehalten (`ARCHITEKTUR.md`): Eingabe-Adapter inkl. Software-Surface, semantische Aktionen, Mapping, Feedback, externe Adapter
- [x] Privates Git-Repo angelegt (github.com/martindoersch/stellwerk)

- [x] Resources gesichtet (Loupedeck-, Tangent-Installer, PDFs; TourBox-Datei war die Android-`.apk`, die Mac-App ist schon installiert)
- [x] Schnittstellen analysiert: Capture One über Tangent (TIPC), Lightroom über Lua-SDK, Photomator nur Tastenkürzel
- [x] Tangent-Unterstützung in Capture One aktiviert (`TangentDeviceSupportEnableDefaultsKey = 1`)
- [x] Prototyp `bridge/fake_tangent_hub.py`: **Capture One verbindet sich und meldet Werte** (Belichtung gelesen)
- [x] Recherche „Gibt es das schon?": nein, Details in `AGENTS.md`. Neue Prüfpunkte unten (AppleScript, tangent-lightroom, MIDI2LR)

## Phase 1 — Capture One nativ (über den Test-Hub)

- [x] Schreiben verifiziert: Belichtung 0 → 0,1 → 0,2 → 0,1 → 0, Capture One meldet jeden Wert zurück ✅
- [x] Wiederverbinden geprüft: Capture One verbindet sich **nur beim Start** → Bridge muss vor Capture One laufen (oder Capture One neu starten). Später: Bridge startet beim Login
- [x] `controls.xml` komplett ausgewertet: `bridge/parse_controls.py` erzeugt `docs/capture-one-controls.md` (Tabelle) und `bridge/mappings/capture-one-controls.json`. **63 Regler, 429 Aktionen, 34 Gruppen.** Nach Capture-One-Updates neu laufen lassen und per `git diff` prüfen
- [x] **Undo fehlt** in `controls.xml` (Redo `0x78` ist da). `ActionOn 0x77` getestet: wirkungslos → Bridge schickt ⌘Z als Tastenkürzel direkt an Capture One (layout-sicher, deutsch Z/Y)
- [x] ⌘Z über die Bridge in Capture One getestet ✅ (2026-11-21). `postToPid` landete im Terminal (Warnton) → jetzt Menüeintrag mit passendem Kürzel per Bedienungshilfen-API klicken (sprachunabhängig); Capture One muss dafür **vorne** sein, die Bridge holt es kurz nach vorne. Tastendruck nur noch als Notlösung
- [x] Redo: Tangent `0x78` wirkungslos (wie Undo `0x77`) → ebenfalls Menü/Tastenkürzel ⇧⌘Z, funktioniert ✅
- [ ] Doppelte Aktionen klären: z. B. Copy Adjustments `0xFC` (Adjustments) und `0x16C` (Cursor Tools), Rotate Left `0xF9` und `0x158`. Welche macht was?
- [ ] Modi: Capture One meldet nur **einen** Modus („Default", `0x00010001`). Modi pro Werkzeug muss also die Bridge selbst verwalten (Ebenen im Mapping), nicht Capture One. Kurz testen, ob `ModeChange` trotzdem etwas bewirkt
- [ ] Verhalten klären: Welcher Wert gilt bei mehreren ausgewählten Bildern? Was passiert ohne geöffnetes Bild?
- [ ] AppleScript-Wörterbuch von Capture One ansehen: Welche Regler fehlen in `controls.xml`, sind aber per AppleScript erreichbar (z. B. Drehen, Keystone)? Als Ergänzung für Tasten, nicht für Drehregler

## Phase 2 — Loupedeck+ → Capture One

- [x] Loupedeck+ angesteckt: meldet sich als **MIDI-Gerät** „Loupedeck+" (Ein- und Ausgang), kein Treiber nötig, Loupedeck-Software muss nicht laufen
- [x] Runde 1: 22 Drehregler mitgeschnitten (`bridge/mitschnitt-runde1-regler.log`): Kanal 1, Drehen = CC relativ (`01` = +1, `7F` = −1), Drücken = Note mit gleicher Nummer. CCs 33–48 (14 Regler) + 1–8 (Farbregler). Obere Regler senden ca. 3× so viele Schritte wie die Farbregler → Schrittweite pro Regler
- [x] Loupedeck+ angelernt (2026-11-21) → `bridge/mappings/loupedeck-plus.json`. Keine Bewertungstasten: die Tasten neben „--/Clr" sind **Shift, Ctrl, Cmd, Alt, Tab**. Drehregler-Drücken muss nicht angelernt werden (Note = CC-Nummer)
- [x] Sterne und Farbmarkierungen: auf die fünf Modus-Tasten (Umschalter `--/Clr`), wie in der Loupedeck-Software
- [ ] Loupedeck-Software beenden oder Gerät freigeben, falls sie es blockiert
- [x] Belegung `bridge/mappings/loupedeck-plus-captureone.json`: Beschriftung → Capture-One-Regler/-Aktion/Tastenkürzel, `perTick` pro Regler, Beschleunigung einstellbar
- [x] Bridge-Prototyp `bridge/stellwerk.swift` (Swift, CoreMIDI + Network): MIDI rein → Tangent raus, Beschleunigung, Deltas alle 15 ms gebündelt, Drücken = zurücksetzen, Startwerte abfragen, Simulation übers Terminal. **Mit echtem Capture One getestet** ✅ (Regler, Reset, Aktionen), Test-Client `bridge/fake_captureone.py`
- [x] Echte Regler getestet (2026-11-21): **Empfindlichkeit perfekt**, mehrere Regler gleichzeitig drehen funktioniert („WOW") ✅. Copy `0xFC` ✅. Paste `0xFD` öffnete Dialog „Anpassungen einfügen" und hing → jetzt Menü ⇧⌘V (testen; Alternative `0x16D`)
- [x] Getestet ✅: Alt/⌥ = fein, Shift/⇧ = grob; `--/Clr` = Sterne ↔ Farben, Fn + `--/Clr` = Modifier-Modus, Fn + Taste = löschen; Paste über Menü ⇧⌘V
- [x] Modifier-Modus: Loupedeck-Tasten Shift/Ctrl/Cmd/Alt/Tab wirken als **echte Tasten**, auch mit Maus-Klicks ✅ (Martin: Standard-Tasten wichtiger als Fein/Grob, beides zusammen ok). Gemeldete Modifier allein reichen nicht – echte Mausklicks tragen nur den Zustand der echten Tastatur → **Event-Tap** setzt die gehaltenen Loupedeck-Modifier bei Maus-/Tastatur-Ereignissen dazu
- [ ] Testbelegung aller Tasten ausprobieren (2026-11-21): Farbregler = Farbbalance (Gesamt/Schatten/Mitteltöne/Lichter X/Y), **Clr/BW** = SW ein/aus + Farbregler auf SW-Regler; P1–P8 Auto/Reset/Drehen/Warnungen/Varianten, C1–C6 Werkzeuge, L1–L3 Ebenen, Export ⌘D. Frei: Hue/Sat/Lum (kein HSL über Tangent), Custom Mode (reserviert für zweite Belegung)

## Phase 2b — Software-Surface (früh, als Testwerkzeug)

- [ ] Web-Oberfläche (Touch/Maus) von der Bridge ausgeliefert, Regler + Tasten, zeigt Werte aus Capture One live
- [ ] Spricht schon das externe Adapter-Protokoll (WebSocket, JSON) → legt das Format praktisch fest
- [ ] Vorher kurz TouchOSC/OSC prüfen: fertige Oberfläche statt Eigenbau?
- [ ] Grundsatz: nur für Martin bauen, klein starten, aber nichts verbauen (neutrale Aktionen, Adapter austauschbar)

## Phase 3 — TourBox Elite Plus nativ

- [x] **USB-Kabel funktioniert nativ** (2026-11-21): serielles Gerät, Unlock + Konfiguration aus tuxbox, ein Byte pro Ereignis → `docs/tourbox-protokoll.md`, Mitschreiber `bridge/tourbox_monitor.swift`. Die TourBox Console muss dafür nicht laufen
- [x] Codes bestätigt: Namen, Drehrichtung (0x40 = rechts/rauf), Steuerkreuz
- [x] Eingang `TourBoxInput` in der App, Geräte-/Belegungsdateien pro Gerät, Einstellungen pro Gerät (Side = Kombi-Taste, `fnDials`)
- [x] In der App mit echter TourBox getestet (Verbindung, Vorgabe-Belegung, Side-Kombis) – „passt perfekt"
- [ ] BLE-Protokoll anhand des Community-Gists (AndyCappDev, „TourBox Elite BLE Protocol") prüfen
- [ ] Verbindung über CoreBluetooth testen, inklusive Unlock-Sequenz; Konflikt mit TourBox Console klären (muss die App beendet sein?)
- [ ] Haptik/Feedback der Elite nutzen, falls das Protokoll es hergibt
- [ ] Fallback: TourBox Console sendet Tastenkürzel → Bridge übersetzt

## Phase 4 — Menüleisten-App (Swift)

- [x] **Version 0.1** (2026-11-21): Xcode-Projekt `app/`, Prototyp portiert (MIDI, Tangent-Hub, Menü-Kürzel, Modus-Tasten, SW-Ebene, Modifier + Event-Tap, Fein/Grob, Beschleunigung). Statusmenü: Verbindungen, Bedienungshilfen, Modus, Belichtung, letzte Aktion, Belegung neu laden, Ordner, Autostart. Baut ohne Warnungen
- [x] v0.1 von Martin getestet ✅ (2026-11-21): läuft mit Loupedeck+ und Capture One
- [x] **Version 0.2** (2026-11-21): Einstellungsfenster. *Drehregler:* Geschwindigkeit, Beschleunigung (0 = aus), Fein/Grob-Faktoren. *Tasten:* jede Taste auf Vorgabe / Capture-One-Aktion (Suchliste) / eigenes Tastenkürzel (Aufnahme) / aus. Gespeichert als Überlagerung in `~/Library/Application Support/Stellwerk/settings.json`, Vorgabe bleibt unangetastet
- [x] **Version 0.3** (2026-11-21): Einblendung beim Moduswechsel (Sterne/Farben/Tasten, Schwarzweiß/Farbbalance), unten mittig auf dem Bildschirm mit der Maus, ohne Fokusklau; abschaltbar im neuen Reiter „Allgemein" (dort auch Autostart, Belegungsordner)
- [x] Absturz beim Moduswechsel behoben: NSHostingView steuerte die Fenstergröße der Einblendung → Layout-Schleife (`sizingOptions = []`). Nachgestellt und geprüft mit `bridge/fake_loupedeck.swift`
- [x] Neu verbinden ohne Neustart geprüft (2026-11-21): **geht nicht.** Capture One verbindet nicht von selbst (20 s gewartet), reagiert nicht auf `defaults write` des Tangent-Schalters, und der Schalter in den Einstellungen verlangt selbst einen Neustart. Kein Tangent im AppleScript-Wörterbuch → Neustart ist der einzige Weg
- [x] Sicherheit: Hub lauschte auf allen Schnittstellen (`*:64246`, also im WLAN erreichbar), obwohl `requiredInterfaceType = .loopback` gesetzt war → jetzt fest an `127.0.0.1` gebunden (App und Prototyp)
- [x] Martins Wünsche (2026-11-21): **Fn + Undo = Zurücksetzen** (neuer Abschnitt `fnButtons` in der Belegung, in den Einstellungen angezeigt), **C1 = Enter, C2 = Esc**. Tasten ohne Menüeintrag gehen jetzt als echter Tastendruck an die vorderste App (Capture One wird vorher nach vorne geholt). Zuschneiden/Ausrichten sind damit von C1/C2 weg
- [x] Bug (behoben, von Martin bestätigt ✅): Fn + Undo kam als Undo an. Mitschnitt zeigte korrektes MIDI; Ursache: `"_hinweis"`-Text im Abschnitt `fnButtons` ließ den strengen JSON-Cast scheitern → ganzer Abschnitt verworfen. Jetzt werden Hinweistexte in allen Abschnitten übersprungen (`entries()`)
- [x] Fn-Ebene in den Einstellungen belegbar (Knopf „Fn …" pro Taste, gespeichert als `fnButtons` in settings.json)
- [x] Knopf „Capture One neu starten" im Menü (nur sichtbar, wenn Capture One läuft, aber nicht verbunden ist): beendet wie ⌘Q, wartet bis zu 30 s, startet neu
- [ ] **Martin:** v0.3 testen, dazu Fn-Ebene in den Einstellungen und Neustart-Knopf
- [ ] Ganz zum Schluss: Custom Mode (zweite Belegung aller Tasten)
- [ ] Belegungsdateien: `app/Stellwerk/Mappings/` ist jetzt die Hauptquelle; `bridge/mappings/` nur noch für den Prototyp

- [ ] Kern nach `ARCHITEKTUR.md`: Control-Ereignis, Aktions-Vokabular, Mapping-Format, Feedback-Bus, aktive App erkennen
- [ ] Swift-Protokolle `InputAdapter` / `OutputAdapter` mit Capabilities
- [ ] Externes Adapter-Protokoll (lokaler WebSocket, JSON) festlegen; OSC als Alternative prüfen
- [ ] Tangent-Hub-Server in Swift (Network-Framework), MIDI über CoreMIDI
- [ ] Menüleiste: Verbindungsstatus pro Gerät und App, Mapping wählen; Markenfarbe Lime `#C7D300`
- [ ] **Wünsche aus dem Praxistest (2026-11-21):**
  - Drehgeschwindigkeit einstellbar machen, mit Beschleunigungskurve („Ramp": schneller drehen = größere Schritte)
  - Fein/Grob per Modifier als Option (Standard wie Photoshop: Alt = fein, Shift = grob). Vorrang haben aber echte Modifier-Tasten; Fein/Grob nur als Zusatz, kein „Voodoo"
  - Tastenbelegung **auswählbar statt fix**: sinnvolle Vorgabe (z. B. Export = ⌘D), pro Taste auf Aktion aus Liste oder eigenes Tastenkürzel umstellbar
  - **Modi/Ebenen** wie in der Loupedeck-Software für LrC: `--/Clr` schaltet die fünf Tasten Shift/Rot/1 · Ctrl/Gelb/2 · Cmd/Grün/3 · Alt/Blau/4 · Tab/Violett/5 zwischen Sternen und Farben, Fn + `--/Clr` auf Modifier-Tasten; **Custom Mode** = komplette zweite Belegung aller Tasten
  - Aktuellen Modus anzeigen (Menüleiste, evtl. Ansage/Overlay)
- [ ] Autostart, Code-Signierung

## Phase 5 — Lightroom Classic und weitere Apps

- [ ] Zuerst **tangent-lightroom** (crazyscot) prüfen: Macht es Lightroom zum Tangent-Client, braucht unsere Bridge keinen eigenen LR-Adapter
- [ ] Zwischenlösung: MIDI2LR direkt mit Loupedeck+ testen
- [ ] Sonst eigenes `.lrplugin` mit `LrSocket` und `LrDevelopController` (Vorbild: `logiplugin.lrplugin` lesen)
- [ ] Photomator über Tastenkürzel und Kurzbefehle
- [ ] Optional: DaVinci Resolve (kann ebenfalls Tangent)

## Hilfsmittel (Vorschläge aus der Recherche, 2026-11-21)

- [ ] **Martin:** Tangent Developer Support Pack holen (Registrierung auf tangentwave.co.uk). Das ist die offizielle TIPC-Spezifikation statt Nachbau aus dem Hammerspoon-Code
- [~] ~~Installer in `Resources/` mit `pkgutil --expand` auspacken~~ – entfällt (2026-11-21): Loupedeck und TourBox laufen nativ, Installer gelöscht., **nicht installieren** (Port 64246!): Loupedeck enthält vermutlich die AppleScript-Anbindung an Capture One und die Belegung des Loupedeck+ als Vorlage für Phase 2; der Tangent Hub vermutlich die Standard-Maps für Capture One und eventuell SDK-Teile
- [ ] MIDI mitschneiden mit der kostenlosen App *MIDI Monitor* (snoize) oder einem eigenen Skript
- [ ] TourBox: BLE-Verkehr von TourBox Console mit Apples **PacketLogger** („Additional Tools for Xcode") mitschneiden, um den Linux-Gist auf dem Mac zu prüfen
- [ ] Eigene Test-Session in Capture One anlegen, damit Schreibversuche keine echten Bearbeitungen verändern; Capture-One-Einstellungen vorher sichern
- [ ] Entscheidung: Python ohne Zusatzpakete kann kein MIDI. Entweder `mido` + `python-rtmidi` installieren oder den MIDI-Teil gleich in Swift mit CoreMIDI bauen. **Empfehlung: Swift**, weil Phase 4 ohnehin Swift ist

## Offene Fragen / Risiken

- Loupedeck+ wird von der aktuellen Logi-Software eventuell nicht mehr unterstützt; das ist egal, solange MIDI funktioniert
- Capture-One-Updates könnten Parameter-IDs ändern → `controls.xml` beim Start einlesen statt fest einzubauen
- Ein später installierter Tangent Hub kollidiert mit Port 64246

## Werkverzeichnis

- [x] Eintrag in `INDEX.md` und `LOGBUCH.md` (laufend nachtragen)
