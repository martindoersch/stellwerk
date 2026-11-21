import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var engine: Engine

    var body: some View {
        TabView {
            DialSettingsView(engine: engine)
                .tabItem { Label("Drehregler", systemImage: "dial.medium") }
            ButtonSettingsView(engine: engine)
                .tabItem { Label("Tasten", systemImage: "square.grid.3x3") }
        }
        .frame(width: 560, height: 520)
        .tint(.lime)
    }
}

// MARK: - Drehregler

private struct DialSettingsView: View {
    @Bindable var engine: Engine

    var body: some View {
        Form {
            Section {
                SliderRow(title: "Geschwindigkeit", value: bind(\.speed), range: 0.25...3, step: 0.05,
                          text: String(format: "× %.2f", engine.settings.speed))
                SliderRow(title: "Beschleunigung", value: bind(\.acceleration), range: 0...2.5, step: 0.1,
                          text: engine.settings.acceleration == 0 ? "aus" : accelText)
            } header: {
                Text("Drehen")
            } footer: {
                Text("Geschwindigkeit = Schrittweite pro Raste. Beschleunigung: Je schneller du drehst, desto größer die Schritte.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SliderRow(title: "Fein (Alt/⌥ halten)", value: bind(\.fine), range: 0.05...0.5, step: 0.05,
                          text: String(format: "× %.2f", engine.settings.fine))
                SliderRow(title: "Grob (Shift/⇧ halten)", value: bind(\.coarse), range: 1.5...10, step: 0.5,
                          text: String(format: "× %.1f", engine.settings.coarse))
            } header: {
                Text("Halten beim Drehen")
            } footer: {
                Text("Wie in Photoshop. Gilt für die Mac-Tastatur und für Alt/Shift am Loupedeck im Tasten-Modus.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Auf Vorgabe zurücksetzen") {
                    engine.updateSettings { s in
                        let d = UserSettings()
                        s.speed = d.speed; s.acceleration = d.acceleration; s.fine = d.fine; s.coarse = d.coarse
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accelText: String {
        let a = engine.settings.acceleration
        return String(format: "× %.1f / × %.1f", 1 + a, 1 + 3 * a)
    }

    private func bind(_ kp: WritableKeyPath<UserSettings, Double>) -> Binding<Double> {
        Binding(get: { engine.settings[keyPath: kp] }, set: { v in engine.updateSettings { $0[keyPath: kp] = v } })
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: String

    var body: some View {
        HStack {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(text).monospacedDigit().frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tasten

private struct ButtonSettingsView: View {
    @Bindable var engine: Engine
    @State private var editing: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(engine.profile.buttons, id: \.self) { name in
                    row(name)
                }
            }
            HStack {
                Text("Geänderte Tasten sind markiert. Drehregler-Drücken setzt immer den Regler zurück.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Alle zurücksetzen") { engine.updateSettings { $0.buttons.removeAll() } }
                    .disabled(engine.settings.buttons.isEmpty)
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func row(_ name: String) -> some View {
        let changed = engine.settings.buttons[name] != nil
        HStack {
            Text(name).frame(width: 110, alignment: .leading)
            if let role = engine.specialRole(name) {
                Text(role).foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(engine.describe(engine.mapping.buttons[name]))
                    .foregroundStyle(engine.mapping.buttons[name] == nil ? .secondary : .primary)
                if changed {
                    Text("geändert")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.lime, in: Capsule())
                        .foregroundStyle(.black)
                }
                Spacer()
                Button("Ändern …") { editing = name }
                    .controlSize(.small)
                    .popover(isPresented: Binding(get: { editing == name }, set: { if !$0 { editing = nil } }),
                             arrowEdge: .trailing) {
                        ButtonEditor(engine: engine, name: name)
                    }
            }
        }
    }
}

private struct ButtonEditor: View {
    enum Kind: String, CaseIterable { case standard = "Vorgabe", action = "Aktion", keys = "Tastenkürzel", off = "Aus" }

    @Bindable var engine: Engine
    let name: String
    @State private var kind = Kind.standard
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline)
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: kind) { _, k in
                switch k {
                case .standard: set(nil)
                case .off: set(.off)
                case .action, .keys: break   // erst bei Auswahl speichern
                }
            }

            switch kind {
            case .standard:
                Text("Vorgabe: \(engine.describe(engine.defaultMapping.buttons[name]))").foregroundStyle(.secondary)
            case .off:
                Text("Die Taste macht nichts.").foregroundStyle(.secondary)
            case .keys:
                ShortcutRecorder(current: currentKeys) { set(.keys($0)) }
                Text("Wird an Capture One geschickt (über das Menü, wenn es dort einen Eintrag mit diesem Kürzel gibt).")
                    .font(.caption).foregroundStyle(.secondary)
            case .action:
                TextField("Aktion suchen …", text: $search).textFieldStyle(.roundedBorder)
                List(filteredActions, id: \.id) { item in
                    Button {
                        set(.action(hexStr(item.id)))
                    } label: {
                        HStack {
                            Text(item.control.name)
                            Spacer()
                            Text(item.control.group.replacingOccurrences(of: " Shortcuts", with: ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if currentAction == item.id { Image(systemName: "checkmark").foregroundStyle(Color.lime) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 260)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear {
            switch engine.settings.buttons[name] {
            case nil: kind = .standard
            case .action?: kind = .action
            case .keys?: kind = .keys
            case .off?: kind = .off
            }
        }
    }

    private var currentAction: UInt32? {
        if case .action(let a)? = engine.mapping.buttons[name] { return a } else { return nil }
    }

    private var currentKeys: String? {
        if case .keys(let k)? = engine.mapping.buttons[name] { return k.text } else { return nil }
    }

    private var filteredActions: [(id: UInt32, control: C1Control)] {
        let all = engine.catalog.actions
        guard !search.isEmpty else { return all }
        return all.filter { $0.control.name.localizedCaseInsensitiveContains(search)
            || $0.control.group.localizedCaseInsensitiveContains(search) }
    }

    private func set(_ choice: ButtonChoice?) {
        engine.updateSettings { $0.buttons[name] = choice }
    }
}

// MARK: - Kürzel aufnehmen

struct ShortcutRecorder: View {
    let current: String?
    let onRecord: (String) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Kürzel drücken … (Esc = abbrechen)" : (current.map(prettyKeys) ?? "Klicken und Kürzel drücken"))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if ev.keyCode == 53 { stop(); return nil }   // Esc
            if let s = Self.string(for: ev) { onRecord(s) }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    /// Ereignis → "cmd+shift+d" (Format der Belegungsdateien)
    static func string(for ev: NSEvent) -> String? {
        var parts: [String] = []
        let f = ev.modifierFlags
        if f.contains(.control) { parts.append("ctrl") }
        if f.contains(.option) { parts.append("alt") }
        if f.contains(.shift) { parts.append("shift") }
        if f.contains(.command) { parts.append("cmd") }
        let named: [UInt16: String] = [123: "left", 124: "right", 125: "down", 126: "up", 36: "return",
                                       48: "tab", 49: "space", 51: "delete"]
        if let n = named[ev.keyCode] {
            parts.append(n)
        } else if let c = ev.characters(byApplyingModifiers: [])?.lowercased(), c.count == 1 {
            parts.append(c)
        } else {
            return nil
        }
        return parts.joined(separator: "+")
    }
}
