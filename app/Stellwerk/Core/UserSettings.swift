// Persönliche Einstellungen: liegen über der mitgelieferten Belegung (Vorgabe).
// Gespeichert in ~/Library/Application Support/Stellwerk/settings.json
import Foundation

/// Belegung einer Taste, wenn sie von der Vorgabe abweicht
enum ButtonChoice: Codable, Equatable {
    case action(String)   // Capture-One-Aktion, z. B. "0x111"
    case keys(String)     // Tastenkürzel, z. B. "cmd+d"
    case off              // bewusst unbelegt
}

struct UserSettings: Codable, Equatable {
    var speed = 1.0          // Grundgeschwindigkeit (× Schrittweite)
    var acceleration = 1.0   // 0 = aus, 1 = Standard (×2 / ×4 bei schnellem Drehen)
    var fine = 0.2           // Alt/⌥ halten
    var coarse = 4.0         // Shift/⇧ halten
    var buttons: [String: ButtonChoice] = [:]
    var fnButtons: [String: ButtonChoice] = [:]   // Fn halten + Taste
    var showHUD = true       // Einblendung beim Moduswechsel

    init() {}

    // Fehlende Felder (ältere settings.json) → Vorgabe statt Fehler
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings()
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        acceleration = try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration
        fine = try c.decodeIfPresent(Double.self, forKey: .fine) ?? d.fine
        coarse = try c.decodeIfPresent(Double.self, forKey: .coarse) ?? d.coarse
        buttons = try c.decodeIfPresent([String: ButtonChoice].self, forKey: .buttons) ?? d.buttons
        fnButtons = try c.decodeIfPresent([String: ButtonChoice].self, forKey: .fnButtons) ?? d.fnButtons
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
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
    /// Vorgabe + persönliche Einstellungen = wirksame Belegung
    func applying(_ s: UserSettings) -> Mapping {
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
        apply(s.buttons, to: &m.buttons)
        apply(s.fnButtons, to: &m.fnButtons)
        return m
    }
}
