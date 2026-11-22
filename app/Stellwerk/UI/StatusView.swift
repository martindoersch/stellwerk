import SwiftUI

extension Color {
    /// Markenfarbe Lime #C7D300 – Text darauf dunkel
    static let lime = Color(red: 0xC7 / 255, green: 0xD3 / 255, blue: 0x00 / 255)
}

struct StatusView: View {
    @Bindable var engine: Engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stellwerk").font(.headline)
                Spacer()
                Text("Loupedeck+ · TourBox → Capture One").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(DeviceID.allCases, id: \.self) { id in
                    let d = engine.device(id)
                    StatusRow(ok: d.connectedName != nil, warn: true, title: d.name,
                              detail: d.connectedName != nil ? String(localized: "verbunden") : String(localized: "nicht angeschlossen"))
                }
                StatusRow(ok: engine.hubState.isConnected, warn: !engine.hubState.isFailed,
                          title: "Capture One", detail: hubText)
                if engine.captureOneRunning && engine.hubState == .listening {
                    Button(engine.restartingCaptureOne ? "Capture One startet neu …" as LocalizedStringKey : "Capture One neu starten") {
                        engine.restartCaptureOne()
                    }
                    .disabled(engine.restartingCaptureOne)
                    .controlSize(.small)
                    .padding(.leading, 18)
                    .help("Capture One verbindet sich nur beim Start. Wird ordentlich beendet (wie ⌘Q) und neu gestartet.")
                }
                StatusRow(ok: engine.accessibilityOK, title: String(localized: "Bedienungshilfen"),
                          detail: engine.accessibilityOK ? String(localized: "freigegeben") : String(localized: "Freigabe fehlt"))
                if !engine.accessibilityOK {
                    Button("Systemeinstellungen öffnen") { Accessibility.openSettings() }
                        .buttonStyle(.link).font(.caption).padding(.leading, 18)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if engine.settings.targetMode == .frontmost {
                    LabeledContent("Profil", value: engine.activeProfileName)
                }
                LabeledContent("Tasten 1–5", value: engine.keyMode.title)
                LabeledContent("Farbregler", value: engine.bwActive ? String(localized: "Schwarzweiß") : String(localized: "Farbbalance"))
                LabeledContent("Belichtung", value: engine.value(of: "Exposure") ?? "–")
                LabeledContent("Zuletzt") {
                    Text(engine.lastAction).lineLimit(1).truncationMode(.middle)
                }
            }
            .font(.callout)

            if !engine.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.warnings, id: \.self) { Text("⚠️ \($0)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Beim Anmelden starten", isOn: Binding(
                get: { engine.launchAtLogin }, set: { engine.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.small).tint(.lime)

            HStack {
                Button("Einstellungen …") {
                    openWindow(id: "settings")
                    NSApp.activate()
                }
                Button("Neu laden") { engine.reloadMappings() }
                    .help("Belegungsdateien neu einlesen")
                Button("Ordner") { engine.openMappingFolder() }
                    .help("Belegungsdateien zum Bearbeiten öffnen")
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { engine.refreshAccessibility() }
    }

    private var hubText: String {
        switch engine.hubState {
        case .starting: return String(localized: "startet …")
        case .listening: return String(localized: "wartet – Capture One (neu) starten")
        case .connected: return String(localized: "verbunden")
        case .failed(let msg): return msg
        }
    }
}

private struct StatusRow: View {
    let ok: Bool
    var warn = false
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.lime : (warn ? Color.orange : Color.red))
                .frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.callout)
    }
}

extension TangentHub.State {
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}
