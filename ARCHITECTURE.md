# Architecture — Stellwerk (universal controller bridge)

As of 2026-11 · Guiding idea: **every input drives every app.** Hardware, software surfaces and apps are interchangeable building blocks.

## Principles

1. **Universal, not a Loupedeck tool**: the core knows neither devices nor apps, only events and actions.
2. **Input is not just hardware**: a software surface (mouse, touch, iPad in a browser) is an input source like any other.
3. **Feedback from the start**: values flow back (Capture One reports exposure → display on the iPad, LED, screen).
4. **Extensible without touching the core**: new device or new app = new adapter + profile, nothing else.
5. **Configuration is data**: device profiles and mappings are JSON files, not code.

## Layers

```
 INPUT ADAPTERS             CORE                                   OUTPUT ADAPTERS
 (sources)                                                         (targets / apps)

 MIDI (Loupedeck+)  ─┐   ┌──────────────────────────────────┐   ┌─ Capture One · Tangent (TIPC)
 Serial/BLE (TourBox)┤   │ 1. Control event (normalized)     │   ├─ Capture One · AppleScript
 HID (mice, pads)   ─┼──►│ 2. Context: active app, mode      │──►├─ Lightroom · Lua plugin
 Software surface   ─┤   │ 3. Mapping → action               │   ├─ Photomator · shortcuts
 (web, touch, mouse) │   │ 4. Action → matching adapter      │   ├─ Resolve · Tangent
 OSC / external     ─┘   │ 5. Feedback → all sources         │◄──┤  Shortcuts, OSC, …
                         └──────────────────────────────────┘   └─ external adapters
        ▲                               │
        └──────── Feedback (values, text, LEDs) ◄──┘
```

### 1. Control event (input, normalized)
Every source translates its protocol into a few basic types:

| Type | Example | Data |
|---|---|---|
| `encoder` (relative) | Loupedeck dial, TourBox knob | `delta` (+1/−1, with speed) |
| `fader` (absolute) | slider, touch slider | `value` 0…1 |
| `button` | key, touch button | `down` / `up` (+ long press, double click in the core) |
| `xy` | touchpad, trackball | `x`, `y` |

Address: `source/device/control`, e.g. `midi/loupedeck-plus/knob-1`.

### 2. Device profile (data)
Describes which controls a device has and what they are called, e.g. `Mappings/loupedeck-plus.json` (created by `bridge/learn_loupedeck.swift`). A software surface ships its own profile.

### 3. Actions (semantic, app-neutral)
A shared vocabulary so one mapping works in several apps:

- Parameters: `develop.exposure`, `develop.contrast`, `develop.wb.temp` … with operations `adjust(delta)`, `set(value)`, `reset`
- Commands: `nav.next`, `nav.prev`, `rate.3`, `edit.undo`, `view.zoom` …
- Escape hatch for special cases: app-specific action, e.g. `captureone:param/0x26`

Each output adapter declares which actions it supports (**capabilities**). If the active app can't do something, the control stays empty or falls back to another adapter (Tangent → AppleScript → shortcut).

### 4. Mapping (data)
`Control + context (app, mode/page) → action + options (step size, acceleration, invert)`. One mapping per device, with sections per app and an app-neutral default.

### 5. Feedback
Output adapters report values back (`develop.exposure = 0.35`). The core distributes them to every source that can display something: software surface, LEDs, displays, later TourBox haptics.

## Extensibility: two kinds of adapters

| Kind | For | Technology |
|---|---|---|
| **Built-in** | performance-critical, system access (MIDI, serial/BLE, Tangent hub) | Swift protocols `InputAdapter` / `OutputAdapter` in the menu bar app |
| **External** | software surfaces, experiments, adapters in other languages | **local WebSocket protocol (JSON)**: a source reports profile + events, a target reports capabilities + values |

The external protocol is the **"universal input device" interface**: a web surface on the iPad, a Python script or a future device connects there without rebuilding the app. The bridge serves the web surface itself (local server, iPad/iPhone on the same network).

Sketch of a message:
```json
{ "type": "control", "source": "surface/ipad", "control": "slider-1", "kind": "fader", "value": 0.42 }
{ "type": "feedback", "action": "develop.exposure", "value": 0.35, "text": "+0.35 EV" }
```

Before fixing the format, evaluate **OSC** (common in lighting/audio, TouchOSC as a ready-made touch surface), possibly as an additional input, not as the core format.

## Current state vs. target

The app today is pragmatic: the engine maps device controls directly to Capture One parameters/actions or shortcuts (per device, per app). The semantic action vocabulary, adapter protocols and the external WebSocket interface are the target and are introduced step by step (see `TASKS.md`, phase 4).
