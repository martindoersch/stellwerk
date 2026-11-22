# Stellwerk

**One bridge, any controller, any photo app.** Stellwerk is a macOS menu bar app that lets hardware controllers drive photo editing apps through their **native interfaces**: fine-grained dials with live value feedback, not just keyboard shortcuts.

Named after the railway *Stellwerk* (signal box): many levers set many switches, wired together in one place. The icon is the ⌥ key, which looks like a railway switch.

🇩🇪 [Deutsche Version](README.de.md)

## What it does today

| Controller | Connection | Driver needed? |
|---|---|---|
| Loupedeck+ | USB, shows up as a MIDI device | No, the Loupedeck software doesn't have to run |
| TourBox Elite Plus | USB cable (serial) | No, quit TourBox Console while Stellwerk runs |

| App | Interface | |
|---|---|---|
| Capture One | Tangent protocol (TIPC): Stellwerk plays the Tangent Hub | Dials, values, actions |
| Any app (frontmost) | Keyboard shortcuts and menu items | Buttons per app profile |

- Dials with adjustable speed, acceleration and fine/coarse modifiers (⌥ = fine, ⇧ = coarse)
- Every button remappable in Settings: Capture One action, menu item, custom shortcut, or off; Fn layer
- Modes like the Loupedeck software (stars ↔ color labels ↔ modifier keys), on-screen HUD when switching
- Loupedeck modifier buttons act as real ⇧ ⌃ ⌘ ⌥ keys, even with mouse clicks
- German and English UI

Planned: Lightroom Classic, Photomator, TourBox over Bluetooth, a web/touch surface for iPad. See [ARCHITECTURE.md](ARCHITECTURE.md) and [TASKS.md](TASKS.md) (German).

> **⚠️ Developers only.** There is no signed or notarized download. You build Stellwerk yourself in Xcode (a free Apple ID is enough). It's early, built for one person's desk and tested there. Expect rough edges.

## Requirements

- macOS 26.5 or later, Xcode 26.5 or later
- Capture One (Mac) for the Tangent connection. Stellwerk reads Capture One's control list (`TangentSettings/controls.xml`) from the installed app at launch; it is not shipped with Stellwerk.
- **Do not install the Tangent Hub.** It uses the same port (`127.0.0.1:64246`) that Stellwerk listens on.

## Install (build from source, developers only)

There is no signed download, so you build it yourself. It takes a few minutes if you've used Xcode before.

1. Clone the repo and open `app/Stellwerk.xcodeproj` in Xcode.
2. Target *Stellwerk* → *Signing & Capabilities*: pick your own team (a free Apple ID works) and change the bundle identifier to something of yours, e.g. `com.yourname.Stellwerk`.
3. *Product → Run*. The ⌥ icon appears in the menu bar.
4. Grant **Accessibility** access when asked (System Settings → Privacy & Security → Accessibility). Stellwerk needs it to click menu items and to add modifier keys to mouse clicks.
5. Enable Tangent support in Capture One (Settings → Tangent), or in Terminal:
   ```sh
   defaults write com.captureone.captureone16 TangentDeviceSupportEnableDefaultsKey -bool true
   ```
6. **Start Stellwerk before Capture One.** Capture One only connects at launch. If it's already running, use *Restart Capture One* in the Stellwerk menu.

## Customize

- Settings window (menu → Settings): dial speed, acceleration, button assignments per device and per app.
- Mappings are JSON: defaults ship in `app/Stellwerk/Mappings/`, your overrides live in `~/Library/Application Support/Stellwerk/` (`Mappings/` and `settings.json`). The menu has a shortcut to that folder.

## Test without hardware

| Tool | Purpose |
|---|---|
| `swift bridge/fake_loupedeck.swift` | Virtual MIDI device "Loupedeck Test" that presses a few buttons |
| `python3 bridge/fake_captureone.py` | Pretends to be Capture One and talks to the hub (use with the prototype `bridge/stellwerk.swift`) |
| `swift bridge/midi_monitor.swift` | Logs raw MIDI from any device |
| `swift bridge/tourbox_monitor.swift` | Logs raw TourBox serial data |

## Working on Stellwerk with AI agents

Stellwerk was built with coding agents (Claude Code, OpenCode) in Xcode, and the repo is set up so you can continue the same way.

| File | For whom | Content |
|---|---|---|
| [`AGENTS.md`](AGENTS.md) | Agents (and humans) | Project facts, protocol findings, conventions, how to build, test and extend |
| [`CLAUDE.md`](CLAUDE.md) | Claude Code | Just points to `AGENTS.md`, so there's one source |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Everyone | Layers, data model, how adapters plug in |
| [`TASKS.md`](TASKS.md) | Agents and you | Roadmap and log of what was tried and verified (German) |
| `docs/` | Reference | TourBox USB protocol. Generate the Capture One control table locally with `python3 bridge/parse_controls.py` |

**The workflow:**

1. Open the repo folder in your agent (Claude Code, OpenCode, Codex, Cursor …) or use the coding assistant inside Xcode. The agent reads `AGENTS.md` automatically.
2. Describe what you want in plain language, e.g. *"Add my Loupedeck CT"*, *"Map the TourBox knob to Capture One's Clarity"*, *"Add an Affinity Photo profile"*.
3. For new hardware, let the agent write a small monitor script first (see `bridge/*_monitor.swift`), press every button, and record the codes. Real data beats guessing.
4. The agent builds in Xcode and tests with the fake devices. You test on the real hardware and report back.
5. Findings and decisions go into `AGENTS.md`, progress into `TASKS.md`. That way the next session (yours or someone else's) starts where the last one stopped.

Contributions are welcome: device profiles, app adapters, translations. Please open an issue first for bigger changes.

## Disclaimer

Stellwerk is an independent project, not affiliated with or endorsed by Capture One, Tangent Wave, Logitech/Loupedeck, TourBox Tech, or Adobe. All trademarks belong to their owners. Protocol details were worked out from public sources and by observing the devices; see `AGENTS.md` for references. Use at your own risk, and back up your catalogs.

## License

[MIT](LICENSE) © 2026 Martin Dörsch
