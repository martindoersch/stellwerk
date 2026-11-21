import SwiftUI

extension Color {
    /// Markenfarbe Lime #C7D300 – Text darauf dunkel
    static let lime = Color(red: 0xC7 / 255, green: 0xD3 / 255, blue: 0x00 / 255)
}

struct StatusView: View {
    @Bindable var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stellwerk").font(.headline)
                Spacer()
                Text("Loupedeck+ → Capture One").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                StatusRow(ok: engine.deviceName != nil, title: "Loupedeck+",
                          detail: engine.deviceName != nil ? "verbunden" : "nicht gefunden")
                StatusRow(ok: engine.hubState.isConnected, warn: !engine.hubState.isFailed,
                          title: "Capture One", detail: hubText)
                StatusRow(ok: engine.accessibilityOK, title: "Bedienungshilfen",
                          detail: engine.accessibilityOK ? "freigegeben" : "Freigabe fehlt")
                if !engine.accessibilityOK {
                    Button("Systemeinstellungen öffnen") { Accessibility.openSettings() }
                        .buttonStyle(.link).font(.caption).padding(.leading, 18)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Tasten 1–5", value: engine.keyMode.rawValue)
                LabeledContent("Farbregler", value: engine.bwActive ? "Schwarzweiß" : "Farbbalance")
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
                Button("Belegung neu laden") { engine.reloadMappings() }
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
        case .starting: return "startet …"
        case .listening: return "wartet – Capture One (neu) starten"
        case .connected: return "verbunden"
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
