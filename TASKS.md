# Tasks — Hardware Controller

Stand: 2026-11-21 · Beschreibung und Technik in `AGENTS.md`

## Erledigt

- [x] Universelle Architektur festgehalten (`ARCHITEKTUR.md`): Eingabe-Adapter inkl. Software-Surface, semantische Aktionen, Mapping, Feedback, externe Adapter
- [x] Privates Git-Repo angelegt (github.com/martindoersch/hardware-controller)

- [x] Resources gesichtet (Loupedeck-, Tangent-Installer, PDFs; TourBox-Datei war die Android-`.apk`, die Mac-App ist schon installiert)
- [x] Schnittstellen analysiert: Capture One über Tangent (TIPC), Lightroom über Lua-SDK, Photomator nur Tastenkürzel
- [x] Tangent-Unterstützung in Capture One aktiviert (`TangentDeviceSupportEnableDefaultsKey = 1`)
- [x] Prototyp `bridge/fake_tangent_hub.py`: **Capture One verbindet sich und meldet Werte** (Belichtung gelesen)
- [x] Recherche „Gibt es das schon?": nein, Details in `AGENTS.md`. Neue Prüfpunkte unten (AppleScript, tangent-lightroom, MIDI2LR)

## Phase 1 — Capture One nativ (über den Test-Hub)

- [x] Schreiben verifiziert: Belichtung 0 → 0,1 → 0,2 → 0,1 → 0, Capture One meldet jeden Wert zurück ✅
- [x] Wiederverbinden geprüft: Capture One verbindet sich **nur beim Start** → Bridge muss vor Capture One laufen (oder Capture One neu starten). Später: Bridge startet beim Login
- [ ] `controls.xml` komplett auswerten: alle Parameter-IDs **und Aktions-IDs** (nächstes Bild, Bewertung, Zurücksetzen …) als Tabelle
- [ ] Modi testen (`ModeChange` / `ModeValue`), z. B. pro Werkzeug
- [ ] Verhalten klären: Welcher Wert gilt bei mehreren ausgewählten Bildern? Was passiert ohne geöffnetes Bild?
- [ ] AppleScript-Wörterbuch von Capture One ansehen: Welche Regler fehlen in `controls.xml`, sind aber per AppleScript erreichbar (z. B. Drehen, Keystone)? Als Ergänzung für Tasten, nicht für Drehregler

## Phase 2 — Loupedeck+ → Capture One

- [x] Loupedeck+ angesteckt: meldet sich als **MIDI-Gerät** „Loupedeck+" (Ein- und Ausgang), kein Treiber nötig, Loupedeck-Software muss nicht laufen
- [x] Runde 1: 22 Drehregler mitgeschnitten (`bridge/mitschnitt-runde1-regler.log`): Kanal 1, Drehen = CC relativ (`01` = +1, `7F` = −1), Drücken = Note mit gleicher Nummer. CCs 33–48 (14 Regler) + 1–8 (Farbregler). Obere Regler senden ca. 3× so viele Schritte wie die Farbregler → Schrittweite pro Regler
- [ ] **Martin:** `cd bridge && swift learn_loupedeck.swift` – geführtes Anlernen aller Regler und Tasten mit Sprachansage → `bridge/mappings/loupedeck-plus.json`
- [ ] Loupedeck-Software beenden oder Gerät freigeben, falls sie es blockiert
- [ ] Mapping-Datei (JSON/YAML): Loupedeck-Regler → Capture-One-Parameter, Tasten → Aktionen
- [ ] Bridge-Prototyp: MIDI rein → Tangent-ParameterChange raus (Beschleunigung bei schnellem Drehen)

## Phase 3 — TourBox Elite Plus nativ

- [ ] BLE-Protokoll anhand des Community-Gists (AndyCappDev, „TourBox Elite BLE Protocol") prüfen
- [ ] Verbindung über CoreBluetooth testen, inklusive Unlock-Sequenz; Konflikt mit TourBox Console klären (muss die App beendet sein?)
- [ ] Haptik/Feedback der Elite nutzen, falls das Protokoll es hergibt
- [ ] Fallback: TourBox Console sendet Tastenkürzel → Bridge übersetzt

## Phase 4 — Menüleisten-App (Swift)

- [ ] Kern nach `ARCHITEKTUR.md`: Control-Ereignis, Aktions-Vokabular, Mapping-Format, Feedback-Bus, aktive App erkennen
- [ ] Swift-Protokolle `InputAdapter` / `OutputAdapter` mit Capabilities
- [ ] Externes Adapter-Protokoll (lokaler WebSocket, JSON) festlegen; OSC als Alternative prüfen
- [ ] **Software-Surface**: Web-Oberfläche (Touch/Maus) von der Bridge ausgeliefert, zeigt Werte live — auch als Testwerkzeug ohne Hardware
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
