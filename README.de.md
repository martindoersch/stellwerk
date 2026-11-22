# Stellwerk

**Eine Bridge, jeder Controller, jede Foto-App.** Stellwerk ist eine Menüleisten-App für macOS. Sie lässt Hardware-Controller Foto-Apps über deren **native Schnittstellen** steuern: feine Drehregler mit Wert-Rückmeldung statt nur Tastenkürzel.

Name nach dem Bahn-Stellwerk: viele Hebel stellen viele Weichen, zentral verschaltet. Das Icon ist die ⌥-Taste, sie sieht aus wie eine Weiche.

🇬🇧 [English version](README.md) (ausführlicher)

## Was es heute kann

- **Geräte:** Loupedeck+ (USB/MIDI) und TourBox Elite Plus (USB-Kabel), ohne Hersteller-Software
- **Apps:** Capture One über das Tangent-Protokoll (Stellwerk spielt den Tangent Hub), dazu jede App über Tastenkürzel und Menüeinträge (Profile je Programm)
- Geschwindigkeit, Beschleunigung, Fein/Grob, jede Taste umbelegbar, Fn-Ebene, Modi mit Einblendung
- Oberfläche auf Deutsch und Englisch

## Installieren

> **⚠️ Nur für Entwickler:innen.** Es gibt keine signierte Version zum Herunterladen. Stellwerk wird selbst in Xcode gebaut (eine kostenlose Apple-ID reicht).

Selbst bauen mit Xcode (macOS 26.5 oder neuer):

1. `app/Stellwerk.xcodeproj` öffnen, unter *Signing & Capabilities* eigenes Team und eigene Bundle-ID eintragen
2. *Product → Run*, Bedienungshilfen erlauben
3. In Capture One die Tangent-Unterstützung einschalten
4. **Stellwerk vor Capture One starten**. Den Tangent Hub nicht installieren, er belegt denselben Port

Details, Testwerkzeuge ohne Hardware und Hinweise: [README.md](README.md).

## Mit KI-Agenten weiterbauen

Stellwerk ist mit Coding-Agents (Claude Code, OpenCode) in Xcode entstanden. Alles, was ein Agent wissen muss, steht in [`AGENTS.md`](AGENTS.md): Projektwissen, Protokolle, Konventionen, Bauen und Testen. Claude Code liest es über `CLAUDE.md` mit. Stand und Fahrplan stehen in [`TASKS.md`](TASKS.md).

Ablauf: Ordner im Agenten öffnen, Wunsch in normaler Sprache beschreiben („Bind meinen Loupedeck CT an"), bei neuer Hardware zuerst Rohdaten mitschreiben lassen, dann bauen und testen. Erkenntnisse kommen in `AGENTS.md`, Fortschritt in `TASKS.md`.

## Lizenz

[MIT](LICENSE) © 2026 Martin Dörsch. Unabhängiges Projekt, nicht verbunden mit Capture One, Tangent, Loupedeck, TourBox oder Adobe.
