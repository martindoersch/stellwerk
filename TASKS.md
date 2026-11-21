# Tasks — Stellwerk

Stand: 2026-11-21 · Beschreibung und Technik in `AGENTS.md`

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
- [ ] Redo `0x78` testen
- [ ] Doppelte Aktionen klären: z. B. Copy Adjustments `0xFC` (Adjustments) und `0x16C` (Cursor Tools), Rotate Left `0xF9` und `0x158`. Welche macht was?
- [ ] Modi: Capture One meldet nur **einen** Modus („Default", `0x00010001`). Modi pro Werkzeug muss also die Bridge selbst verwalten (Ebenen im Mapping), nicht Capture One. Kurz testen, ob `ModeChange` trotzdem etwas bewirkt
- [ ] Verhalten klären: Welcher Wert gilt bei mehreren ausgewählten Bildern? Was passiert ohne geöffnetes Bild?
- [ ] AppleScript-Wörterbuch von Capture One ansehen: Welche Regler fehlen in `controls.xml`, sind aber per AppleScript erreichbar (z. B. Drehen, Keystone)? Als Ergänzung für Tasten, nicht für Drehregler

## Phase 2 — Loupedeck+ → Capture One

- [x] Loupedeck+ angesteckt: meldet sich als **MIDI-Gerät** „Loupedeck+" (Ein- und Ausgang), kein Treiber nötig, Loupedeck-Software muss nicht laufen
- [x] Runde 1: 22 Drehregler mitgeschnitten (`bridge/mitschnitt-runde1-regler.log`): Kanal 1, Drehen = CC relativ (`01` = +1, `7F` = −1), Drücken = Note mit gleicher Nummer. CCs 33–48 (14 Regler) + 1–8 (Farbregler). Obere Regler senden ca. 3× so viele Schritte wie die Farbregler → Schrittweite pro Regler
- [ ] **Martin:** `cd bridge && swift learn_loupedeck.swift` – geführtes Anlernen aller Regler und Tasten mit Sprachansage → `bridge/mappings/loupedeck-plus.json`
- [ ] Loupedeck-Software beenden oder Gerät freigeben, falls sie es blockiert
- [x] Belegung `bridge/mappings/loupedeck-plus-captureone.json`: Beschriftung → Capture-One-Regler/-Aktion/Tastenkürzel, `perTick` pro Regler, Beschleunigung einstellbar
- [x] Bridge-Prototyp `bridge/stellwerk.swift` (Swift, CoreMIDI + Network): MIDI rein → Tangent raus, Beschleunigung, Deltas alle 15 ms gebündelt, Drücken = zurücksetzen, Startwerte abfragen, Simulation übers Terminal. **Mit echtem Capture One getestet** ✅ (Regler, Reset, Aktionen), Test-Client `bridge/fake_captureone.py`
- [ ] Nach dem Anlernen: echte Regler testen, `perTick` und Beschleunigung nach Gefühl einstellen
- [ ] Belegung für die 8 Farbregler und P1–P8/C1–C6 überlegen (Capture One hat über Tangent kein HSL pro Farbe → Color Balance? Ebenen?)

## Phase 2b — Software-Surface (früh, als Testwerkzeug)

- [ ] Web-Oberfläche (Touch/Maus) von der Bridge ausgeliefert, Regler + Tasten, zeigt Werte aus Capture One live
- [ ] Spricht schon das externe Adapter-Protokoll (WebSocket, JSON) → legt das Format praktisch fest
- [ ] Vorher kurz TouchOSC/OSC prüfen: fertige Oberfläche statt Eigenbau?
- [ ] Grundsatz: nur für Martin bauen, klein starten, aber nichts verbauen (neutrale Aktionen, Adapter austauschbar)

## Phase 3 — TourBox Elite Plus nativ

- [ ] BLE-Protokoll anhand des Community-Gists (AndyCappDev, „TourBox Elite BLE Protocol") prüfen
- [ ] Verbindung über CoreBluetooth testen, inklusive Unlock-Sequenz; Konflikt mit TourBox Console klären (muss die App beendet sein?)
- [ ] Haptik/Feedback der Elite nutzen, falls das Protokoll es hergibt
- [ ] Fallback: TourBox Console sendet Tastenkürzel → Bridge übersetzt

## Phase 4 — Menüleisten-App (Swift)

- [ ] Kern nach `ARCHITEKTUR.md`: Control-Ereignis, Aktions-Vokabular, Mapping-Format, Feedback-Bus, aktive App erkennen
- [ ] Swift-Protokolle `InputAdapter` / `OutputAdapter` mit Capabilities
- [ ] Externes Adapter-Protokoll (lokaler WebSocket, JSON) festlegen; OSC als Alternative prüfen
- [ ] Tangent-Hub-Server in Swift (Network-Framework), MIDI über CoreMIDI
- [ ] Menüleiste: Verbindungsstatus pro Gerät und App, Mapping wählen; Markenfarbe Lime `#C7D300`
- [ ] Autostart, Code-Signierung

## Phase 5 — Lightroom Classic und weitere Apps

- [ ] Zuerst **tangent-lightroom** (crazyscot) prüfen: Macht es Lightroom zum Tangent-Client, braucht unsere Bridge keinen eigenen LR-Adapter
- [ ] Zwischenlösung: MIDI2LR direkt mit Loupedeck+ testen
- [ ] Sonst eigenes `.lrplugin` mit `LrSocket` und `LrDevelopController` (Vorbild: `logiplugin.lrplugin` lesen)
- [ ] Photomator über Tastenkürzel und Kurzbefehle
- [ ] Optional: DaVinci Resolve (kann ebenfalls Tangent)

## Hilfsmittel (Vorschläge aus der Recherche, 2026-11-21)

- [ ] **Martin:** Tangent Developer Support Pack holen (Registrierung auf tangentwave.co.uk). Das ist die offizielle TIPC-Spezifikation statt Nachbau aus dem Hammerspoon-Code
- [ ] Installer in `Resources/` mit `pkgutil --expand` auspacken, **nicht installieren** (Port 64246!): Loupedeck enthält vermutlich die AppleScript-Anbindung an Capture One und die Belegung des Loupedeck+ als Vorlage für Phase 2; der Tangent Hub vermutlich die Standard-Maps für Capture One und eventuell SDK-Teile
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
