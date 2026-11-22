# Tasks — Stellwerk

Stand: 2026-11-22 · Beschreibung und Technik in `AGENTS.md`

## Als Nächstes (Martin, 2026-11-21)

- [ ] **Programmprofile ausbauen und im Alltag testen.** Grundlage steht: Modus „Im aktiven Programm“, Profile pro Gerät, Kürzel für Tasten und Drehregler, Menüeintrag neben jedem Kürzel. Zu klären: welche Programme zuerst (Photoshop? Premiere? Finder?), sinnvolle Vorgaben je Programm, ob Drehregler mehr als Kürzel brauchen (z. B. Scrollen, Pinselgröße)
  - [x] **Vorgaben für Programmprofile** (2026-11-22): `Mappings/app-profiles.json`, wird beim Hinzufügen des Programms übernommen (Menü „Programm hinzufügen" › „Mit Vorgabe"), Knopf ↺ setzt ein Profil auf die Vorgabe zurück. Quick-Keys-Display zeigt im Programmprofil dessen Belegung (Kurznamen per `labels`/`fnLabels`). Fehler beim Einlesen gefunden und behoben: fehlte ein Abschnitt (z. B. `fnButtons`), scheiterte das ganze Profil
  - [ ] **Finder als erster Versuch** (Vorgabe für alle drei Geräte: Drehen = Auswahl bewegen, Drücken = Quick Look, ⌘↑/⌘↓ Ordner hoch/öffnen, ⌘1–4 Darstellung, Papierkorb, Tabs). **Martin:** im Alltag testen; dabei prüfen: Kürzel im Einstellungsfenster als Finder-Menüeintrag erkannt? Umlaute auf dem Quick-Keys-Display („Öffnen")? Blättert Quick Look beim Drehen mit?
    - Von Martin getestet ✅ (2026-11-22): Finder-Profil wirkt laut Vorgabe, Wechsel Finder ↔ Capture One schaltet Display und Belegung um. Stolperstein beim Testen: Capture One lief schon vor dem Neustart von Stellwerk → nicht verbunden, Tangent-Befehle kamen nicht an (Display schaltet trotzdem um, das macht Stellwerk allein). Lösung wie immer: Capture One neu starten
    - Rückmeldung (2026-11-22): Kürzel werden alle als Finder-Menüeintrag erkannt ✅. Display zeigt „Öffnen" als „Offnen" (Schrift kennt keine Umlaute, für Martin ok). Quick Look blättert beim Drehen mit ✅, aber ↑ ↓ springt in der Symboldarstellung zeilenweise → **Hauptrad jetzt ← →** (Loupedeck großes Rad, TourBox Scroll, Quick Keys Rad), zweiter Drehregler ↑ ↓ (Contrast bzw. Knob). In Liste/Spalten klappt ← → Ordner auf/zu, dafür bleibt ↑ ↓. Nach Zurücksetzen mit ↺ von Martin getestet ✅ (Rad geht ← →)
    - Bug (2026-11-22, behoben, ungetestet): Wechsel in ein Programm ohne Profil zeigte „Capture One", auch wenn Capture One gar nicht läuft → dann jetzt „Kein Profil" (gleicher Text für alle Programme ohne Profil, also keine Einblendung bei jedem Wechsel). Wird auch beim Starten/Beenden von Capture One neu bestimmt
    - Martins Wunsch (2026-11-22): beim Programmwechsel **Profilname kurz als Einblendung auf dem Quick-Keys-Display** (1 s, nur beim Profilwechsel, folgt dem Schalter „Einblendung“ unter Allgemein). Erster Test: erschien nicht → jetzt 0,3 s verzögert und 2 s lang (Verdacht: Xencelabs-Treiber schreibt beim Programmwechsel dazwischen, nicht weiter geprüft). Von Martin getestet ✅ (2026-11-22)
    - **Bug Bildschirm-Einblendung** (2026-11-22, behoben): zeigte nur Symbol und Hintergrund, kein Text. Ursache: mit `sizingOptions = []` liefert `fittingSize` 0 × 0 (nachgemessen) → Fenster zu klein. Betraf seit der Absturz-Behebung alle Einblendungen. Jetzt Größe per `NSHostingController.sizeThatFits` gemessen, Absturz-Schutz bleibt. Von Martin getestet ✅
- [ ] **Öffentlich auf GitHub** (2026-11-22, öffentlich seit 2026-11-22). Vorbereitet: englische Oberfläche (String Catalog), `README.md` (EN) + `README.de.md`, `AGENTS.md` auf Englisch, `CLAUDE.md`, `ARCHITECTURE.md`, MIT-`LICENSE`. Offen:
  - [x] **Rechtlich:** Regler-Liste wird beim Start aus dem installierten Capture One gelesen (`controls.xml`, XMLParser), nicht mehr mitgeliefert. Geprüft: liefert dieselben 492 Einträge wie die alte JSON, 0 Unterschiede. Abgeleitete Dateien aus dem Repo genommen und in `.gitignore`
  - [x] Bundle-ID `MD.Stellwerk` → `at.martindoersch.Stellwerk` (**Martin:** Bedienungshilfen-Freigabe und Autostart neu setzen)
  - [x] README: „Developers only“, kein signierter Download
  - [x] Git-Verlauf bereinigt (abgeleitete Capture-One-Dateien aus allen Commits entfernt, Sicherung `../Stellwerk-vor-Bereinigung-2026-11-22.bundle`), Repo **öffentlich**, Beschreibung + Topics, GitHub erkennt MIT
  - [ ] Screenshot/GIF fürs README (vorher auf private Bilder prüfen)
  - Optional später: signierte, notarisierte Version als Download (Developer ID, GitHub Releases)

## Erledigt

- [x] **Icon: Weiche ⌥** (2026-11-22). Menüleiste: SF Symbol `option` als Template, getrennt = 40 % Deckkraft (ins Bild gezeichnet, `.opacity` greift im Menüleisten-Label nicht verlässlich). App-Icon: im vorhandenen Icon-Composer-Bündel `app/Stellwerk/Stellwerk.icon` den Drehregler-Glyph durch `Assets/option.svg` ersetzt, dunkel auf Lime (Dunkelmodus: Lime-Glas). Ausweichsymbol bei Bedarf: `arrow.triangle.branch`
- [x] Universelle Architektur festgehalten (`ARCHITECTURE.md`): Eingabe-Adapter inkl. Software-Surface, semantische Aktionen, Mapping, Feedback, externe Adapter
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

## Phase 3b — Xencelabs Quick Keys

- [x] Protokoll (2026-11-22): HID über den Funk-Dongle, ohne Treiber. Mitschreiber `bridge/quickkeys_monitor.swift`, Codes bestätigt: Tasten 0–7, 8 = unten, 9 = Rad-Knopf, Rad 1 Meldung/Raste. Display-Texte, Einblendung (braucht `05` + `06`-Block) und Ringfarbe funktionieren → `docs/quickkeys-protokoll.md`
- [x] In der App (2026-11-22): `QuickKeysInput`, Geräte- und Belegungsdatei. Neu im Kern: `dialSelect` – Tasten wählen, was das Rad steuert (halten + drehen = vorübergehend, tippen = bleibt, nochmal tippen = aufheben), Rad-Knopf = zurücksetzen. Display zeigt Kurzname + Wert aus Capture One, gewählte Taste mit „>", Ringfarbe je Regler. Ohne Auswahl: Rad = Bild vor/zurück. Baut ohne Warnungen
- [x] Von Martin getestet ✅ (2026-11-22): Wahl per Halten/Tippen „fühlt sich richtig an", Schrittweiten passen. Einblendung beim Drehen störte → entfernt, die Werte neben den Tasten reichen. Einblendung beim Wählen störte ebenfalls → ganz weg (Wahl sieht man am „>" und an der Ringfarbe). **Display-Schrift kennt kein ß** („Weiß" → „Wei") → wird als „ss" geschrieben; Umlaute ungetestet
- [x] Parallel zum Xencelabs-Treiber (Tablett): Quick-Keys-Tasten dort deaktivieren, prüfen ob der Treiber das Display überschreibt (Stellwerk schreibt beim Wechsel zu Capture One neu)
  - Test von Martin (2026-11-22), Treiber läuft, Quick-Keys-Einstellungen im Treiber unverändert: Solange Stellwerk läuft, funktioniert es wie ohne Treiber (LrC). Stellwerk beendet → Display behält die Stellwerk-Texte; Quick Keys aus- und einschalten → Xencelabs-Oberfläche und -Funktionen wieder da. Stellwerk erneut gestartet → geht wieder ✅. Keine doppelte Auslösung ✅, Stift normal ✅. **Nach Standby: Taste löst doppelt aus** (Stellwerk + Treiber-Kürzel). Vermutung: der Treiber übernimmt die Quick Keys erst, wenn sie sich neu verbinden (Standby, Aus/Ein), vorher war er nach Stellwerk gestartet. Nächster Test: Quick-Keys-Tasten und Rad im Treiber deaktivieren, dann Aus/Ein und Standby. Ausweg falls nicht abschaltbar: nur den Herstellerkanal `0xFF0A` exklusiv öffnen (ungetestet)
  - Nachtest: doppelte Auslösung auch ohne Standby, fiel vorher nur nicht auf (nur gedreht). Stift/Tablett normal ✅
  - Versuch exklusiv (2026-11-22, wieder ausgebaut): Herstellerkanal `0xFF0A` mit `kIOHIDOptionsTypeSeizeDevice` geöffnet → macOS erlaubt es, aber **Stift geht nicht mehr** (Treiber holt die Stiftdaten offenbar über denselben Kanal) und auch Stellwerk bekam keine Tasten. Kein Weg, solange der Treiber läuft. Bleibt: Quick-Keys-Tasten und Rad im Treiber deaktivieren, oder Quick Keys ohne Tablett/Treiber nutzen
  - **Lösung** (2026-11-22, Martin ✅): in der Xencelabs-App (1.3.5) unter „Meine Quick Keys" einen Tastensatz „fürStellwerk" mit allen 8 Tasten auf „Deaktivieren" und eine Drehschalter-Klickabfolge „fürStellwerk" mit Drehen links/rechts auf „Deaktivieren" anlegen und auswählen → Stellwerk geht wie erwartet, Stift normal. Unschön: der Satz muss erst ausgewählt sein (Taste unten bzw. Rad-Knopf wechseln im Treiber Satz/Modus, Stellwerk nutzt dieselben Tasten). **Einschränkung, von Martin so akzeptiert:** Fn/Rad-Knopf können den Treiber aus „fürStellwerk" wegschalten (nicht geprüft). Abhilfe bei Bedarf: andere Sätze/Modi aus der Abfolge nehmen oder Programmeinstellungen (+) für LrC/Capture One/Finder. Display behält nach dem Beenden von Stellwerk dessen Texte, bis die Quick Keys aus/ein geschaltet werden
- [x] **Fn-Ebene zum Umschalten** (2026-11-22): Taste unten halten = Fn-Ebene vorübergehend, kurz tippen = bleibt (Ring violett, Display zeigt die Fn-Belegung), nochmal tippen = zurück. Im Kern per `"fnLatch": true` in der Belegung (sonst wie bisher, Loupedeck unverändert), Kurznamen fürs Display per `"label"` in `buttons`/`fnButtons`. Vorgabe: links Grün P / ohne U / Rot X / Viewer G, rechts 0 / 1 / 5 Sterne / Alle anzeigen N
- [x] Fn-Ebene von Martin getestet ✅ (2026-11-22): „passt gut so"
- [ ] **Seiten/Ebenen** allgemein im Kern (für alle Geräte): mehr als eine Zusatzebene, Taste „nächste Seite"/„Seite X". Loupedeck: Custom Mode
- [ ] Einstellungsfenster: Wahltasten (`dialSelect`) dort sichtbar machen und bearbeiten
- [x] Akkustand im Statusmenü neben „verbunden" (2026-11-22, `F2 01`). Balken im Display geht nicht: kein Pixelzugriff, nur Textfelder und Einblendung

## Phase 4 — Menüleisten-App (Swift)

- [x] **Version 0.1** (2026-11-21): Xcode-Projekt `app/`, Prototyp portiert (MIDI, Tangent-Hub, Menü-Kürzel, Modus-Tasten, SW-Ebene, Modifier + Event-Tap, Fein/Grob, Beschleunigung). Statusmenü: Verbindungen, Bedienungshilfen, Modus, Belichtung, letzte Aktion, Belegung neu laden, Ordner, Autostart. Baut ohne Warnungen
- [x] v0.1 von Martin getestet ✅ (2026-11-21): läuft mit Loupedeck+ und Capture One
- [x] **Version 0.2** (2026-11-21): Einstellungsfenster. *Drehregler:* Geschwindigkeit, Beschleunigung (0 = aus), Fein/Grob-Faktoren. *Tasten:* jede Taste auf Vorgabe / Capture-One-Aktion (Suchliste) / eigenes Tastenkürzel (Aufnahme) / aus. Gespeichert als Überlagerung in `~/Library/Application Support/Stellwerk/settings.json`, Vorgabe bleibt unangetastet
- [x] **Version 0.3** (2026-11-21): Einblendung beim Moduswechsel (Sterne/Farben/Tasten, Schwarzweiß/Farbbalance), unten mittig auf dem Bildschirm mit der Maus, ohne Fokusklau; abschaltbar im neuen Reiter „Allgemein" (dort auch Autostart, Belegungsordner)
- [x] **Version 0.4** (2026-11-22): Xencelabs Quick Keys (Phase 3b). Versionsnummer klein neben dem Namen im Statusmenü (aus `MARKETING_VERSION`, bisher stand dort noch 0.1)
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

- [ ] Kern nach `ARCHITECTURE.md`: Control-Ereignis, Aktions-Vokabular, Mapping-Format, Feedback-Bus, aktive App erkennen
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

- [x] **tangent-lightroom** geprüft (2026-11-22): eingestellt (archiviert 2022, lief über eigene Python-Brücke + Tangent Mapper). Nachfolger ist Tangents offizielles LrC-Plug-in (Hub 1.7.0, 2021); ob es TIPC spricht, ist undokumentiert → nicht weiter verfolgt, Martin hat sich für ein eigenes Plug-in entschieden
- [x] Vorbild angesehen (2026-11-22): Logi-Plug-in (`logiplugin.lrplugin`, lesbares Lua) und TourBox-Plug-in. Muster: Plug-in lauscht per `LrSocket` auf zwei vom System vergebenen Ports (send/receive), schreibt sie in eine Datei, die Hersteller-App verbindet sich. Logi führt beliebige Lua-Skripte der App aus (`runscript`) – das „Gefühl" (Schritte, Beschleunigung) steckt in der App. Regler = getValue + Delta, auf getRange begrenzen, setValue. Werte alle 200 ms abfragen und Änderungen melden (auch Maus). Code gehört Logitech → nur Vorgehen übernommen
- [ ] **Eigenes Plug-in `lightroom/Stellwerk.lrplugin`** (2026-11-22, Schritt 1 geschrieben, ungetestet): feste Befehle statt Skripte (`change`/`set`/`reset`/`get`/`watch`/`do`), eine Abarbeitungs-Schleife (Deltas eines Reglers zusammengefasst, nichts überholt sich), Portdatei `~/Library/Application Support/Stellwerk/lightroom-ports`, Meldungen `value`/`module`/`photo`. Test-Client `bridge/lightroom_test.py`, Installation `lightroom/install.sh`
  - Getestet ✅ (2026-11-22, mit Martin): Belichtung schrittweise, Zurücksetzen, Werte zurück, Wiederverbinden 3× hintereinander. Belastung: 100 × 0,01 in 0,74 s → alle angekommen (Endwert genau 1,00), aber Lightroom erst nach 2,9 s fertig: **~50 ms pro setValue** (Bild wird neu berechnet). → Stellwerk muss Deltas sammeln und höchstens ~alle 60 ms pro Regler senden
  - Stolpersteine: Aus dem Repo über den Zusatzmodul-Manager hinzugefügt, las Lightroom nur `Info.lua` („No script by the name …“) → in den Modules-Ordner kopieren (`install.sh`). `LrShutdownPlugin`/`LrShutdownApp` müssen eine Tabelle mit `LrShutdownFunction(doneFunction)` liefern, sonst „reagiert nicht“ beim Beenden. „Zusatzmodul neu laden“ startet eine zweite Fassung, ohne die alte zu beenden (jetzt: Startzeit in der Portdatei, ältere beendet sich) – einmal fror Lightroom dabei ein → nach Änderungen besser Lightroom neu starten. Neu lauschen direkt im `onClosed` klappte nicht → Hauptschleife legt beide Sockets neu an. `LrUndo` gibt es (LrC 16)
- [ ] **Schritt 2** (2026-11-22): Ausgang `Output/LightroomBridge.swift` (liest Portdatei alle 2 s, verbindet neu, **Flusskontrolle**: pro Regler nur ein Befehl unterwegs, weitere Schritte sammeln sich bis zur Antwort, Timeout 0,3 s). Lightroom-Katalog `LightroomControls` mit eigenem ID-Bereich `0x4C52…` → Engine/Belegung/Quick Keys arbeiten unverändert, Ausgabe nach ID (Lightroom ↔ Tangent). Aktiv im Modus „Im aktiven Programm“, wenn Lightroom vorne und das Plug-in verbunden ist (vor einem Tastenprofil für Lightroom). Belegungen `…-lightroom.json` für alle drei Geräte, sinngemäß wie Capture One; Loupedeck-Farbregler = HSL-Sättigung je Farbe, Fn = Luminanz. Statusmenü zeigt Lightroom. Von Martin mit den **Quick Keys getestet ✅** (2026-11-22): „WOW, funktioniert richtig toll“, Werte (Belichtung …) im Display. **Loupedeck+ getestet ✅** (2026-11-22): fühlt sich in Capture One und Lightroom „genau gleich“ und gut an; bei ganz schnellen Bewegungen dürfte die Beschleunigung größer sein (Einstellung). **Quick Keys: schnelles Drehen fühlt sich in beiden Programmen nicht gut an** → liegt am Rad (laut Protokoll nur ~10 Meldungen/s), Messspur in der Debug-Fassung (`/tmp/stellwerk-trace.log`, Zeilen „QK“). **Martin:** TourBox in Lightroom testen
    - Messspur ausgewertet (2026-11-22, Treiber aus): (1) beim schnellen Drehen alle 5–8 Rasten **eine Raste in die Gegenrichtung** → „springt“; (2) Abstände schwanken bei gleichmäßigem Drehen 45–160 ms (Funk) → Beschleunigungsstufen ×1/×2/×4 wechselten fast jede Raste → „ruckelt“. Neu, nur für die Quick Keys (`acceleration` in der Belegung): `ignoreReverseMs` (einzelne Gegenraste verwerfen, ab der zweiten zählt sie) und `smoothing` (gleitender Mittelwert, Faktor stufenlos zwischen `mediumMs` und `fastMs`). Mit den aufgezeichneten Rasten nachgerechnet: 11 von 92 verworfen, Faktor steigt gleichmäßig. Loupedeck/TourBox unverändert. Von Martin getestet ✅ (2026-11-22): „besser, passt so“ – Quick Keys sind Nebengerät, so schnell wird selten gedreht
    - Nebenbei: `"_hinweis"` im Abschnitt `acceleration` hätte den ganzen Abschnitt verworfen (strenger Cast) → Einlesen jetzt tolerant
  - [x] **Hue/Sat/Lum** (2026-11-22): Martin meldete, die Farbregler steuern Sättigung, Lightroom zeigt aber den Reiter Farbton. Neu im Kern: `layers` in der Belegung – Tasten wählen eine Ebene der Drehregler (bleibt bis zur nächsten Ebenen-Taste, `default`). Loupedeck in Lightroom: Hue/Sat/Lum → Farbregler = HSL Farbton/Sättigung/Luminanz, Einblendung zeigt die Ebene; Fn-Luminanz entfällt. Plug-in ruft beim Drehen `revealPanel` auf (ob das den HSL-Reiter umschaltet: offen). Erster Test: Hue ✅, Sat/Lum ✗ – Statusmenü zeigte „CC 18: nicht angelernt“: **das Loupedeck schaltet Hue/Sat/Lum selbst um, die Farbregler senden dann andere CCs** (vermutlich Sat 9–16, Lum 17–24). Neu im Geräteprofil `layerCCs` (Ebene aus der CC, gilt auch ohne Tastendruck); unveränderte Kopie im Benutzerordner ersetzt. Getestet ✅: Hue/Sat/Lum steuern die richtigen Regler (Blöcke 1–8/9–16/17–24 bestätigt). Drücken zum Zurücksetzen ging nur bei Hue → Drücken sendet die Note mit derselben Nummer, also auch 9–24 → ergänzt, getestet ✅ (2026-11-22): „Perfekt“
  - Offen: Einstellungsfenster zeigt nur die Capture-One-Belegung; Kopieren/Einfügen geht über Tastenkürzel (Dialog)
- [ ] Sonst eigenes `.lrplugin` mit `LrSocket` und `LrDevelopController` (Vorbild: `logiplugin.lrplugin` lesen)
- [ ] Photomator über Tastenkürzel und Kurzbefehle – **zurückgestellt** (2026-11-22). Geprüft an Photomator 3.4.15: keine Steuer-Schnittstelle. AppleScript nur Standard-Suite (öffnen/sichern/schließen), keine Kurzbefehle-Aktionen (kein `Metadata.appintents`), URL-Schema `photomator://` ohne erkennbare Befehle, kein Tangent/MIDI, Tastenkürzel nur für Werkzeuge, nicht anpassbar. Einziger Weg für Regler wäre die Bedienungshilfen-API (Schieberegler in der Seitenleiste direkt verstellen) – ungetestet
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
- [x] ~~Capture-One-Updates könnten Parameter-IDs ändern~~ → `controls.xml` wird seit 2026-11-22 beim Start eingelesen
- Ein später installierter Tangent Hub kollidiert mit Port 64246

## Werkverzeichnis

- [x] Eintrag in `INDEX.md` und `LOGBUCH.md` (laufend nachtragen)
