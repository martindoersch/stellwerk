// Persönliche Einstellungen: liegen über der mitgelieferten Belegung (Vorgabe).
// Gespeichert in ~/Library/Application Support/Stellwerk/settings.json
import Foundation

/// Unterstützte Geräte; der Rohwert ist zugleich der Name der Belegungsdateien
enum DeviceID: String, CaseIterable, Codable, Hashable {
    case loupedeck = "loupedeck-plus"
    case tourbox = "tourbox-elite-plus"
    case quickkeys = "xencelabs-quick-keys"

    var profileFile: String { rawValue + ".json" }              // Gerät: Signal → Beschriftung
    var mappingFile: String { rawValue + "-captureone.json" }   // Belegung für Capture One
}

/// Belegung einer Taste, wenn sie von der Vorgabe abweicht
enum ButtonChoice: Codable, Equatable {
    case action(String)   // Capture-One-Aktion, z. B. "0x111"
    case keys(String)     // Tastenkürzel, z. B. "cmd+d"
    case off              // bewusst unbelegt
}

/// Wohin Tasten und Drehregler wirken
enum TargetMode: String, Codable, CaseIterable {
    case captureOne   // immer Capture One, egal welches Programm vorne ist
    case frontmost    // Profil des vorderen Programms; ohne eigenes Profil Capture One
}

/// Persönliche Capture-One-Belegung eines Geräts
struct DeviceSettings: Codable, Equatable {
    var buttons: [String: ButtonChoice] = [:]
    var fnButtons: [String: ButtonChoice] = [:]   // Fn (bzw. Kombi-Taste) halten + Taste
}

/// Drehregler in einem Programmprofil: Tastenkürzel je Richtung und beim Drücken
struct DialKeys: Codable, Equatable {
    var left: String?
    var right: String?
    var press: String?
    var isEmpty: Bool { left == nil && right == nil && press == nil }
}

/// Belegung eines Geräts in einem Programmprofil (nur Tastenkürzel)
struct AppBindings: Codable, Equatable {
    var buttons: [String: String] = [:]     // Taste → Kürzel, z. B. "cmd+z"
    var fnButtons: [String: String] = [:]
    var dials: [String: DialKeys] = [:]
    var labels: [String: String]?           // Kurznamen fürs Quick-Keys-Display (aus der Vorgabe)
    var fnLabels: [String: String]?

    init(buttons: [String: String] = [:], fnButtons: [String: String] = [:], dials: [String: DialKeys] = [:]) {
        self.buttons = buttons; self.fnButtons = fnButtons; self.dials = dials
    }

    // Fehlende Abschnitte (z. B. kein fnButtons in der Vorgabe) → leer statt Fehler
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttons = try c.decodeIfPresent([String: String].self, forKey: .buttons) ?? [:]
        fnButtons = try c.decodeIfPresent([String: String].self, forKey: .fnButtons) ?? [:]
        dials = try c.decodeIfPresent([String: DialKeys].self, forKey: .dials) ?? [:]
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels)
        fnLabels = try c.decodeIfPresent([String: String].self, forKey: .fnLabels)
    }
}

/// Belegung für ein anderes Programm als Capture One, je Gerät
struct AppProfile: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var devices: [String: AppBindings] = [:]   // DeviceID.rawValue → Belegung
    var id: String { bundleID }

    init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }

    func bindings(_ d: DeviceID) -> AppBindings { devices[d.rawValue] ?? AppBindings() }
    mutating func update(_ d: DeviceID, _ change: (inout AppBindings) -> Void) {
        var b = bindings(d)
        change(&b)
        devices[d.rawValue] = b
    }

    private enum CodingKeys: String, CodingKey { case bundleID, name, devices }
    private enum LegacyKeys: String, CodingKey { case buttons, fnButtons, dials }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        devices = try c.decodeIfPresent([String: AppBindings].self, forKey: .devices) ?? [:]
        // Ältere Fassung: Belegung direkt im Profil = Loupedeck
        let l = try decoder.container(keyedBy: LegacyKeys.self)
        if devices.isEmpty, l.contains(.buttons) || l.contains(.dials) {
            devices[DeviceID.loupedeck.rawValue] = AppBindings(
                buttons: try l.decodeIfPresent([String: String].self, forKey: .buttons) ?? [:],
                fnButtons: try l.decodeIfPresent([String: String].self, forKey: .fnButtons) ?? [:],
                dials: try l.decodeIfPresent([String: DialKeys].self, forKey: .dials) ?? [:])
        }
    }

    static let defaultsFile = "app-profiles.json"

    /// Mitgelieferte Vorgaben (app-profiles.json). Hinweistexte werden vorher entfernt,
    /// sonst scheitert das Lesen der Drehregler. nil = Datei fehlt oder ist ungültig.
    static func loadDefaults() -> [AppProfile]? {
        func strip(_ v: Any) -> Any {
            if let d = v as? [String: Any] { return d.filter { $0.key != "_hinweis" }.mapValues(strip) }
            if let a = v as? [Any] { return a.map(strip) }
            return v
        }
        guard let json = MappingStore.load(defaultsFile), let list = json["profiles"],
              let data = try? JSONSerialization.data(withJSONObject: strip(list)) else { return nil }
        return try? JSONDecoder().decode([AppProfile].self, from: data)
    }
}

struct UserSettings: Codable, Equatable {
    var speed = 1.0          // Grundgeschwindigkeit (× Schrittweite)
    var acceleration = 1.0   // 0 = aus, 1 = Standard (×2 / ×4 bei schnellem Drehen)
    var fine = 0.2           // Alt/⌥ halten
    var coarse = 4.0         // Shift/⇧ halten
    var devices: [String: DeviceSettings] = [:]   // DeviceID.rawValue → Capture-One-Belegung
    var showHUD = true       // Einblendung beim Moduswechsel
    var targetMode = TargetMode.captureOne
    var appProfiles: [AppProfile] = []

    init() {}

    func device(_ d: DeviceID) -> DeviceSettings { devices[d.rawValue] ?? DeviceSettings() }
    mutating func updateDevice(_ d: DeviceID, _ change: (inout DeviceSettings) -> Void) {
        var s = device(d)
        change(&s)
        devices[d.rawValue] = s
    }

    /// Profil eines Programms ändern (legt es nicht an)
    mutating func updateProfile(_ bundleID: String, _ change: (inout AppProfile) -> Void) {
        guard let i = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        change(&appProfiles[i])
    }

    private enum CodingKeys: String, CodingKey {
        case speed, acceleration, fine, coarse, devices, showHUD, targetMode, appProfiles
    }
    private enum LegacyKeys: String, CodingKey { case buttons, fnButtons }

    // Fehlende Felder (ältere settings.json) → Vorgabe statt Fehler
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings()
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        acceleration = try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration
        fine = try c.decodeIfPresent(Double.self, forKey: .fine) ?? d.fine
        coarse = try c.decodeIfPresent(Double.self, forKey: .coarse) ?? d.coarse
        devices = try c.decodeIfPresent([String: DeviceSettings].self, forKey: .devices) ?? d.devices
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        targetMode = try c.decodeIfPresent(TargetMode.self, forKey: .targetMode) ?? d.targetMode
        appProfiles = try c.decodeIfPresent([AppProfile].self, forKey: .appProfiles) ?? d.appProfiles
        // Ältere Fassung: Tastenbelegung direkt in den Einstellungen = Loupedeck
        let l = try decoder.container(keyedBy: LegacyKeys.self)
        if devices[DeviceID.loupedeck.rawValue] == nil, l.contains(.buttons) || l.contains(.fnButtons) {
            devices[DeviceID.loupedeck.rawValue] = DeviceSettings(
                buttons: try l.decodeIfPresent([String: ButtonChoice].self, forKey: .buttons) ?? [:],
                fnButtons: try l.decodeIfPresent([String: ButtonChoice].self, forKey: .fnButtons) ?? [:])
        }
    }

    static var url: URL {
        MappingStore.userDir.deletingLastPathComponent().appendingPathComponent("settings.json")
    }

    static func load() -> UserSettings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(UserSettings.self, from: data) else { return UserSettings() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.url, options: .atomic)
    }
}

extension Mapping {
    /// Vorgabe + persönliche Einstellungen = wirksame Belegung eines Geräts
    func applying(_ s: UserSettings, device: DeviceID) -> Mapping {
        var m = self
        m.speed = s.speed
        m.accel.mediumFactor = 1 + s.acceleration
        m.accel.fastFactor = 1 + 3 * s.acceleration
        m.fineFactor = s.fine
        m.coarseFactor = s.coarse
        func apply(_ choices: [String: ButtonChoice], to target: inout [String: ButtonBinding]) {
            for (name, choice) in choices {
                switch choice {
                case .action(let h): if let id = hexID(h) { target[name] = .action(id) }
                case .keys(let k): if let kc = Keys.parse(k) { target[name] = .keys(kc) }
                case .off: target[name] = nil
                }
            }
        }
        let d = s.device(device)
        apply(d.buttons, to: &m.buttons)
        apply(d.fnButtons, to: &m.fnButtons)
        return m
    }
}

/// Wirksame Belegung eines Geräts in einem Programmprofil (Kürzel schon gelesen)
struct AppMapping {
    struct Dial { var left: KeyCombo?; var right: KeyCombo?; var press: KeyCombo? }
    var name = ""
    var buttons: [String: KeyCombo] = [:]
    var fnButtons: [String: KeyCombo] = [:]
    var dials: [String: Dial] = [:]
    var labels: [String: String] = [:]
    var fnLabels: [String: String] = [:]

    init(_ p: AppProfile, device: DeviceID) {
        name = p.name
        let b = p.bindings(device)
        func parse(_ s: String?) -> KeyCombo? { s.flatMap { Keys.parse($0) } }
        buttons = b.buttons.compactMapValues { parse($0) }
        fnButtons = b.fnButtons.compactMapValues { parse($0) }
        labels = b.labels ?? [:]
        fnLabels = b.fnLabels ?? [:]
        dials = b.dials.mapValues { Dial(left: parse($0.left), right: parse($0.right), press: parse($0.press)) }
    }
}
