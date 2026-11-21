# Hardware Controller — Projektbeschreibung

Eigene Bridge, damit Martins Hardware-Controller Foto-Apps **über deren native Schnittstellen** steuern, egal welche Hardware an welcher App hängt. Stand und offene Punkte: `TASKS.md` · Aufbau: **`ARCHITEKTUR.md`** · Git: privates Repo github.com/martindoersch/hardware-controller (`Resources/` ist ausgeschlossen).

## Ziel

1. Die nativen Schnittstellen der Apps nutzen (feine Regler, Wert-Rückmeldung), nicht nur Tastenkürzel.
2. Die Hardware von der App entkoppeln: Jedes Gerät wird einmal angebunden, jede App einmal. Dann steuert jedes Gerät jede App.
3. **Universal und erweiterbar**: Eingabe ist nicht nur Hardware, auch eine Software-Oberfläche (Maus, Touch, iPad im Browser) ist eine Quelle. Neue Geräte und Apps kommen als Adapter dazu, ohne den Kern umzubauen. Details in `ARCHITEKTUR.md`.

```
Hardware-Adapter        Bridge (Menüleisten-App)       App-Adapter
Loupedeck+    ─┐                                    ┌─ Capture One  (Tangent-Protokoll, Bridge spielt Hub)
TourBox Elite+ ─┼──►  einheitliche Aktionen  ──►    ├─ Lightroom Classic (eigenes Lua-Plugin, LR-SDK)
MIDI allgemein ─┤
Software-Surface ┘  (Touch/Maus, Web)     „Belichtung +0,05“            └─ Photomator (nur Tastenkürzel/Kurzbefehle)
```

## Hardware (vorhanden)

| Gerät | Anbindung | Notiz |
|---|---|---|
| Loupedeck+ | USB, meldet sich als **MIDI-Gerät** | ältestes Loupedeck-Modell, kein Logi-SDK nötig |
| TourBox Elite Plus | Bluetooth (BLE), gekoppelt als „Keyboard" | kein offizielles SDK; BLE-Protokoll von der Community entschlüsselt (braucht Unlock-Sequenz) |
| Tangent Element | **nicht vorhanden** | Tangent Hub bewusst **nicht installieren**: Er würde Port 64246 belegen |

## Schnittstellen der Apps (Erkenntnisse)

### Capture One: Tangent-Protokoll (TIPC) ✅ verifiziert 2026-11-21
- Capture One verbindet sich als Client mit `127.0.0.1:64246` (dort lauscht normalerweise der Tangent Hub).
- **Unsere Bridge spielt den Hub.** Capture One meldet sich mit `ApplicationDefinition` an und beantwortet Wertabfragen.
- Einstellung: `defaults write com.captureone.captureone16 TangentDeviceSupportEnableDefaultsKey -bool true` (in den Capture-One-Einstellungen sichtbar als Tangent-Unterstützung)
- Regler-Liste: `/Applications/Capture One.app/Contents/Resources/TangentSettings/controls.xml` (63 Parameter, z. B. Belichtung `0x26`, Kelvin `0x01`, Tint `0x03`, außerdem Aktionen)
- Format: Big Endian, Nachricht = `uint32 Länge` + Body; Body = `uint32 Befehl` + Daten; Strings = `uint32 Länge` + Bytes
- Wichtige Befehle Hub→App: `0x01` InitiateComms, `0x02` ParameterChange (id, float delta), `0x03` Reset, `0x04` ValueRequest, `0x08`/`0x0B` ActionOn/Off, `0x09` ModeChange
- App→Hub: `0x81` ApplicationDefinition, `0x82` ParameterValue (id, float, bool default), `0x85` ModeValue, `0x86` DisplayText
- Referenz: Hammerspoon `extensions/tangent/tangent.lua` (TIPC Rev 4); offizielles Developer Support Pack bei tangentwave.co.uk

### Lightroom Classic: Lua-Plugin (LR-SDK)
- Offizieller Weg: `.lrplugin` mit `LrDevelopController` (setzt jeden Entwicklungsregler) und `LrSocket` (lokale TCP-Verbindung zur Bridge)
- Vorhandene Vorbilder in `~/Library/Application Support/Adobe/Lightroom/Modules/`: `logiplugin.lrplugin` (Loupedeck, lesbarer Lua-Code) und `Tourbox.lrplugin` (kompilierter Bytecode)
- Open-Source-Referenz: MIDI2LR

### Photomator
- Keine Plugin-API, nur Tastenkürzel, Kurzbefehle (Shortcuts) und Bedienungshilfen → gröber als die anderen Apps

## Recherche: Gibt es das schon? (2026-11-21)

Ergebnis: **Fertige Lösung gibt es keine.** Einen Ersatz-Hub, der MIDI- oder TourBox-Eingaben über das Tangent-Protokoll an Capture One weitergibt, haben wir nicht gefunden.

| Fund | Nutzen für uns |
|---|---|
| BOME MIDI Translator, Keyboard Maestro, Midi2Macro | MIDI → Tastenkürzel, nur in eine Richtung, keine Wert-Rückmeldung. Genau das wollen wir überwinden |
| **Capture One AppleScript-API** (seit 2020, Mac) | Zweiter nativer Weg: Loupedeck selbst steuert C1 am Mac so. Kann Dinge, die Tangent nicht hat (z. B. Drehen/Keystone), ist für Drehregler aber langsamer. Als Ergänzung zum App-Adapter prüfen |
| **tangent-lightroom** (crazyscot, GitHub) | Lightroom-Plugin plus Python-Bridge, spricht mit dem Tangent Hub. Dann wäre auch LR ein Tangent-Client → **ein einheitlicher App-Adapter**. Code lesen, bevor wir ein eigenes `.lrplugin` bauen |
| **MIDI2LR** (Open Source) | Reife MIDI→Lightroom-Lösung; Loupedeck+ wäre damit in LR sofort nutzbar. Vorbild für Plugin und Beschleunigung |
| Hammerspoon `hs.tangent`, CommandPost | Tangent-Client-Code in Lua (Gegenseite unseres Hubs); CommandPost hat Adapter für Tangent, Loupedeck und den originalen TourBox (nur Final Cut Pro) |
| TourBox-Elite-BLE-Gist (AndyCappDev, Nov. 2025) | Einzige Quelle zum Protokoll, nur unter Linux getestet, noch nicht unabhängig bestätigt. Kein Mac-Treiber vorhanden |

## Ordner

| Pfad | Inhalt |
|---|---|
| `Resources/` | Installer und PDF-Handbücher (Loupedeck, Tangent, TourBox) |
| `bridge/midi_monitor.swift` | MIDI-Mitschreiber (`swift midi_monitor.swift [Gerät]`) |
| `bridge/learn_loupedeck.swift` | Geführtes Anlernen des Loupedeck+ mit Sprachansage → `bridge/mappings/loupedeck-plus.json` |
| `ARCHITEKTUR.md` | Schichten, Datenmodell, Erweiterbarkeit |
| `bridge/fake_tangent_hub.py` | Prototyp: Test-Hub für Capture One (nur Python-Standardbibliothek), interaktiv über das Terminal |

## Entscheidungen

- **Prototyp in Python** (keine Abhängigkeiten), danach **Menüleisten-App in Swift** (CoreMIDI und Network-Framework sind eingebaut, passt zu Xcode)
- **Universeller Aufbau** (2026-11-21): Kern kennt nur normierte Ereignisse und semantische Aktionen; Adapter eingebaut (Swift) oder extern über lokales WebSocket-JSON-Protokoll; Rückkanal für Werte von Anfang an
- Versionierung: privates GitHub-Repo, `Resources/` (Hersteller-Installer, 500 MB) nicht im Repo
- Startkombination: **Loupedeck+ → Capture One**, danach TourBox nativ, danach Lightroom
