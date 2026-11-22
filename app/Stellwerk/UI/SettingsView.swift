import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    /// Fenstertitel – die Engine erkennt daran, ob die Einstellungen vorne sind (Anlernen)
    static var windowTitle: String { String(localized: "Stellwerk – Einstellungen") }

    @Bindable var engine: Engine

    var body: some View {
        TabView(selection: $engine.settingsTab) {
            DialSettingsView(engine: engine)
                .tabItem { Label("Drehregler", systemImage: "dial.medium") }
                .tag(Engine.SettingsTab.dials)
            ButtonSettingsView(engine: engine)
                .tabItem { Label("Tasten", systemImage: "square.grid.3x3") }
                .tag(Engine.SettingsTab.buttons)
            GeneralSettingsView(engine: engine)
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
                .tag(Engine.SettingsTab.general)
        }
        .frame(width: 560, height: 520)
        .tint(.lime)
    }
}

// MARK: - Allgemein

private struct GeneralSettingsView: View {
    @Bindable var engine: Engine

    var body: some View {
        Form {
            Section {
                Picker("Tasten und Drehregler wirken", selection: Binding(
                    get: { engine.settings.targetMode }, set: { v in engine.updateSettings { $0.targetMode = v } })) {
                    Text("Immer in Capture One").tag(TargetMode.captureOne)
                    Text("Im aktiven Programm (Profile)").tag(TargetMode.frontmost)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Programme")
            } footer: {
                Text("Immer in Capture One: wirkt auch, wenn ein anderes Programm vorne ist. Im aktiven Programm: Programme mit eigenem Profil (Tab „Tasten\") bekommen ihre Tastenkürzel, alle anderen die Capture-One-Belegung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Anzeige") {
                Toggle("Moduswechsel einblenden", isOn: Binding(
                    get: { engine.settings.showHUD }, set: { v in engine.updateSettings { $0.showHUD = v } }))
                Text("Kurzes Schild unten in der Bildschirmmitte, z. B. „Farben\" oder „Schwarzweiß\".")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Start") {
                Toggle("Beim Anmelden starten", isOn: Binding(
                    get: { engine.launchAtLogin }, set: { engine.setLaunchAtLogin($0) }))
                Text("Stellwerk muss vor Capture One laufen – sonst Capture One neu starten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Belegungsdateien") {
                HStack {
                    Button("Ordner öffnen") { engine.openMappingFolder() }
                    Button("Neu laden") { engine.reloadMappings() }
                }
            }
        }
        .formStyle(.grouped)
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
                          text: engine.settings.acceleration == 0 ? String(localized: "aus") : accelText)
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
    let title: LocalizedStringKey
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
    @State private var editing: EditTarget?
    @State private var highlighted: String?   // Zeile der zuletzt am Gerät gedrückten Taste
    @State private var highlightedFn = false  // … mit gehaltener Fn-Taste gedrückt
    @State private var highlightedDevice = DeviceID.loupedeck

    struct EditTarget: Identifiable {
        let name: String; let fn: Bool; var dial = false
        var id: String { (dial ? "dial:" : fn ? "fn:" : "") + name }
    }

    /// Bearbeitetes Programmprofil (nil = Capture One)
    private var app: AppProfile? { engine.editingProfile.flatMap(engine.appProfile) }

    var body: some View {
        VStack(spacing: 0) {
            DevicePicker(engine: engine)
                .padding([.horizontal, .top], 10)
            ProfileBar(engine: engine)
                .padding([.horizontal, .top], 10).padding(.bottom, 6)
            if app != nil && engine.settings.targetMode != .frontmost {
                Text("Profile wirken erst mit „Im aktiven Programm\" (Allgemein).")
                    .font(.caption).foregroundStyle(.orange).padding(.bottom, 6)
            }
            if engine.menuShortcuts[app?.bundleID ?? Engine.captureOneBundleID] == nil {
                Text("\(app?.name ?? "Capture One") läuft nicht – Menüeinträge zu den Kürzeln erscheinen, sobald es läuft.")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                List {
                    // Die ForEach-Kennung ist zugleich das Sprungziel (ein extra .id greift in macOS-Listen nicht)
                    Section("Tasten") {
                        ForEach(engine.profile.buttons.map { "b:" + $0 }, id: \.self) { key in
                            let name = String(key.dropFirst(2))
                            Group { if let app { appRow(name, app) } else { row(name) } }
                                .listRowBackground(isHighlighted(key) ? Color.lime.opacity(0.3) : nil)
                        }
                    }
                    if let app {
                        Section("Drehregler") {
                            ForEach(engine.profile.dials.map { "d:" + $0 }, id: \.self) { key in
                                dialRow(String(key.dropFirst(2)), app)
                                    .listRowBackground(isHighlighted(key) ? Color.lime.opacity(0.3) : nil)
                            }
                        }
                    }
                }
                .onChange(of: engine.learned) { _, l in jump(to: l, proxy) }
                // Kam der Tastendruck aus einem anderen Tab, entsteht die Liste erst jetzt
                .onAppear { jump(to: engine.learned, proxy) }
            }
            HStack {
                let fn = engine.fnLabel
                (app == nil
                     ? Text("Taste am Gerät drücken, um sie hier zu finden (mit \(fn): \(fn)-Ebene). Drehregler-Drücken setzt den Regler zurück.")
                     : Text("Taste drücken oder Drehregler drehen, um sie hier zu finden (mit \(fn): \(fn)-Ebene)."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if app == nil {
                    Button("Alle zurücksetzen") { engine.resetButtons() }
                        .disabled(engine.deviceSettings.buttons.isEmpty && engine.deviceSettings.fnButtons.isEmpty)
                }
            }
            .padding(10)
        }
        .onChange(of: engine.editingProfile) { highlighted = nil; engine.refreshMenuShortcuts() }
        // Menüs neu lesen, wenn man zurückkommt – vielleicht wurden Kürzel in Capture One geändert
        .task {
            engine.refreshMenuShortcuts()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                engine.refreshMenuShortcuts()
            }
        }
        .sheet(item: $editing) { t in
            VStack(spacing: 0) {
                if let app, t.dial {
                    DialKeyEditor(engine: engine, name: t.name, bundleID: app.bundleID)
                } else if let app {
                    AppButtonEditor(engine: engine, name: t.name, fn: t.fn, bundleID: app.bundleID)
                } else {
                    ButtonEditor(engine: engine, name: t.name, fn: t.fn)
                }
                HStack {
                    Spacer()
                    Button("Fertig") { editing = nil }.keyboardShortcut(.defaultAction)
                }
                .padding([.horizontal, .bottom], 14)
            }
        }
    }

    /// Nur hinspringen und hervorheben – belegen wählt man selbst
    private func jump(to l: Engine.Learned?, _ proxy: ScrollViewProxy) {
        guard let l else { return }
        let key = (l.dial ? "d:" : "b:") + l.name
        highlighted = key
        highlightedDevice = l.device
        highlightedFn = l.fn && !l.dial
        // Erst nach dem Neuzeichnen scrollen, sonst kennt die Liste das Ziel evtl. noch nicht
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(key, anchor: .center) }
        }
    }

    /// Hervorhebung gilt nur für das Gerät, an dem gedrückt wurde
    private func isHighlighted(_ key: String) -> Bool { highlighted == key && highlightedDevice == engine.editingDevice }

    /// Zeile im Programmprofil: nur Tastenkürzel
    @ViewBuilder
    private func appRow(_ name: String, _ p: AppProfile) -> some View {
        HStack {
            Text(controlLabel(name)).frame(width: 110, alignment: .leading)
            if let role = engine.specialRole(name, inAppProfile: true) {
                Text(role).foregroundStyle(.secondary)
                Spacer()
            } else {
                let b = engine.appBindings(p.bundleID)
                let m = engine.appMapping(p.bundleID)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(b.buttons[name].map(prettyKeys) ?? "–")
                            .foregroundStyle(b.buttons[name] == nil ? .secondary : .primary)
                        MenuHint(engine: engine, combo: m?.buttons[name], app: p.bundleID)
                    }
                    if let fn = b.fnButtons[name] {
                        HStack(spacing: 6) {
                            Text("\(engine.fnLabel): \(prettyKeys(fn))").font(.caption).foregroundStyle(.secondary)
                            MenuHint(engine: engine, combo: m?.fnButtons[name], app: p.bundleID)
                        }
                    }
                }
                Spacer()
                editButton("Ändern …", name: name, fn: false)
                editButton("\(engine.fnLabel) …", name: name, fn: true)
            }
        }
    }

    @ViewBuilder
    private func dialRow(_ name: String, _ p: AppProfile) -> some View {
        let d = engine.appBindings(p.bundleID).dials[name] ?? DialKeys()
        HStack {
            Text(controlLabel(name)).lineLimit(1).frame(width: 170, alignment: .leading)
            (d.isEmpty ? Text(verbatim: "–")
                : Text("← \(d.left.map(prettyKeys) ?? "–")   → \(d.right.map(prettyKeys) ?? "–")   Drücken \(d.press.map(prettyKeys) ?? "–")"))
                .foregroundStyle(d.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Ändern …") { editing = EditTarget(name: name, fn: false, dial: true) }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func row(_ name: String) -> some View {
        let changed = engine.deviceSettings.buttons[name] != nil || engine.deviceSettings.fnButtons[name] != nil
        HStack {
            Text(controlLabel(name)).frame(width: 110, alignment: .leading)
            if let role = engine.specialRole(name) {
                Text(role).foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(engine.describe(engine.mapping.buttons[name]))
                            .foregroundStyle(engine.mapping.buttons[name] == nil ? .secondary : .primary)
                        MenuHint(engine: engine, binding: engine.mapping.buttons[name])
                    }
                    if let fn = engine.mapping.fnButtons[name] {
                        HStack(spacing: 6) {
                            Text("\(engine.fnLabel): \(engine.describe(fn))").font(.caption).foregroundStyle(.secondary)
                            MenuHint(engine: engine, binding: fn)
                        }
                    }
                }
                if changed {
                    Text("geändert")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.lime, in: Capsule())
                        .foregroundStyle(.black)
                }
                Spacer()
                editButton("Ändern …", name: name, fn: false)
                editButton("\(engine.fnLabel) …", name: name, fn: true)
            }
        }
    }
}

/// Auswahl des Geräts, dessen Tasten bearbeitet werden – mit Verbindungsstatus
private struct DevicePicker: View {
    @Bindable var engine: Engine

    var body: some View {
        Picker("Gerät", selection: $engine.editingDevice) {
            ForEach(DeviceID.allCases, id: \.self) { id in
                let d = engine.device(id)
                Text("\(d.connectedName != nil ? "●" : "○") \(d.name)").tag(id)
            }
        }
        .pickerStyle(.segmented)
        .help("● verbunden, ○ nicht angeschlossen. Taste an einem Gerät drücken wechselt automatisch dorthin.")
    }
}

/// Klein neben einem Kürzel: welcher Menüeintrag im Programm gerade dieses Kürzel hat
/// (aus dem echten Menü gelesen – zeigt also auch selbst vergebene Kürzel)
private struct MenuHint: View {
    let engine: Engine
    let combo: KeyCombo?
    var app: String?   // nil = Capture One

    init(engine: Engine, combo: KeyCombo?, app: String?) {
        self.engine = engine; self.combo = combo; self.app = app
    }

    init(engine: Engine, binding: ButtonBinding?) {
        self.engine = engine
        if case .keys(let k)? = binding { combo = k } else { combo = nil }
    }

    var body: some View {
        if let combo {
            switch engine.menuMatch(combo, in: app) {
            case .item(let title):
                Text("→ \(title)").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head).help(title)
            case .missing:
                Text("kein Menüeintrag").font(.caption).foregroundStyle(.orange)
                    .help("Im Menü gibt es kein Kürzel \(prettyKeys(combo.text)) – es wird als Tastendruck geschickt.")
            case .notRunning, .plainKey:
                EmptyView()
            }
        }
    }
}

extension ButtonSettingsView {
    /// Knopf der zuletzt am Gerät gedrückten Ebene (normal oder Fn) wird betont
    @ViewBuilder
    private func editButton(_ title: LocalizedStringKey, name: String, fn: Bool) -> some View {
        let button = Button(title) { editing = EditTarget(name: name, fn: fn) }.controlSize(.small)
        if highlighted == "b:" + name && highlightedFn == fn {
            button.buttonStyle(.borderedProminent).foregroundStyle(.black)
        } else {
            button
        }
    }
}

private struct ButtonEditor: View {
    enum Kind: CaseIterable {
        case standard, action, keys, off
        var title: LocalizedStringKey {
            switch self {
            case .standard: "Vorgabe"
            case .action: "Aktion"
            case .keys: "Tastenkürzel"
            case .off: "Aus"
            }
        }
    }

    @Bindable var engine: Engine
    let name: String
    let fn: Bool
    @State private var kind = Kind.standard
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: fn ? "\(engine.fnLabel) + \(controlLabel(name))" : controlLabel(name)).font(.headline)
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.title) }
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
                Text("Vorgabe: \(engine.describe(engine.defaultBinding(name, fn: fn)))").foregroundStyle(.secondary)
            case .off:
                Text("Die Taste macht nichts.").foregroundStyle(.secondary)
            case .keys:
                ShortcutRecorder(current: currentKeys) { set(.keys($0)) }
                MenuHint(engine: engine, binding: engine.binding(name, fn: fn))
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
        .frame(width: 440)
        .onAppear {
            switch engine.choice(name, fn: fn) {
            case nil: kind = .standard
            case .action?: kind = .action
            case .keys?: kind = .keys
            case .off?: kind = .off
            }
        }
    }

    private var currentAction: UInt32? {
        if case .action(let a)? = engine.binding(name, fn: fn) { return a } else { return nil }
    }

    private var currentKeys: String? {
        if case .keys(let k)? = engine.binding(name, fn: fn) { return k.text } else { return nil }
    }

    private var filteredActions: [(id: UInt32, control: C1Control)] {
        let all = engine.catalog.actions
        guard !search.isEmpty else { return all }
        return all.filter { $0.control.name.localizedCaseInsensitiveContains(search)
            || $0.control.group.localizedCaseInsensitiveContains(search) }
    }

    private func set(_ choice: ButtonChoice?) {
        engine.setChoice(choice, for: name, fn: fn)
    }
}

// MARK: - Programmprofile

/// Auswahl des bearbeiteten Profils: Capture One oder ein anderes Programm
private struct ProfileBar: View {
    @Bindable var engine: Engine
    @State private var confirmDelete = false
    @State private var confirmReset = false

    var body: some View {
        HStack {
            Picker("Profil", selection: $engine.editingProfile) {
                Text("Capture One").tag(String?.none)
                ForEach(engine.settings.appProfiles) { p in
                    Text(p.name).tag(Optional(p.bundleID))
                }
            }
            .frame(maxWidth: 260)
            Menu {
                // Programme mit mitgelieferter Vorgabe zuerst, auch wenn sie nicht laufen
                let presets = engine.defaultAppProfiles.filter { engine.appProfile($0.bundleID) == nil }
                if !presets.isEmpty {
                    Section("Mit Vorgabe") {
                        ForEach(presets) { p in
                            Button(p.name) { engine.addAppProfile(bundleID: p.bundleID, name: p.name) }
                        }
                    }
                    Divider()
                }
                ForEach(candidates, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                        if let id = app.bundleIdentifier { engine.addAppProfile(bundleID: id, name: app.localizedName ?? id) }
                    }
                }
                if !candidates.isEmpty { Divider() }
                Button("Anderes Programm …") { pickApp() }
            } label: {
                Label("Programm hinzufügen", systemImage: "plus")
            }
            .fixedSize()
            if let id = engine.editingProfile {
                if engine.defaultAppProfile(id) != nil {
                    Button { confirmReset = true } label: { Image(systemName: "arrow.counterclockwise") }
                        .help("Auf Vorgabe zurücksetzen")
                        .confirmationDialog("Profil „\(engine.appProfile(id)?.name ?? id)\" auf die Vorgabe zurücksetzen?",
                                            isPresented: $confirmReset) {
                            Button("Zurücksetzen", role: .destructive) { engine.resetAppProfile(id) }
                        } message: {
                            Text("Eigene Änderungen an allen Geräten gehen verloren.")
                        }
                }
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .help("Profil löschen")
                    .confirmationDialog("Profil „\(engine.appProfile(id)?.name ?? id)\" löschen?", isPresented: $confirmDelete) {
                        Button("Löschen", role: .destructive) { engine.removeAppProfile(id) }
                    }
            }
            Spacer()
        }
    }

    /// Laufende Programme ohne eigenes Profil
    private var candidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != Bundle.main.bundleIdentifier && id != Engine.captureOneBundleID && engine.appProfile(id) == nil
                    && engine.defaultAppProfile(id) == nil   // steht schon oben unter „Mit Vorgabe"
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        engine.addAppProfile(bundleID: id, name: url.deletingPathExtension().lastPathComponent)
    }
}

/// Taste im Programmprofil: ein Tastenkürzel ans vordere Programm
private struct AppButtonEditor: View {
    @Bindable var engine: Engine
    let name: String
    let fn: Bool
    let bundleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(fn ? "\(engine.fnLabel) + " : "")\(controlLabel(name)) – \(profileName)").font(.headline)
            ShortcutRecorder(current: current) { engine.setAppKeys($0, for: name, fn: fn, in: bundleID) }
            MenuHint(engine: engine, combo: current.flatMap { Keys.parse($0) }, app: bundleID)
            HStack {
                Text("Wird an \(profileName) geschickt, wenn es vorne ist.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Entfernen") { engine.setAppKeys(nil, for: name, fn: fn, in: bundleID) }
                    .disabled(current == nil)
            }
        }
        .padding(14)
        .frame(width: 440)
    }

    private var profileName: String { engine.appProfile(bundleID)?.name ?? bundleID }

    private var current: String? {
        let b = engine.appBindings(bundleID)
        return fn ? b.fnButtons[name] : b.buttons[name]
    }
}

/// Drehregler im Programmprofil: Kürzel für links, rechts und Drücken
private struct DialKeyEditor: View {
    @Bindable var engine: Engine
    let name: String
    let bundleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(controlLabel(name)) – \(engine.appProfile(bundleID)?.name ?? bundleID)").font(.headline)
            slot("Nach links", \.left)
            slot("Nach rechts", \.right)
            slot("Drücken", \.press)
            Text("Pro Raste ein Tastendruck, z. B. ⌘− / ⌘+ zum Zoomen oder Pfeiltasten.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 440)
    }

    private var keys: DialKeys { engine.appBindings(bundleID).dials[name] ?? DialKeys() }

    private func slot(_ title: LocalizedStringKey, _ kp: WritableKeyPath<DialKeys, String?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            slotRow(title, kp)
            MenuHint(engine: engine, combo: keys[keyPath: kp].flatMap { Keys.parse($0) }, app: bundleID)
                .padding(.leading, 98)
        }
    }

    private func slotRow(_ title: LocalizedStringKey, _ kp: WritableKeyPath<DialKeys, String?>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            ShortcutRecorder(current: keys[keyPath: kp]) { v in
                var d = keys
                d[keyPath: kp] = v
                engine.setAppDial(d, for: name, in: bundleID)
            }
            Button {
                var d = keys
                d[keyPath: kp] = nil
                engine.setAppDial(d, for: name, in: bundleID)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(keys[keyPath: kp] == nil)
            .help("Entfernen")
        }
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
            Group {
                if recording { Text("Kürzel drücken … (Esc = abbrechen)") }
                else if let current { Text(verbatim: prettyKeys(current)) }
                else { Text("Klicken und Kürzel drücken") }
            }
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
            parts.append(c == "+" ? "plus" : c)
        } else {
            return nil
        }
        return parts.joined(separator: "+")
    }
}
