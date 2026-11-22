// Kern: nimmt Control-Ereignisse der Eingabe-Adapter, wendet Belegung und Modi an und
// schickt Aktionen an die Ausgabe-Adapter. Hält den Zustand fürs Statusmenü.
// Mehrere Geräte gleichzeitig (Loupedeck+, TourBox); jedes hat Geräteprofil, Belegung und eigene gehaltene Tasten.
import AppKit
import Observation
import ServiceManagement

@Observable
final class Engine {
    enum KeyMode {
        case stars, colors, modifiers
        var title: String {
            switch self {
            case .stars: String(localized: "Sterne")
            case .colors: String(localized: "Farben")
            case .modifiers: String(localized: "Tasten (Shift/Ctrl/Cmd/Alt/Tab)")
            }
        }
    }

    static let captureOneBundleID = "com.captureone.captureone16"
    static let mappingFiles = DeviceID.allCases.flatMap { [$0.profileFile, $0.mappingFile] }

    /// Ein Gerät mit seinen Belegungsdaten und Laufzeit-Zustand
    struct Device {
        let id: DeviceID
        var profile = DeviceProfile()
        var defaultMapping = Mapping()            // mitgelieferte Belegung ohne persönliche Änderungen
        var mapping = Mapping()                   // wirksame Belegung (Vorgabe + Einstellungen)
        var appMappings: [String: AppMapping] = [:]   // Programmprofile nach Bundle-ID
        var connectedName: String?
        var name: String { profile.device }
    }

    /// Gerade gedrückte Tasten je Gerät – bewusst nicht beobachtet: ändert sich bei jedem Druck,
    /// und das Einstellungsfenster müsste sonst jedes Mal neu zeichnen.
    @ObservationIgnored private var held: [DeviceID: Set<String>] = [:]

    /// Auswahl „Taste wählt, was der Drehregler steuert" (Quick Keys). Gehalten gewinnt vor gewählt.
    struct DialSelection {
        var latched: String?        // kurz getippt → bleibt
        var holding: String?        // gerade gehalten
        var used = false            // beim Halten gedreht/zurückgesetzt → beim Loslassen nicht festhalten
        var current: String? { holding ?? latched }
    }
    @ObservationIgnored private var selection: [DeviceID: DialSelection] = [:]

    // MARK: Zustand fürs Menü
    var hubState = TangentHub.State.starting
    var accessibilityOK = Accessibility.isTrusted
    var keyMode = KeyMode.stars
    var bwActive = false
    var lastAction = "–"
    var warnings: [String] = []
    var values: [UInt32: Float] = [:]
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var settings = UserSettings.load()
    var captureOneRunning = false
    var restartingCaptureOne = false
    var activeProfileName = "Capture One"   // Profil des vorderen Programms (Modus „aktives Programm")
    private(set) var devices: [DeviceID: Device] = Dictionary(uniqueKeysWithValues: DeviceID.allCases.map { ($0, Device(id: $0)) })

    // MARK: Einstellungsfenster & Anlernen
    enum SettingsTab: Hashable { case dials, buttons, general }
    /// Zuletzt am Gerät gedrückte Taste, während das Einstellungsfenster vorne ist
    struct Learned: Equatable { let device: DeviceID; let name: String; let fn: Bool; let dial: Bool; let serial: Int }
    var settingsTab = SettingsTab.dials
    var editingDevice = DeviceID.loupedeck   // in den Einstellungen bearbeitetes Gerät
    var editingProfile: String?             // nil = Capture One, sonst Bundle-ID des Programmprofils
    var learned: Learned?
    private var learnSerial = 0
    private var lastLearnTime: TimeInterval = 0

    // MARK: Bausteine
    private(set) var catalog = Catalog()
    private let midi = MIDIInput(match: "Loupedeck")
    private let tourbox = TourBoxInput()
    private let quickkeys = QuickKeysInput()
    private let hub = TangentHub()
    private let keys = KeyOutput()
    private let hud = HUD()
    private var lastTick: [String: TimeInterval] = [:]

    func device(_ id: DeviceID) -> Device { devices[id] ?? Device(id: id) }

    // Bequemer Zugriff fürs Einstellungsfenster: das gerade bearbeitete Gerät
    var profile: DeviceProfile { device(editingDevice).profile }
    var mapping: Mapping { device(editingDevice).mapping }
    var deviceSettings: DeviceSettings { settings.device(editingDevice) }
    /// Name der Kombi-Taste des bearbeiteten Geräts („Fn" beim Loupedeck, „Side" bei der TourBox)
    var fnLabel: String { mapping.fnKey }

    init() {
        loadMappings()
        keys.onLog = { [weak self] in self?.log($0) }
        hub.onLog = { [weak self] in self?.log($0) }
        hub.onState = { [weak self] st in
            guard let self else { return }
            self.hubState = st
            if case .connected = st {
                self.log(String(localized: "Capture One verbunden"))
                self.requestStartValues()
            }
        }
        hub.onValue = { [weak self] id, v, _ in
            self?.values[id] = v
            self?.showQuickKeysValue(id)
        }
        midi.onConnection = { [weak self] name in self?.devices[.loupedeck]?.connectedName = name }
        midi.onMessage = { [weak self] s, d1, d2 in self?.handleMIDI(status: s, d1, d2) }
        tourbox.onConnection = { [weak self] name in
            self?.devices[.tourbox]?.connectedName = name
            if name == nil { self?.held[.tourbox] = nil }
        }
        tourbox.onByte = { [weak self] b in self?.handleTourBox(b) }
        tourbox.onLog = { [weak self] in self?.log($0) }
        quickkeys.onConnection = { [weak self] name in
            self?.devices[.quickkeys]?.connectedName = name
            if name == nil { self?.held[.quickkeys] = nil; self?.selection[.quickkeys] = nil }
        }
        quickkeys.onReady = { [weak self] in self?.refreshQuickKeys() }
        quickkeys.onButton = { [weak self] i, down in self?.handleQuickKeys(button: i, down: down) }
        quickkeys.onWheel = { [weak self] ticks in self?.handleQuickKeys(wheel: ticks) }
        quickkeys.onLog = { [weak self] in self?.log($0) }

        hub.start()
        midi.start()
        tourbox.start()
        quickkeys.start()
        Accessibility.request()
        startTapWhenTrusted()
        // Läuft Capture One? (für den Knopf „Capture One neu starten")
        updateCaptureOneRunning()
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCaptureOneRunning() }
            }
        }
        updateActiveProfile(announce: false)
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateActiveProfile(announce: true)
                // Der Xencelabs-Treiber beschriftet das Display beim Programmwechsel womöglich selbst → neu schreiben
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.captureOneBundleID {
                    self?.refreshQuickKeys(force: true)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keys.releaseAll(); self?.hub.stop(); self?.tourbox.stop(); self?.quickkeys.stop() }
        }
    }

    /// Die Freigabe kann später erteilt werden → regelmäßig nachsehen und dann den Event-Tap starten.
    private func startTapWhenTrusted() {
        accessibilityOK = Accessibility.isTrusted
        if accessibilityOK, ModifierTap.start() { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.startTapWhenTrusted() }
        }
    }

    private func requestStartValues() {
        for d in devices.values { for p in d.mapping.allParams { hub.request(p) } }
    }

    // MARK: Belegung

    func loadMappings() {
        warnings.removeAll()
        // Regler-Liste aus dem installierten Capture One; eine eigene JSON (parse_controls.py)
        // im Benutzerordner dient nur als Ausweg, wenn Capture One woanders liegt.
        if let c = Catalog.fromInstalledCaptureOne(bundleID: Self.captureOneBundleID) { catalog = c }
        else if let c = MappingStore.load("capture-one-controls.json") { catalog = Catalog(json: c) }
        else { warnings.append(String(localized: "Capture One nicht gefunden – Regler-Liste fehlt")) }
        for id in DeviceID.allCases {
            var d = device(id)
            if let p = MappingStore.load(id.profileFile) { d.profile = DeviceProfile(json: p) }
            else { warnings.append(String(localized: "\(id.profileFile) fehlt – Gerät anlernen")) }
            if let m = MappingStore.load(id.mappingFile) { d.defaultMapping = Mapping(json: m, catalog: catalog) }
            else { warnings.append(String(localized: "\(id.mappingFile) fehlt oder ist kein gültiges JSON")) }
            devices[id] = d
            warnings += d.defaultMapping.warnings.map { "\(d.name): \($0)" }
        }
        applySettings()
        keyMode = .stars
        bwActive = false
        selection.removeAll()
        if hub.isConnected { requestStartValues() }
        refreshQuickKeys(force: true)
    }

    /// Einstellungen auf alle Geräte anwenden
    private func applySettings() {
        for id in DeviceID.allCases {
            var d = device(id)
            d.mapping = d.defaultMapping.applying(settings, device: id)
            d.appMappings = Dictionary(settings.appProfiles.map { ($0.bundleID, AppMapping($0, device: id)) },
                                       uniquingKeysWith: { a, _ in a })
            devices[id] = d
        }
    }

    func reloadMappings() {
        loadMappings()
        log(warnings.isEmpty ? String(localized: "Belegung neu geladen")
            : String(localized: "Belegung geladen, \(warnings.count) Hinweis(e)"))
    }

    func openMappingFolder() {
        NSWorkspace.shared.open(MappingStore.prepareUserDir(files: Self.mappingFiles))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { log(String(localized: "Autostart: \(error.localizedDescription)")) }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshAccessibility() { accessibilityOK = Accessibility.isTrusted }

    // MARK: Capture One neu starten
    // Capture One sucht den Tangent Hub nur beim eigenen Start (getestet, kein Wiederverbinden).

    private func updateCaptureOneRunning() {
        captureOneRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.captureOneBundleID).isEmpty
    }

    /// Beendet Capture One ordentlich (wie ⌘Q) und startet es neu, damit es sich mit Stellwerk verbindet.
    func restartCaptureOne() {
        guard !restartingCaptureOne,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.captureOneBundleID).first,
              let url = app.bundleURL else { return }
        restartingCaptureOne = true
        log(String(localized: "Capture One wird neu gestartet …"))
        app.terminate()
        waitForQuit(app, url: url, tries: 0)
    }

    private func waitForQuit(_ app: NSRunningApplication, url: URL, tries: Int) {
        if app.isTerminated {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, err in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.restartingCaptureOne = false
                        if let err { self?.log(String(localized: "Start fehlgeschlagen: \(err.localizedDescription)")) }
                    }
                }
            }
            return
        }
        guard tries < 60 else {   // 30 s: vermutlich wartet ein Dialog in Capture One
            restartingCaptureOne = false
            log(String(localized: "Capture One beendet sich nicht – Dialog offen?"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.waitForQuit(app, url: url, tries: tries + 1) }
        }
    }

    // MARK: Einstellungen

    /// Ändert die Einstellungen, speichert sie und macht sie sofort wirksam
    func updateSettings(_ change: (inout UserSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        s.save()
        applySettings()
        updateActiveProfile(announce: false)
        refreshQuickKeys()
    }

    // Tastenbelegung des bearbeiteten Geräts je Ebene (normal oder Fn) für das Einstellungsfenster
    func binding(_ name: String, fn: Bool) -> ButtonBinding? { fn ? mapping.fnButtons[name] : mapping.buttons[name] }
    func defaultBinding(_ name: String, fn: Bool) -> ButtonBinding? {
        let m = device(editingDevice).defaultMapping
        return fn ? m.fnButtons[name] : m.buttons[name]
    }
    func choice(_ name: String, fn: Bool) -> ButtonChoice? { fn ? deviceSettings.fnButtons[name] : deviceSettings.buttons[name] }
    func setChoice(_ c: ButtonChoice?, for name: String, fn: Bool) {
        updateSettings { $0.updateDevice(editingDevice) { d in if fn { d.fnButtons[name] = c } else { d.buttons[name] = c } } }
    }
    func resetButtons() {
        updateSettings { $0.updateDevice(editingDevice) { d in d.buttons.removeAll(); d.fnButtons.removeAll() } }
    }

    // MARK: Programmprofile

    func appProfile(_ bundleID: String) -> AppProfile? { settings.appProfiles.first { $0.bundleID == bundleID } }
    /// Belegung des bearbeiteten Geräts in einem Programmprofil
    func appBindings(_ bundleID: String) -> AppBindings { appProfile(bundleID)?.bindings(editingDevice) ?? AppBindings() }
    func appMapping(_ bundleID: String) -> AppMapping? { device(editingDevice).appMappings[bundleID] }

    func addAppProfile(bundleID: String, name: String) {
        guard bundleID != Self.captureOneBundleID else { editingProfile = nil; return }
        if appProfile(bundleID) == nil {
            updateSettings { $0.appProfiles.append(AppProfile(bundleID: bundleID, name: name)) }
        }
        editingProfile = bundleID
    }

    func removeAppProfile(_ bundleID: String) {
        updateSettings { $0.appProfiles.removeAll { $0.bundleID == bundleID } }
        if editingProfile == bundleID { editingProfile = nil }
    }

    /// Kürzel einer Taste im Programmprofil (nil = unbelegt)
    func setAppKeys(_ keys: String?, for name: String, fn: Bool, in bundleID: String) {
        let dev = editingDevice
        updateSettings { $0.updateProfile(bundleID) { p in
            p.update(dev) { b in if fn { b.fnButtons[name] = keys } else { b.buttons[name] = keys } }
        } }
    }

    func setAppDial(_ d: DialKeys, for name: String, in bundleID: String) {
        let dev = editingDevice
        updateSettings { $0.updateProfile(bundleID) { p in p.update(dev) { b in b.dials[name] = d.isEmpty ? nil : d } } }
    }

    /// Bundle-ID des vorderen Programms, wenn es ein Profil hat – nur im Modus „aktives Programm"
    private var frontProfileID: String? {
        guard settings.targetMode == .frontmost,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, appProfile(id) != nil else { return nil }
        return id
    }

    /// Profil des vorderen Programms für ein Gerät; nil = Capture-One-Belegung
    private func frontApp(_ dev: DeviceID) -> AppMapping? { frontProfileID.flatMap { device(dev).appMappings[$0] } }

    /// Anzeige des aktiven Profils; Stellwerk selbst (Einstellungen, Menü) ändert es nicht
    private func updateActiveProfile(announce show: Bool) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let name = frontProfileID.flatMap { appProfile($0)?.name } ?? "Capture One"
        guard name != activeProfileName else { return }
        activeProfileName = name
        if show && settings.targetMode == .frontmost { announce(name, symbol: "app.badge") }
    }

    // MARK: Menü-Kürzel der Programme (Anzeige in den Einstellungen)

    /// Bundle-ID → Kürzel → „Menü › Eintrag"; fehlt ein Programm, läuft es nicht
    private(set) var menuShortcuts: [String: [String: String]] = [:]

    /// Liest die Menüs neu ein (Kürzel können sich in Capture One jederzeit ändern)
    func refreshMenuShortcuts() {
        guard Accessibility.isTrusted else { return }
        var out: [String: [String: String]] = [:]
        for id in [Self.captureOneBundleID] + settings.appProfiles.map(\.bundleID) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                out[id] = KeyOutput.menuShortcuts(pid: app.processIdentifier)
            }
        }
        menuShortcuts = out
    }

    enum MenuMatch { case item(String), missing, notRunning, plainKey }

    /// Was ein Kürzel im Programm auslöst
    func menuMatch(_ k: KeyCombo, in bundleID: String?) -> MenuMatch {
        guard let menu = menuShortcuts[bundleID ?? Self.captureOneBundleID] else { return .notRunning }
        if let key = KeyOutput.menuKey(k), let title = menu[key] { return .item(title) }
        return k.flags.contains(.maskCommand) ? .missing : .plainKey   // Enter, Pfeile … sind keine Menü-Kürzel
    }

    // MARK: Anlernen

    /// Einstellungsfenster (oder sein Blatt) ist vorne → Gerätetasten zeigen statt auslösen
    private var isLearning: Bool {
        guard NSApp.isActive, let w = NSApp.keyWindow else { return false }
        return (w.sheetParent ?? w).title == SettingsView.windowTitle
    }

    private func learn(_ dev: DeviceID, _ name: String, dial: Bool) {
        learnSerial += 1
        let fn = held[dev, default: []].contains(device(dev).mapping.fnKey)
        learned = Learned(device: dev, name: name, fn: fn, dial: dial, serial: learnSerial)
        editingDevice = dev   // Einstellungen springen zum Gerät, an dem gedrückt wurde
        settingsTab = .buttons
    }

    func describe(_ b: ButtonBinding?) -> String {
        switch b {
        case .action(let a)?: return catalog.name(a)
        case .keys(let k)?: return prettyKeys(k.text)
        case nil: return "–"
        }
    }

    /// Tasten mit fester Sonderfunktion (in den Einstellungen nicht frei belegbar)
    /// In Programmprofilen bleiben nur Fn und der Modus-Umschalter fest.
    func specialRole(_ name: String, inAppProfile: Bool = false) -> String? {
        if name == mapping.modeToggle { return String(localized: "Umschalter Sterne/Farben (Fn: Tasten)") }
        if name == mapping.fnKey {
            return mapping.fnKey == "Fn" ? String(localized: "Fn (in Kombination)") : String(localized: "Kombi-Taste wie Fn (in Kombination)")
        }
        if inAppProfile { return nil }
        if name == mapping.bwToggle { return String(localized: "Schwarzweiß + Farbregler umschalten") }
        if mapping.modeKeys.contains(name) { return String(localized: "Stern/Farbe/Taste je nach Modus") }
        return nil
    }

    private func notAssigned(_ name: String) -> String { String(localized: "\(controlLabel(name)): nicht belegt") }

    private func log(_ s: String) {
        lastAction = s
        #if DEBUG
        print(s)
        #endif
    }

    // MARK: Eingänge → Control-Ereignis

    private func handleMIDI(status: UInt8, _ d1: Int, _ d2: Int) {
        let p = device(.loupedeck).profile
        switch status & 0xF0 {
        case 0xB0:
            let ticks = d2 < 64 ? d2 : d2 - 128   // relativ: 01 = +1, 7F = −1
            if let name = p.dialByCC[d1] { turn(.loupedeck, name, ticks: ticks) } else { log(String(localized: "CC \(d1): nicht angelernt")) }
        case 0x90 where d2 > 0:
            if let name = p.nameByNote[d1] { press(.loupedeck, name) } else { log(String(localized: "Note \(d1): nicht angelernt")) }
        case 0x80, 0x90:   // NoteOff bzw. NoteOn mit Velocity 0 = losgelassen
            if let name = p.nameByNote[d1] { release(.loupedeck, name) }
        default: break
        }
    }

    /// TourBox: ein Byte je Ereignis. Bit 7 = losgelassen, Bit 6 = Drehrichtung rechts/rauf
    private func handleTourBox(_ b: UInt8) {
        let p = device(.tourbox).profile
        let code = Int(b & 0x3F)
        if let name = p.dialByCC[code] {
            turn(.tourbox, name, ticks: b & 0x40 != 0 ? 1 : -1)
        } else if let name = p.nameByNote[code] {
            if b & 0x80 != 0 { release(.tourbox, name) } else { press(.tourbox, name) }
        } else {
            log(String(localized: "TourBox \(String(format: "%02X", b)): nicht angelernt"))
        }
        #if DEBUG
        trace(String(format: "%02X", b) + "  gehalten: \(held[.tourbox, default: []].sorted())  → \(lastAction)")
        #endif
    }

    /// Quick Keys: Tasten 0–9 (Bit der Tastenmaske), Rad ±1 pro Raste
    private func handleQuickKeys(button i: Int, down: Bool) {
        guard let name = device(.quickkeys).profile.nameByNote[i] else {
            if down { log(String(localized: "Quick Keys Taste \(i): nicht angelernt")) }
            return
        }
        if down { press(.quickkeys, name) } else { release(.quickkeys, name) }
    }

    private func handleQuickKeys(wheel ticks: Int) {
        guard let name = device(.quickkeys).profile.dials.first else { return }
        turn(.quickkeys, name, ticks: ticks)
    }

    #if DEBUG
    /// Fehlersuche: jedes TourBox-Byte nach /tmp/stellwerk-tourbox.log
    @ObservationIgnored private lazy var traceFile: FileHandle? = {
        let url = URL(fileURLWithPath: "/tmp/stellwerk-tourbox.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    private func trace(_ s: String) {
        let t = String(format: "%.3f  ", ProcessInfo.processInfo.systemUptime)
        traceFile?.write(Data((t + s + "\n").utf8))
    }
    #endif

    // MARK: Router

    /// Belegung eines Drehreglers in der gerade aktiven Ebene (Fn gehalten, per Taste gewählt, Schwarzweiß)
    private func dialBinding(_ dev: DeviceID, _ name: String) -> DialBinding? {
        let m = device(dev).mapping
        let fn = held[dev, default: []].contains(m.fnKey) ? m.fnDials[name] : nil
        let selected = name == m.dialSelect.dial ? selection[dev]?.current.flatMap { m.dialSelect.keys[$0]?.binding } : nil
        return fn ?? selected ?? (bwActive ? m.bwDials[name] : nil) ?? m.dials[name]
    }

    /// Beim Halten einer Wahltaste wurde der Drehregler benutzt → beim Loslassen zurück zur vorigen Auswahl
    private func markSelectionUsed(_ dev: DeviceID, _ name: String) {
        if name == device(dev).mapping.dialSelect.dial, selection[dev]?.holding != nil { selection[dev]?.used = true }
    }

    func turn(_ dev: DeviceID, _ name: String, ticks: Int) {
        // Beim Anlernen eines Programmprofils zeigt Drehen den Regler; in Capture One wirkt er weiter (zum Ausprobieren)
        if editingProfile != nil, isLearning {
            // Eine Drehung liefert viele Rasten → nur einmal pro Ansatz melden
            let now = ProcessInfo.processInfo.systemUptime
            if learned?.name != name || learned?.device != dev || now - lastLearnTime > 0.6 { learn(dev, name, dial: true) }
            lastLearnTime = now
            return
        }
        if let app = frontApp(dev) {
            guard let k = ticks > 0 ? app.dials[name]?.right : app.dials[name]?.left else { log(notAssigned(name)); return }
            for _ in 0 ..< abs(ticks) { keys.sendToFront(k, viaMenu: false) }
            lastAction = "\(controlLabel(name)): \(prettyKeys(k.text))"
            return
        }
        markSelectionUsed(dev, name)
        guard let b = dialBinding(dev, name) else { log(notAssigned(name)); return }
        if let plus = b.plus, let minus = b.minus {   // Drehregler löst Aktionen aus
            let a = ticks > 0 ? plus : minus
            for _ in 0 ..< abs(ticks) { hub.action(a) }
            log("\(controlLabel(name)): \(catalog.name(a))")
            return
        }
        guard let p = b.param else { return }
        let m = device(dev).mapping
        let now = ProcessInfo.processInfo.systemUptime
        let tickKey = "\(dev.rawValue):\(name)"
        let ms = (now - (lastTick[tickKey] ?? 0)) * 1000
        lastTick[tickKey] = now
        let acc = m.accel
        let factor = ms < acc.fastMs ? acc.fastFactor : ms < acc.mediumMs ? acc.mediumFactor : 1
        hub.change(p, by: Float(Double(ticks) * b.perTick * m.speed * factor * modifierFactor(m)))
        lastAction = catalog.name(p)
    }

    /// Alt/⌥ = fein, Shift/⇧ = grob (fein gewinnt, wenn beides gehalten wird).
    /// Mac-Tastatur und Alt/Shift am Loupedeck im Tasten-Modus – wirkt auch auf die TourBox.
    private func modifierFactor(_ m: Mapping) -> Double {
        let kb = m.keyboardModifiers ? CGEventSource.flagsState(.combinedSessionState) : []
        let pad = keyMode == .modifiers ? held[.loupedeck, default: []] : []
        if kb.contains(.maskAlternate) || pad.contains("Alt") { return m.fineFactor }
        if kb.contains(.maskShift) || pad.contains("Shift") { return m.coarseFactor }
        return 1
    }

    func press(_ dev: DeviceID, _ name: String) {
        held[dev, default: []].insert(name)
        let d = device(dev), m = d.mapping
        let fnHeld = held[dev, default: []].contains(m.fnKey)
        let isDial = d.profile.dialByCC.values.contains(name)
        let dialOnly = isDial && !d.profile.buttons.contains(name)   // Loupedeck: Drücken eines Drehreglers

        if name != m.fnKey, isLearning, !dialOnly || editingProfile != nil {   // Fn wirkt nur in Kombination
            learn(dev, name, dial: dialOnly)
            return
        }
        if name == m.modeToggle {
            keyMode = fnHeld ? .modifiers : (keyMode == .stars ? .colors : .stars)
            log(String(localized: "Modus: \(keyMode.title)"))
            switch keyMode {
            case .stars: announce(String(localized: "Sterne"), symbol: "star.fill")
            case .colors: announce(String(localized: "Farben"), symbol: "paintpalette.fill")
            case .modifiers: announce(String(localized: "HUD.keys", defaultValue: "Tasten"), symbol: "keyboard")
            }
            return
        }
        let app = frontApp(dev)
        // Taste wählt, was der Drehregler steuert – außer sie ist in den Einstellungen anders belegt
        if m.dialSelect.keys[name] != nil, m.buttons[name] == nil, !fnHeld, app == nil {
            selection[dev, default: DialSelection()].holding = name
            selection[dev]?.used = false
            selectionChanged(dev)
            return
        }
        markSelectionUsed(dev, name)   // Drücken des Drehreglers (zurücksetzen) zählt als benutzt
        // Im Programmprofil sind die fünf Modus-Tasten frei belegbar, außer im Tasten-Modus (Shift/Ctrl/…)
        if let i = m.modeKeys.firstIndex(of: name), app == nil || keyMode == .modifiers {
            switch keyMode {
            case .stars: if let a = fnHeld ? m.starsClear : m.starIDs[safe: i] { trigger(a) }
            case .colors: if let a = fnHeld ? m.colorsClear : m.colorIDs[safe: i] { trigger(a) }
            case .modifiers: keys.postReal(name, down: true); lastAction = String(localized: "Taste \(controlLabel(name))")
            }
            return
        }
        if name == m.fnKey { return }   // Fn wirkt nur in Kombination
        if let app {
            let k = (fnHeld ? app.fnButtons[name] : nil) ?? app.buttons[name] ?? (isDial ? app.dials[name]?.press : nil)
            if let k { log("\(fnHeld ? "\(m.fnKey)+" : "")\(controlLabel(name)): \(prettyKeys(k.text))"); keys.sendToFront(k) }
            else { log(String(localized: "\(controlLabel(name)): in \(app.name) nicht belegt")) }
            return
        }
        if name == m.bwToggle {
            bwActive.toggle()
            let colorMode = bwActive ? String(localized: "Schwarzweiß") : String(localized: "Farbbalance")
            log(String(localized: "Farbregler: \(colorMode)"))
            announce(colorMode,
                     symbol: bwActive ? "circle.lefthalf.filled" : "circle.hexagongrid.fill")
            if let a = m.bwAction { hub.action(a) }
            return
        }
        if fnHeld, let b = m.fnButtons[name] {   // Fn + Taste
            run(b, name: "\(m.fnKey)+\(controlLabel(name))")
            return
        }
        switch m.buttons[name] {
        case let b?: run(b, name: controlLabel(name))
        case nil:   // Drücken eines Drehreglers setzt seinen Regler zurück (mit Fn: den Fn-Regler)
            if let p = dialBinding(dev, name)?.param { hub.reset(p); log(String(localized: "\(catalog.name(p)) zurückgesetzt")) }
            else { log(notAssigned(name)) }
        }
    }

    func release(_ dev: DeviceID, _ name: String) {
        held[dev, default: []].remove(name)
        if dev == .loupedeck, keys.realDown.contains(name) { keys.postReal(name, down: false) }
        // Kurz getippt → Auswahl bleibt (nochmal tippen hebt sie auf); gehalten und gedreht → zurück zur vorigen
        if var s = selection[dev], s.holding == name {
            if !s.used { s.latched = s.latched == name ? nil : name }
            s.holding = nil
            selection[dev] = s
            selectionChanged(dev)
        }
    }

    // MARK: Quick-Keys-Display

    /// Auswahl geändert: Ring färben, Display neu beschriften (bewusst ohne Einblendung – getestet, stört)
    private func selectionChanged(_ dev: DeviceID) {
        guard dev == .quickkeys else { return }
        let m = device(dev).mapping
        let choice = selection[dev]?.current.flatMap { m.dialSelect.keys[$0] }
        quickkeys.ring(choice?.color ?? m.dialSelect.ring ?? 0xFFFFFF)
        refreshQuickKeys()
        if let p = choice?.binding.param { lastAction = catalog.name(p) }
    }

    /// Texte neben den Tasten: Kurzname + Wert; die gewählte Taste mit „>" davor
    private func refreshQuickKeys(force: Bool = false) {
        let d = device(.quickkeys), m = d.mapping
        if force {
            quickkeys.invalidate()
            let choice = selection[.quickkeys]?.current.flatMap { m.dialSelect.keys[$0] }
            quickkeys.ring(choice?.color ?? m.dialSelect.ring ?? 0xFFFFFF)
        }
        let current = selection[.quickkeys]?.current
        for i in 0 ..< 8 {
            guard let name = d.profile.nameByNote[i] else { continue }
            var label = "", value = ""
            if let b = m.buttons[name] {
                label = describe(b)
            } else if let c = m.dialSelect.keys[name] {
                // Die Display-Schrift kennt kein ß (getestet: „Weiß" → „Wei")
                label = controlLabel(c.label).replacingOccurrences(of: "ß", with: "ss")
                if let p = c.binding.param, let v = values[p] { value = formatValue(v, p) }
            }
            let mark = name == current ? ">" : ""
            let room = 8 - mark.count - value.count
            let sep = !value.isEmpty && label.count < room ? " " : ""
            quickkeys.setText(i, mark + label.prefix(max(0, room - sep.count)) + sep + value)
        }
    }

    /// Neuer Wert aus Capture One: Display nachführen (bewusst ohne Einblendung – die verdeckt die Tastentexte)
    private func showQuickKeysValue(_ id: UInt32) {
        guard device(.quickkeys).mapping.dialSelect.keys.values.contains(where: { $0.binding.param == id }) else { return }
        refreshQuickKeys()
    }

    /// Ganzzahlig bei Reglern mit Schritt ≥ 1 (Kelvin, Kontrast …), sonst zwei Nachkommastellen
    private func formatValue(_ v: Float, _ p: UInt32) -> String {
        String(format: (catalog.items[p]?.step ?? 1) >= 1 ? "%.0f" : "%.2f", v)
    }

    private func run(_ b: ButtonBinding, name: String) {
        switch b {
        case .action(let a): trigger(a)
        case .keys(let k): log("\(name): \(prettyKeys(k.text))"); keys.send(k, toBundleID: Self.captureOneBundleID)
        }
    }

    private func announce(_ text: String, symbol: String) {
        if settings.showHUD { hud.show(text, symbol: symbol) }
    }

    private func trigger(_ a: UInt32) {
        hub.action(a)
        log(catalog.name(a))
    }

    // MARK: Anzeige

    /// Wert des Reglers, der auf diesem Drehregler liegt
    func value(of name: String, on dev: DeviceID = .loupedeck) -> String? {
        guard let p = device(dev).mapping.dials[name]?.param, let v = values[p] else { return nil }
        return String(format: abs(v) >= 100 ? "%.0f" : "%.2f", v)
    }
}
