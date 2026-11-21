// Belegungsdaten: Geräteprofil (MIDI → Beschriftung), Belegung (Beschriftung → Aktion),
// Capture-One-Katalog (Namen, Schrittweiten). Alles JSON, siehe ARCHITEKTUR.md.
import AppKit
import Carbon.HIToolbox
import CoreGraphics

func hexID(_ s: String) -> UInt32? {
    let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
    return UInt32(t, radix: 16)
}

func hexStr(_ id: UInt32) -> String { String(format: "0x%X", id) }

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

/// Einträge eines Abschnitts; Hinweistexte wie "_hinweis" (keine Objekte) werden übersprungen.
/// (Ein strenger Cast auf [String: [String: Any]] verwarf sonst den ganzen Abschnitt.)
func entries(_ v: Any?) -> [String: [String: Any]] {
    (v as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
}

// MARK: - Dateien

/// Belegungen liegen im App-Bundle (Vorgabe) und können im Benutzerordner überschrieben werden:
/// ~/Library/Application Support/Stellwerk/Mappings/<datei>.json
enum MappingStore {
    static var userDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stellwerk/Mappings", isDirectory: true)
    }

    static func url(_ name: String) -> URL? {
        let user = userDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: user.path) { return user }
        return Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "json")
    }

    static func load(_ name: String) -> [String: Any]? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Legt den Benutzerordner an und kopiert fehlende Vorgaben hinein (zum Bearbeiten).
    static func prepareUserDir(files: [String]) -> URL {
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        for f in files {
            let dst = userDir.appendingPathComponent(f)
            guard !FileManager.default.fileExists(atPath: dst.path),
                  let src = Bundle.main.url(forResource: (f as NSString).deletingPathExtension, withExtension: "json")
            else { continue }
            try? FileManager.default.copyItem(at: src, to: dst)
        }
        return userDir
    }
}

// MARK: - Capture-One-Katalog

struct C1Control { let name: String; let isParam: Bool; let step: Double; var group = "" }

struct Catalog {
    var items: [UInt32: C1Control] = [:]

    init() {}

    init(json: [String: Any]) {
        guard let groups = json["groups"] as? [[String: Any]] else { return }
        var counts: [String: Int] = [:]
        for g in groups {
            for i in g["items"] as? [[String: Any]] ?? [] { counts[i["name"] as? String ?? "", default: 0] += 1 }
        }
        for g in groups {
            for i in g["items"] as? [[String: Any]] ?? [] {
                guard let idStr = i["id"] as? String, let id = hexID(idStr), let name = i["name"] as? String else { continue }
                let display = (counts[name] ?? 0) > 1 ? "\(g["name"] as? String ?? "") \(name)" : name
                items[id] = C1Control(name: display, isParam: i["kind"] as? String == "parameter",
                                      step: i["step"] as? Double ?? 0.1, group: g["name"] as? String ?? "")
            }
        }
    }

    func name(_ id: UInt32) -> String { items[id]?.name ?? hexStr(id) }

    /// Alle auslösbaren Aktionen (keine Regler), nach Gruppe und Name sortiert
    var actions: [(id: UInt32, control: C1Control)] {
        items.filter { !$0.value.isParam }.map { (id: $0.key, control: $0.value) }
            .sorted { ($0.control.group, $0.control.name) < ($1.control.group, $1.control.name) }
    }
}

// MARK: - Geräteprofil

struct DeviceProfile {
    var device = "Loupedeck+"
    var dialByCC: [Int: String] = [:]
    var nameByNote: [Int: String] = [:]   // Tasten und Drücken der Drehregler
    var buttons: [String] = []            // echte Tasten, in sinnvoller Reihenfolge

    init() {}

    init(json: [String: Any]) {
        device = json["device"] as? String ?? device
        let controls = entries(json["controls"])
        // Drücken eines Drehreglers sendet die Note mit seiner CC-Nummer; echte Tasten haben Vorrang
        for (name, c) in controls { if let cc = c["cc"] as? Int { dialByCC[cc] = name; nameByNote[cc] = name } }
        for (name, c) in controls { if let note = c["note"] as? Int { nameByNote[note] = name } }
        let order = ["Undo", "Redo", "Copy", "Paste", "Before/After", "Export", "Screen Mode", "Custom Mode"]
            + (1...8).map { "P\($0)" } + (1...6).map { "C\($0)" } + ["L1", "L2", "L3", "Hue", "Sat", "Lum", "Clr/BW"]
            + ["Pfeil links", "Pfeil rechts", "Pfeil oben", "Pfeil unten"]
        let names = controls.filter { $0.value["note"] != nil }.map(\.key)
        buttons = order.filter(names.contains) + names.filter { !order.contains($0) }.sorted()
    }
}

// MARK: - Tastenkürzel

struct KeyCombo { let code: CGKeyCode; let flags: CGEventFlags; let text: String; let char: String? }

enum Keys {
    static let named: [String: CGKeyCode] = ["left": 123, "right": 124, "down": 125, "up": 126, "return": 36,
                                             "tab": 48, "space": 49, "delete": 51, "esc": 53]

    /// Sucht im aktuellen Tastaturlayout die Taste, die `ch` erzeugt (deutsch: Z und Y vertauscht).
    static func keyCode(for ch: Character) -> CGKeyCode? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in 0 ..< 128 {
                var dead: UInt32 = 0, len = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let st = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
                if st == noErr, len == 1, String(utf16CodeUnits: chars, count: 1) == String(ch) { return CGKeyCode(code) }
            }
            return nil
        }
    }

    /// "cmd+z", "cmd+shift+z", "alt+left" …
    static func parse(_ s: String) -> KeyCombo? {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        var char: String?
        for part in s.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default:
                code = named[part] ?? (part.count == 1 ? keyCode(for: part.first!) : nil)
                if part.count == 1 { char = part.uppercased() }
            }
        }
        return code.map { KeyCombo(code: $0, flags: flags, text: s, char: char) }
    }
}

// MARK: - Belegung

struct DialBinding { var param: UInt32?; var perTick: Double; var plus: UInt32?; var minus: UInt32? }
struct Accel { var fastMs = 20.0, fastFactor = 4.0, mediumMs = 45.0, mediumFactor = 2.0 }

/// Lesbare Form eines Tastenkürzels: "cmd+shift+z" → "⇧⌘Z"
func prettyKeys(_ s: String) -> String {
    var mods = "", key = ""
    for part in s.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "ctrl": mods = "⌃" + mods
        case "alt", "opt": mods += "⌥"
        case "shift": mods += "⇧"
        case "cmd": mods += "⌘"
        default:
            let sym = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "tab": "⇥",
                       "space": "Leertaste", "delete": "⌫", "esc": "⎋"]
            key = sym[part] ?? part.uppercased()
        }
    }
    // Reihenfolge wie bei Apple: ⌃⌥⇧⌘
    let ordered = ["⌃", "⌥", "⇧", "⌘"].filter(mods.contains).joined()
    return ordered + key
}
enum ButtonBinding { case action(UInt32), keys(KeyCombo) }

struct Mapping {
    var app = "Capture One"
    var dials: [String: DialBinding] = [:]
    var buttons: [String: ButtonBinding] = [:]
    var fnButtons: [String: ButtonBinding] = [:]   // Fn halten + Taste
    var accel = Accel()
    var speed = 1.0

    // Fein/Grob (wie Photoshop: Alt = fein, Shift = grob)
    var fineFactor = 0.2
    var coarseFactor = 4.0
    var keyboardModifiers = true

    // Modus-Tasten: Umschalter wechselt Sterne ↔ Farben, Fn + Umschalter = Modifier-Modus
    var modeToggle: String?
    var fnKey = "Fn"
    var modeKeys: [String] = []
    var starIDs: [UInt32] = []
    var colorIDs: [UInt32] = []
    var starsClear: UInt32?
    var colorsClear: UInt32?

    // Schwarzweiß-Ebene der Farbregler
    var bwToggle: String?
    var bwAction: UInt32?
    var bwDials: [String: DialBinding] = [:]

    var warnings: [String] = []

    init() {}

    init(json: [String: Any], catalog: Catalog) {
        app = json["app"] as? String ?? app
        func dialsFrom(_ raw: [String: [String: Any]]) -> [String: DialBinding] {
            var out: [String: DialBinding] = [:]
            for (name, v) in raw {
                let p = (v["param"] as? String).flatMap(hexID)
                out[name] = DialBinding(param: p,
                                        perTick: v["perTick"] as? Double ?? p.flatMap { catalog.items[$0]?.step } ?? 0.1,
                                        plus: (v["plus"] as? String).flatMap(hexID),
                                        minus: (v["minus"] as? String).flatMap(hexID))
            }
            return out
        }

        if let a = json["acceleration"] as? [String: Double] {
            accel = Accel(fastMs: a["fastMs"] ?? 20, fastFactor: a["fastFactor"] ?? 4,
                          mediumMs: a["mediumMs"] ?? 45, mediumFactor: a["mediumFactor"] ?? 2)
        }
        dials = dialsFrom(entries(json["dials"]))
        func buttonsFrom(_ raw: [String: [String: Any]]) -> [String: ButtonBinding] {
            var out: [String: ButtonBinding] = [:]
            for (name, v) in raw {
                if let a = (v["action"] as? String).flatMap(hexID) {
                    out[name] = .action(a)
                } else if let k = v["keys"] as? String {
                    if let combo = Keys.parse(k) { out[name] = .keys(combo) } else { warnings.append("\(name): Tastenkürzel \(k) nicht lesbar") }
                }
            }
            return out
        }
        buttons = buttonsFrom(entries(json["buttons"]))
        fnButtons = buttonsFrom(entries(json["fnButtons"]))

        let mod = json["modifiers"] as? [String: Any] ?? [:]
        fineFactor = mod["fine"] as? Double ?? fineFactor
        coarseFactor = mod["coarse"] as? Double ?? coarseFactor
        keyboardModifiers = mod["keyboard"] as? Bool ?? keyboardModifiers

        let mode = json["modeKeys"] as? [String: Any] ?? [:]
        modeToggle = mode["toggle"] as? String
        fnKey = mode["fn"] as? String ?? fnKey
        modeKeys = mode["keys"] as? [String] ?? []
        starIDs = (mode["stars"] as? [String] ?? []).compactMap(hexID)
        colorIDs = (mode["colors"] as? [String] ?? []).compactMap(hexID)
        starsClear = (mode["starsClear"] as? String).flatMap(hexID)
        colorsClear = (mode["colorsClear"] as? String).flatMap(hexID)

        let bw = json["bwLayer"] as? [String: Any] ?? [:]
        bwToggle = bw["toggle"] as? String
        bwAction = (bw["action"] as? String).flatMap(hexID)
        bwDials = dialsFrom(entries(bw["dials"]))

        // IDs gegen controls.xml prüfen
        guard !catalog.items.isEmpty else { return }
        let buttonIDs = (Array(buttons.values) + Array(fnButtons.values)).compactMap { b -> UInt32? in if case .action(let a) = b { return a } else { return nil } }
        let dialIDs = (Array(dials.values) + Array(bwDials.values)).flatMap { [$0.param, $0.plus, $0.minus].compactMap { $0 } }
        let all = Set(dialIDs + buttonIDs + starIDs + colorIDs + [starsClear, colorsClear, bwAction].compactMap { $0 })
        for id in all where catalog.items[id] == nil { warnings.append("\(hexStr(id)) steht nicht in controls.xml") }
    }

    /// Alle Regler-IDs, deren Startwert wir abfragen
    var allParams: Set<UInt32> { Set((Array(dials.values) + Array(bwDials.values)).compactMap(\.param)) }
}
