# Architektur — Stellwerk (universelle Controller-Bridge)

Stand: 2026-11-21 · Leitidee: **Jede Eingabe steuert jede App.** Hardware, Software-Oberflächen und Apps sind austauschbare Bausteine.

## Grundprinzipien

1. **Universal statt Loupedeck-Tool** — der Kern kennt weder Geräte noch Apps, nur Ereignisse und Aktionen.
2. **Eingabe ist nicht gleich Hardware** — eine Software-Oberfläche (Maus, Touch, iPad im Browser) ist eine Eingabequelle wie jede andere.
3. **Rückkanal von Anfang an** — Werte fließen zurück (Capture One meldet Belichtung → Anzeige auf dem iPad, LED, Display).
4. **Erweiterbar ohne Kernumbau** — neues Gerät oder neue App = neuer Adapter + Profil, sonst nichts.
5. **Konfiguration als Daten** — Geräteprofile und Mappings sind JSON-Dateien, kein Code.

## Schichten

```
 EINGABE-ADAPTER            KERN                                   AUSGABE-ADAPTER
 (Quellen)                                                         (Ziele / Apps)

 MIDI (Loupedeck+)  ─┐   ┌──────────────────────────────────┐   ┌─ Capture One · Tangent (TIPC)
 BLE (TourBox)      ─┤   │ 1. Control-Ereignis (normiert)    │   ├─ Capture One · AppleScript
 HID (Maus, Pads)   ─┼──►│ 2. Kontext: aktive App, Modus     │──►├─ Lightroom · Lua-Plugin
 Software-Surface   ─┤   │ 3. Mapping → Aktion               │   ├─ Photomator · Tastenkürzel
 (Web, Touch, Maus) │    │ 4. Aktion → passender Adapter     │   ├─ Resolve · Tangent
 OSC / externe      ─┘   │ 5. Rückmeldung → alle Quellen     │◄──┤  Shortcuts, OSC, …
                         └──────────────────────────────────┘   └─ externe Adapter
        ▲                               │
        └──────── Feedback (Werte, Texte, LEDs) ◄──┘
```

### 1. Control-Ereignis (Eingabe, normiert)
Jede Quelle übersetzt ihr Protokoll in wenige Grundtypen:

| Typ | Beispiel | Daten |
|---|---|---|
| `encoder` (relativ) | Loupedeck-Drehregler, TourBox-Knob | `delta` (+1/−1, mit Tempo) |
| `fader` (absolut) | Schieberegler, Touch-Slider | `value` 0…1 |
| `button` | Taste, Touch-Button | `down` / `up` (+ Long-Press, Doppelklick im Kern) |
| `xy` | Touchpad, Trackball | `x`, `y` |

Adresse: `quelle/gerät/control`, z. B. `midi/loupedeck-plus/knob-1`.

### 2. Geräteprofil (Daten)
Beschreibt, welche Controls ein Gerät hat und wie sie heißen, z. B. `mappings/loupedeck-plus.json` (entsteht durch `learn_loupedeck.swift`). Eine Software-Surface liefert ihr Profil selbst mit.

### 3. Aktionen (semantisch, app-neutral)
Gemeinsames Vokabular, damit ein Mapping in mehreren Apps funktioniert:

- Parameter: `develop.exposure`, `develop.contrast`, `develop.wb.temp` … mit Operation `adjust(delta)`, `set(value)`, `reset`
- Befehle: `nav.next`, `nav.prev`, `rate.3`, `edit.undo`, `view.zoom` …
- Ausweg für Spezielles: app-eigene Aktion, z. B. `captureone:param/0x26`

Jeder Ausgabe-Adapter meldet, welche Aktionen er kann (**Capabilities**). Kann die aktive App etwas nicht, bleibt das Control leer oder fällt auf einen anderen Adapter zurück (Tangent → AppleScript → Tastenkürzel).

### 4. Mapping (Daten)
`Control + Kontext (App, Modus/Seite) → Aktion + Optionen (Schrittweite, Beschleunigung, Umkehr)`. Ein Mapping pro Gerät, mit Abschnitten pro App und einem App-neutralen Standard.

### 5. Feedback
Ausgabe-Adapter melden Werte zurück (`develop.exposure = 0,35`). Der Kern verteilt sie an alle Quellen, die etwas anzeigen können: Software-Surface, LEDs, Displays, später TourBox-Haptik.

## Erweiterbarkeit: zwei Arten von Adaptern

| Art | Wofür | Technik |
|---|---|---|
| **Eingebaut** | Performance-kritisch, Systemzugriff (MIDI, BLE, Tangent-Hub) | Swift-Protokolle `InputAdapter` / `OutputAdapter` in der Menüleisten-App |
| **Extern** | Software-Surfaces, Experimente, Adapter in anderen Sprachen | **lokales WebSocket-Protokoll (JSON)**: Quelle meldet Profil + Ereignisse, Ziel meldet Capabilities + Werte |

Das externe Protokoll ist die **„Universal Input Device"-Schnittstelle**: Eine Web-Oberfläche auf dem iPad, ein Python-Skript oder ein künftiges Gerät dockt dort an, ohne dass die App neu gebaut wird. Die Bridge liefert die Web-Oberfläche selbst aus (lokaler Server, iPad/iPhone im selben WLAN).

Skizze einer Nachricht:
```json
{ "type": "control", "source": "surface/ipad", "control": "slider-1", "kind": "fader", "value": 0.42 }
{ "type": "feedback", "action": "develop.exposure", "value": 0.35, "text": "+0,35 EV" }
```

Vor dem endgültigen Format prüfen: **OSC** (verbreitet bei Licht/Audio, TouchOSC als fertige Touch-Oberfläche) — eventuell als zusätzlicher Eingang, nicht als Kernformat.

## Was das für die Phasen heißt

- Python-Prototyp darf direkt sein (Loupedeck → C1), dient nur zum Lernen.
- Ab der Swift-App: zuerst Kern (Ereignis, Aktion, Mapping, Feedback-Bus), dann Adapter einzeln andocken.
- Software-Surface früh einplanen, sie ist das beste Testwerkzeug (ohne Hardware testen, Werte sehen).
