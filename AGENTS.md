# Stellwerk — Guide for agents

> Read this first. It is the single source of project knowledge for coding agents (Claude Code reads it via `CLAUDE.md`). Roadmap and progress: `TASKS.md` · Design: `ARCHITECTURE.md` · User docs: `README.md`.
> Reply in the language the user writes in. The original author works in German; `TASKS.md` and code comments are German.

Stellwerk is a macOS menu bar app that lets hardware controllers drive photo apps **through their native interfaces**, independent of which device talks to which app. Named after the railway signal box: many levers, many switches, wired centrally.

## Goals

1. Use the apps' native interfaces (fine dials, value feedback), not just keyboard shortcuts.
2. Decouple hardware from apps: each device is connected once, each app once, then every device drives every app.
3. **Universal and extensible**: input is not only hardware; a software surface (mouse, touch, iPad in a browser) is a source too. New devices and apps arrive as adapters without touching the core. See `ARCHITECTURE.md`.

```
Input adapters          Bridge (menu bar app)          Output adapters
Loupedeck+     ─┐                                    ┌─ Capture One  (Tangent protocol, Stellwerk acts as the hub)
TourBox Elite+ ─┼──►  unified actions  ──►           ├─ Any frontmost app (shortcuts, menu items)
MIDI general   ─┤    "Exposure +0.05"                ├─ Lightroom Classic (planned: Lua plugin, LR SDK)
Software surface┘                                    └─ Photomator (planned: shortcuts only)
```

## Repository layout

| Path | Content |
|---|---|
| `app/` | **Menu bar app**, Xcode project `Stellwerk.xcodeproj`, no sandbox. `Core/` (Engine, Mapping, UserSettings), `Input/` (MIDI, TourBox serial), `Output/` (Tangent hub, keys/menu items/event tap), `UI/` (status menu, settings, HUD) |
| `app/Stellwerk/Mappings/` | Default device profiles and mappings (JSON, bundled). Users override them in `~/Library/Application Support/Stellwerk/Mappings/`; settings overlay in `…/Stellwerk/settings.json` |
| `app/Stellwerk/Localizable.xcstrings` | UI strings. **Source language is German** (keys are German text), English translations alongside |
| `app/Stellwerk/Controls.xcstrings` | Display names for device control names (the names themselves are keys in JSON and must not change) |
| `app/Stellwerk/Stellwerk.icon` | App icon (Icon Composer), ⌥ glyph on lime |
| `bridge/` | Prototypes and test tools (Swift scripts, Python stdlib only). `bridge/mappings/` is only for the prototype |
| `bridge/fake_loupedeck.swift` | Virtual MIDI device "Loupedeck Test": test Stellwerk without hardware |
| `bridge/fake_captureone.py` | Test client that pretends to be Capture One |
| `bridge/midi_monitor.swift`, `bridge/tourbox_monitor.swift` | Raw data loggers for new hardware |
| `bridge/learn_loupedeck.swift` | Guided learning of Loupedeck+ controls with voice prompts |
| `bridge/parse_controls.py` | Parses Capture One's `controls.xml` → `docs/capture-one-controls.md` (lookup table) + `bridge/mappings/capture-one-controls.json` (prototype). **Both are generated locally and git-ignored**: the data belongs to Capture One and must not be committed |
| `docs/` | TourBox USB protocol (+ the locally generated Capture One table) |

## Build, run, test

- Build with Xcode (`app/Stellwerk.xcodeproj`, scheme *Stellwerk*). Inside Xcode use the `BuildProject` tool; from a shell: `xcodebuild -project app/Stellwerk.xcodeproj -scheme Stellwerk build`. Keep the build free of warnings.
- Contributors must set their own signing team and bundle ID; don't commit those changes back.
- Without hardware: run the app, then `swift bridge/fake_loupedeck.swift`. For hub logic: `python3 bridge/fake_captureone.py`.
- With hardware: the human tests on real devices. Ask for a short test and wait for the result before marking anything as verified.
- **Capture One connects only at its own launch.** Stellwerk must run first (or use the in-app restart button).

## Conventions

- Swift, SwiftUI, Observation (`@Observable`), async/await; no Combine. 4-space indent. Comments in German are fine; match the surrounding file.
- **Configuration is data**: devices and mappings are JSON, not code. JSON may contain `"_hinweis"` (note) keys; parsers must skip them (a strict cast once dropped a whole section).
- **Localization**: every user-visible string is localizable with the German text as key. Add the English translation to `Localizable.xcstrings` in the same change. Use `String(localized:)` for strings built outside views; `Text(verbatim:)` for data that must not be translated.
- Security: the Tangent hub binds to `127.0.0.1` only, never `*` (otherwise it is reachable over Wi-Fi).
- Don't commit vendor installers, manuals, or vendor files copied from app bundles.
- After a change: update `TASKS.md` (check off, add findings with date), record lasting knowledge here. Commit messages short, imperative, German or English.

## Adding things

- **New device:** write or reuse a monitor script, have the human press every control, document the codes (`docs/`), add a device profile + default mapping JSON in `app/Stellwerk/Mappings/`, an input in `Input/`, and display names in `Controls.xcstrings` if needed.
- **New app:** prefer a native interface (Tangent, plugin SDK, AppleScript) over shortcuts. Record the findings below before coding.
- **New UI language:** add it in Xcode (Project → Info → Localizations) and translate both string catalogs.

## Hardware

| Device | Connection | Notes |
|---|---|---|
| Loupedeck+ | USB, appears as **MIDI device** | Channel 1. Turning = relative CC (`01` = +1, `7F` = −1), pressing = note with the same number. CCs 33–48 + 1–8 (color dials). Top dials send ~3× more steps than color dials → step size per dial. No Logi software needed |
| TourBox Elite Plus | **USB serial** (CDC), 115200 8N1 | Sends nothing until unlocked: `55 00 07 88 94 00 1A FE`, wait 300 ms, then a 94-byte config. One byte per event, bit 7 = release, bit 6 = direction. Details (German): `docs/tourbox-protokoll.md`. TourBox Console must be quit. BLE not done yet |
| Tangent panels | not supported as input | Don't install the Tangent Hub: it occupies port 64246 |

## App interfaces (findings)

### Capture One: Tangent protocol (TIPC), verified
- Capture One connects as a client to `127.0.0.1:64246` (normally the Tangent Hub). **Stellwerk plays the hub.** Capture One registers with `ApplicationDefinition` and answers value requests.
- Connects **only at launch** and reads the Tangent switch only at launch; no reconnect, no AppleScript hook. Restart is the only way.
- Enable: `defaults write com.captureone.captureone16 TangentDeviceSupportEnableDefaultsKey -bool true` (visible in Capture One settings).
- Control list: `/Applications/Capture One.app/Contents/Resources/TangentSettings/controls.xml` (63 parameters, 429 actions, one mode "Default"). **The app reads it at launch from the installed Capture One** (`Catalog.fromInstalledCaptureOne`, located via bundle ID), so IDs stay current after updates and no vendor data is shipped. Fallback: a `capture-one-controls.json` in the user mappings folder. Same folder has Tangent's default maps (`element-*-map.xml`, `wave-map.xml`, `ripple-map.xml`), useful as layout templates.
- Key IDs: exposure `0x26`, Kelvin `0x01`, tint `0x03`, contrast `0x28`, saturation `0x2C`, highlights `0x2E`, shadows `0x30`, white `0x250`, black `0x251`, clarity `0x32`, structure `0x33`. Actions: next/prev image `0x8E`/`0x8D`, stars 0–5 `0x106`, `0x101`–`0x105`, color tags `0x107`–`0x10E`, reset `0x112`, copy/apply adjustments `0xFC`/`0xFD`, before/after `0x252`, auto `0x111`, zoom fit/100 % `0xC4`/`0xC5`.
- **Undo/Redo (`0x77`/`0x78`) have no effect** → Stellwerk clicks the matching menu item via the Accessibility API (language-independent), keystroke as fallback. Paste `0xFD` opened a dialog and hung → menu ⇧⌘V.
- Wire format: big endian, message = `uint32 length` + body; body = `uint32 command` + data; strings = `uint32 length` + bytes.
- Hub→app: `0x01` InitiateComms, `0x02` ParameterChange (id, float delta), `0x03` Reset, `0x04` ValueRequest, `0x08`/`0x0B` ActionOn/Off, `0x09` ModeChange. App→hub: `0x81` ApplicationDefinition, `0x82` ParameterValue (id, float, bool default), `0x85` ModeValue, `0x86` DisplayText.
- References: Hammerspoon `extensions/tangent/tangent.lua` (TIPC rev 4); official Developer Support Pack at tangentwave.co.uk.

### Other apps (frontmost)
- Buttons send shortcuts; where a menu item exists, Stellwerk clicks it via Accessibility (works regardless of keyboard layout). The target app is brought to front first.
- Loupedeck modifier buttons are held as real modifiers; an **event tap** adds them to real mouse/keyboard events (posted modifier events alone don't affect real clicks).

### Lightroom Classic (planned)
- Official route: `.lrplugin` with `LrDevelopController` + `LrSocket` (local TCP to the bridge). Check **tangent-lightroom** (crazyscot, GitHub) first: it might make LR a Tangent client too. MIDI2LR is the mature open-source reference.

### Photomator (planned)
- No plugin API: shortcuts, Shortcuts app, Accessibility only.

## Prior art (researched 2026-11)

No existing tool forwards MIDI/TourBox input to Capture One over Tangent. Related: BOME MIDI Translator, Keyboard Maestro (shortcuts only, no feedback) · Capture One AppleScript API (slower, but covers things Tangent lacks, e.g. rotation) · tangent-lightroom · MIDI2LR · Hammerspoon `hs.tangent`, CommandPost · tuxbox (TourBox on Linux, source of the unlock/config bytes) · TourBox Elite BLE gist by AndyCappDev (unverified on Mac).

## Decisions

- Prototype in Python/Swift scripts, product as a Swift menu bar app (CoreMIDI and Network framework built in).
- Universal design: the core knows only normalized events and semantic actions; adapters built in (Swift) or external via a local WebSocket JSON protocol (planned); value feedback from the start.
- Start combination Loupedeck+ → Capture One, then TourBox, then Lightroom.
- License MIT. Vendor installers and manuals are not stored in the repo.
