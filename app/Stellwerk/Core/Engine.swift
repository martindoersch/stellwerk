// Kern: nimmt Control-Ereignisse der Eingabe-Adapter, wendet Belegung und Modi an und
// schickt Aktionen an die Ausgabe-Adapter. Hält den Zustand fürs Statusmenü.
import AppKit
import Observation
import ServiceManagement

@Observable
final class Engine {
    enum KeyMode: String { case stars = "Sterne", colors = "Farben", modifiers = "Tasten (Shift/Ctrl/Cmd/Alt/Tab)" }

    static let captureOneBundleID = "com.captureone.captureone16"
    static let mappingFiles = ["loupedeck-plus.json", "loupedeck-plus-captureone.json", "capture-one-controls.json"]

    // MARK: Zustand fürs Menü
    var deviceName: String?
    var hubState = TangentHub.State.starting
    var accessibilityOK = Accessibility.isTrusted
    var keyMode = KeyMode.stars
    var bwActive = false
    var lastAction = "–"
    var warnings: [String] = []
    var values: [UInt32: Float] = [:]
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var settings = UserSettings.load()

    // MARK: Bausteine
    private(set) var catalog = Catalog()
    private(set) var profile = DeviceProfile()
    private(set) var mapping = Mapping()
    private(set) var defaultMapping = Mapping()   // mitgelieferte Belegung ohne persönliche Änderungen
    private let midi = MIDIInput(match: "Loupedeck")
    private let hub = TangentHub()
    private let keys = KeyOutput()

    private var held = Set<String>()                 // gerade gedrückte Tasten am Gerät
    private var lastTick: [String: TimeInterval] = [:]

    init() {
        loadMappings()
        keys.onLog = { [weak self] in self?.log($0) }
        hub.onLog = { [weak self] in self?.log($0) }
        hub.onState = { [weak self] st in
            guard let self else { return }
            self.hubState = st
            if case .connected = st {
                self.log("Capture One verbunden")
                for p in self.mapping.allParams { self.hub.request(p) }   // Startwerte holen
            }
        }
        hub.onValue = { [weak self] id, v, _ in self?.values[id] = v }
        midi.onConnection = { [weak self] name in self?.deviceName = name }
        midi.onMessage = { [weak self] s, d1, d2 in self?.handleMIDI(status: s, d1, d2) }

        hub.start()
        midi.start()
        Accessibility.request()
        startTapWhenTrusted()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keys.releaseAll(); self?.hub.stop() }
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

    // MARK: Belegung

    func loadMappings() {
        warnings.removeAll()
        if let c = MappingStore.load("capture-one-controls.json") { catalog = Catalog(json: c) }
        else { warnings.append("capture-one-controls.json fehlt") }
        if let p = MappingStore.load("loupedeck-plus.json") { profile = DeviceProfile(json: p) }
        else { warnings.append("loupedeck-plus.json fehlt – Gerät anlernen") }
        if let m = MappingStore.load("loupedeck-plus-captureone.json") { defaultMapping = Mapping(json: m, catalog: catalog) }
        else { warnings.append("loupedeck-plus-captureone.json fehlt oder ist kein gültiges JSON") }
        mapping = defaultMapping.applying(settings)
        warnings += mapping.warnings
        keyMode = .stars
        bwActive = false
        if hub.isConnected { for p in mapping.allParams { hub.request(p) } }
    }

    func reloadMappings() {
        loadMappings()
        log(warnings.isEmpty ? "Belegung neu geladen" : "Belegung geladen, \(warnings.count) Hinweis(e)")
    }

    func openMappingFolder() {
        NSWorkspace.shared.open(MappingStore.prepareUserDir(files: Self.mappingFiles))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { log("Autostart: \(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshAccessibility() { accessibilityOK = Accessibility.isTrusted }

    // MARK: Einstellungen

    /// Ändert die Einstellungen, speichert sie und macht sie sofort wirksam
    func updateSettings(_ change: (inout UserSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        s.save()
        mapping = defaultMapping.applying(s)
    }

    func describe(_ b: ButtonBinding?) -> String {
        switch b {
        case .action(let a)?: return catalog.name(a)
        case .keys(let k)?: return prettyKeys(k.text)
        case nil: return "–"
        }
    }

    /// Tasten mit fester Sonderfunktion (in den Einstellungen nicht frei belegbar)
    func specialRole(_ name: String) -> String? {
        if name == mapping.modeToggle { return "Umschalter Sterne/Farben (Fn: Tasten)" }
        if name == mapping.fnKey { return "Fn (in Kombination)" }
        if name == mapping.bwToggle { return "Schwarzweiß + Farbregler umschalten" }
        if mapping.modeKeys.contains(name) { return "Stern/Farbe/Taste je nach Modus" }
        return nil
    }

    private func log(_ s: String) {
        lastAction = s
        #if DEBUG
        print(s)
        #endif
    }

    // MARK: MIDI → Control-Ereignis

    private func handleMIDI(status: UInt8, _ d1: Int, _ d2: Int) {
        switch status & 0xF0 {
        case 0xB0:
            let ticks = d2 < 64 ? d2 : d2 - 128   // relativ: 01 = +1, 7F = −1
            if let name = profile.dialByCC[d1] { turn(name, ticks: ticks) } else { log("CC \(d1): nicht angelernt") }
        case 0x90 where d2 > 0:
            if let name = profile.nameByNote[d1] { press(name) } else { log("Note \(d1): nicht angelernt") }
        case 0x80, 0x90:   // NoteOff bzw. NoteOn mit Velocity 0 = losgelassen
            if let name = profile.nameByNote[d1] { release(name) }
        default: break
        }
    }

    // MARK: Router

    /// Belegung eines Drehreglers in der gerade aktiven Ebene
    private func dialBinding(_ name: String) -> DialBinding? {
        (bwActive ? mapping.bwDials[name] : nil) ?? mapping.dials[name]
    }

    func turn(_ name: String, ticks: Int) {
        guard let b = dialBinding(name) else { log("\(name): nicht belegt"); return }
        if let plus = b.plus, let minus = b.minus {   // Drehregler löst Aktionen aus
            let a = ticks > 0 ? plus : minus
            for _ in 0 ..< abs(ticks) { hub.action(a) }
            log("\(name): \(catalog.name(a))")
            return
        }
        guard let p = b.param else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let ms = (now - (lastTick[name] ?? 0)) * 1000
        lastTick[name] = now
        let acc = mapping.accel
        let factor = ms < acc.fastMs ? acc.fastFactor : ms < acc.mediumMs ? acc.mediumFactor : 1
        hub.change(p, by: Float(Double(ticks) * b.perTick * mapping.speed * factor * modifierFactor()))
        lastAction = catalog.name(p)
    }

    /// Alt/⌥ = fein, Shift/⇧ = grob (fein gewinnt, wenn beides gehalten wird)
    private func modifierFactor() -> Double {
        let kb = mapping.keyboardModifiers ? CGEventSource.flagsState(.combinedSessionState) : []
        let pad = keyMode == .modifiers
        if kb.contains(.maskAlternate) || (pad && held.contains("Alt")) { return mapping.fineFactor }
        if kb.contains(.maskShift) || (pad && held.contains("Shift")) { return mapping.coarseFactor }
        return 1
    }

    func press(_ name: String) {
        held.insert(name)
        let m = mapping

        if name == m.modeToggle {
            keyMode = held.contains(m.fnKey) ? .modifiers : (keyMode == .stars ? .colors : .stars)
            log("Modus: \(keyMode.rawValue)")
            return
        }
        if let i = m.modeKeys.firstIndex(of: name) {
            let fn = held.contains(m.fnKey)
            switch keyMode {
            case .stars: if let a = fn ? m.starsClear : m.starIDs[safe: i] { trigger(a) }
            case .colors: if let a = fn ? m.colorsClear : m.colorIDs[safe: i] { trigger(a) }
            case .modifiers: keys.postReal(name, down: true); lastAction = "Taste \(name)"
            }
            return
        }
        if name == m.fnKey { return }   // Fn wirkt nur in Kombination
        if name == m.bwToggle {
            bwActive.toggle()
            log("Farbregler: \(bwActive ? "Schwarzweiß" : "Farbbalance")")
            if let a = m.bwAction { hub.action(a) }
            return
        }
        switch m.buttons[name] {
        case .action(let a)?: trigger(a)
        case .keys(let k)?: log("\(name): \(k.text)"); keys.send(k, toBundleID: Self.captureOneBundleID)
        case nil:
            if let p = dialBinding(name)?.param { hub.reset(p); log("\(catalog.name(p)) zurückgesetzt") }
            else { log("\(name): nicht belegt") }
        }
    }

    func release(_ name: String) {
        held.remove(name)
        if keys.realDown.contains(name) { keys.postReal(name, down: false) }
    }

    private func trigger(_ a: UInt32) {
        hub.action(a)
        log(catalog.name(a))
    }

    // MARK: Anzeige

    func value(of name: String) -> String? {
        guard let p = dialBinding(name)?.param, let v = values[p] else { return nil }
        return String(format: abs(v) >= 100 ? "%.0f" : "%.2f", v)
    }
}
