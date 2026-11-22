// Belegungsdaten: Geräteprofil (MIDI → Beschriftung), Belegung (Beschriftung → Aktion),
// Capture-One-Katalog (Namen, Schrittweiten). Alles JSON, siehe ARCHITECTURE.md.
import AppKit
import Carbon.HIToolbox
import CoreGraphics

func hexID(_ s: String) -> UInt32? {
    let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
    return UInt32(t, radix: 16)
}

func hexStr(_ id: UInt32) -> String { String(format: "0x%X", id) }

/// Anzeigename eines Bedienelements. Die Namen in den Gerätedateien sind zugleich Schlüssel
/// (Belegung, Einstellungen) und bleiben unverändert; übersetzt wird nur die Anzeige (Tabelle „Controls").
func controlLabel(_ name: String) -> String {
    Bundle.main.localizedString(forKey: name, value: name, table: "Controls")
}

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
    var ids: [String: UInt32] = [:]   // Lightroom-Namen (z. B. "Exposure2012") → ID

    init() {}

    /// Lightroom-Regler und -Aktionen dazunehmen (eigener ID-Bereich, siehe LightroomControls)
    mutating func addLightroom() {
        for (id, c) in LightroomControls.byID {
            items[id] = C1Control(name: c.name, isParam: c.isParam, step: c.step, group: "Lightroom")
            ids[c.key] = id
        }
    }

    /// ID aus der Belegungsdatei: Lightroom-Name oder Hex-ID (Capture One)
    func resolve(_ s: String) -> UInt32? { ids[s] ?? hexID(s) }

    /// Capture-One-Liste vorhanden? (Lightroom ist immer drin)
    var hasCaptureOne: Bool { items.keys.contains { !LightroomControls.contains($0) } }

    init(json: [String: Any]) {
        guard let groups = json["groups"] as? [[String: Any]] else { return }
        var counts: [String: Int] = [:]
        for g in groups {
            for i in g["items"] as? [[String: Any]] ?? [] { counts[i["name"] as? String ?? "", default: 0] += 1 }
        }
        for g in groups {
            for i in g["items"] as? [[String: Any]] ?? [] {
                guard let idStr = i["id"] as? String, let id = hexID(idStr), let name = i["name"] as? String else { continue }
                // Doppelte Namen (z. B. Copy Adjustments) mit Gruppe unterscheiden: "Copy Adjustments (Cursor Tools)"
                let group = (g["name"] as? String ?? "").replacingOccurrences(of: " Shortcuts", with: "")
                let display = (counts[name] ?? 0) > 1 ? "\(name) (\(group))" : name
                items[id] = C1Control(name: display, isParam: i["kind"] as? String == "parameter",
                                      step: i["step"] as? Double ?? 0.1, group: g["name"] as? String ?? "")
            }
        }
    }

    /// Liest die Regler-Liste direkt aus dem installierten Capture One
    /// (`…/Contents/Resources/TangentSettings/controls.xml`). Die Liste gehört Capture One
    /// und wird deshalb nicht mitgeliefert. `nil`, wenn Capture One fehlt.
    static func fromInstalledCaptureOne(bundleID: String) -> Catalog? {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? URL(fileURLWithPath: "/Applications/Capture One.app")
        let xml = app.appendingPathComponent("Contents/Resources/TangentSettings/controls.xml")
        guard let parser = XMLParser(contentsOf: xml) else { return nil }
        let reader = ControlsXMLReader()
        parser.delegate = reader
        guard parser.parse(), !reader.groups.isEmpty else { return nil }
        return Catalog(json: ["groups": reader.groups])
    }

    func name(_ id: UInt32) -> String { items[id]?.name ?? hexStr(id) }

    /// Alle auslösbaren Capture-One-Aktionen (keine Regler), nach Gruppe und Name sortiert
    var actions: [(id: UInt32, control: C1Control)] {
        items.filter { !$0.value.isParam && !LightroomControls.contains($0.key) }.map { (id: $0.key, control: $0.value) }
            .sorted { ($0.control.group, $0.control.name) < ($1.control.group, $1.control.name) }
    }
}

/// Übersetzt `controls.xml` in dieselbe Struktur wie `bridge/parse_controls.py`:
/// `[{name, items: [{id, name, kind, step}]}]`. Nur `Controls/Group/(Parameter|Action)` zählt.
private final class ControlsXMLReader: NSObject, XMLParserDelegate {
    var groups: [[String: Any]] = []
    private var inControls = false
    private var group: [String: Any]?
    private var item: [String: Any]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        text = ""
        switch element {
        case "Controls": inControls = true
        case "Group" where inControls: group = ["name": attributes["name"] ?? "", "items": [[String: Any]]()]
        case "Parameter" where group != nil, "Action" where group != nil:
            item = ["id": attributes["id"] ?? "", "kind": element == "Parameter" ? "parameter" : "action"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "Name" where item != nil: item?["name"] = value
        case "StepSize" where item != nil: item?["step"] = Double(value)
        case "Parameter", "Action":
            if let i = item, var g = group { g["items"] = (g["items"] as? [[String: Any]] ?? []) + [i]; group = g }
            item = nil
        case "Group":
            if let g = group { groups.append(g) }
            group = nil
        case "Controls": inControls = false
        default: break
        }
        text = ""
    }
}

// MARK: - Geräteprofil

struct DeviceProfile {
    var device = "Loupedeck+"
    var dialByCC: [Int: String] = [:]
    var nameByNote: [Int: String] = [:]   // Tasten und Drücken der Drehregler
    var buttons: [String] = []            // echte Tasten, in sinnvoller Reihenfolge
    var dials: [String] = []              // Drehregler, in sinnvoller Reihenfolge
    var layerByCC: [Int: String] = [:]    // Gerät schaltet Ebenen selbst (Loupedeck: Hue/Sat/Lum ändern die CCs der Farbregler)

    init() {}

    init(json: [String: Any]) {
        device = json["device"] as? String ?? device
        let controls = entries(json["controls"])
        // Drücken eines Drehreglers sendet die Note mit seiner CC-Nummer; echte Tasten haben Vorrang
        for (name, c) in controls { if let cc = c["cc"] as? Int { dialByCC[cc] = name; nameByNote[cc] = name } }
        for (name, c) in controls { if let note = c["note"] as? Int { nameByNote[note] = name } }
        // "layerCCs": {"Hue": 1, "Sat": 9, "Lum": 17} – erste CC jeder Ebene; die Drehregler ab der ersten Ebene
        // (CC 1, 2, …) senden in den anderen Ebenen um denselben Abstand verschoben (getestet: Lum, Regler 2 = CC 18)
        if let lay = json["layerCCs"] as? [String: Int], let first = lay.values.min() {
            let layered = controls.compactMap { name, c -> (Int, String)? in
                guard let cc = c["cc"] as? Int, cc >= first, cc < first + 8 else { return nil }
                return (cc, name)
            }
            for (layerName, start) in lay {
                for (cc, name) in layered {
                    dialByCC[start + cc - first] = name
                    layerByCC[start + cc - first] = layerName
                    // Drücken sendet die Note mit derselben Nummer (zurücksetzen); echte Tasten haben Vorrang
                    if nameByNote[start + cc - first] == nil { nameByNote[start + cc - first] = name }
                }
            }
        }
        // Reihenfolge aus der Gerätedatei ("order"/"dialOrder"), sonst die des Loupedeck+
        var loupedeckOrder: [String] = ["Undo", "Redo", "Copy", "Paste", "Before/After", "Export", "Screen Mode", "Custom Mode"]
        loupedeckOrder += (1...8).map { "P\($0)" } + (1...6).map { "C\($0)" }
        loupedeckOrder += ["L1", "L2", "L3", "Hue", "Sat", "Lum", "Clr/BW", "Pfeil links", "Pfeil rechts", "Pfeil oben", "Pfeil unten"]
        let order = json["order"] as? [String] ?? loupedeckOrder
        let names = controls.filter { $0.value["note"] != nil }.map(\.key)
        buttons = order.filter(names.contains) + names.filter { !order.contains($0) }.sorted()
        let dialOrder = json["dialOrder"] as? [String] ?? ["Control Dial (großes Rad)", "Exposure", "Contrast", "Clarity",
                         "Shadows", "Highlights", "Whites", "Blacks", "Vibrance", "Saturation", "White Balance / Temp", "Tint", "D1", "D2"]
        let dialNames = controls.filter { $0.value["cc"] != nil }.map(\.key)
        dials = dialOrder.filter(dialNames.contains) + dialNames.filter { !dialOrder.contains($0) }.sorted()
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
            case "plus": code = keyCode(for: "+"); char = "+"   // „+" ist im Format das Trennzeichen
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

/// Tasten wählen, was ein Drehregler steuert (Quick Keys: T1–T8 → Rad). Mit Kurzname fürs Display und Ringfarbe.
struct DialSelect {
    struct Choice { var binding: DialBinding; var label: String; var color: UInt32? }
    var dial: String?
    var ring: UInt32?                    // Ringfarbe ohne Auswahl
    var keys: [String: Choice] = [:]
}

struct Accel {
    var fastMs = 20.0, fastFactor = 4.0, mediumMs = 45.0, mediumFactor = 2.0
    var smoothing = 0.0         // > 0: gleitender Mittelwert der Abstände, Faktor stufenlos zwischen mediumMs (×1) und fastMs
    var ignoreReverseMs = 0.0   // > 0: einzelne Gegenraste innerhalb dieser Zeit verwerfen (Quick-Keys-Rad)
}

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
                       "space": String(localized: "Leertaste"), "delete": "⌫", "esc": "⎋", "plus": "+"]
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
    var fnDials: [String: DialBinding] = [:]       // Fn halten + drehen
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
    var fnLatch = false                            // Kombi-Taste kurz tippen = Fn-Ebene bleibt, nochmal tippen = zurück
    var fnRing: UInt32?                            // Quick Keys: Ringfarbe, solange die Fn-Ebene aktiv ist
    var labels: [String: String] = [:]             // Kurznamen fürs Display (Quick Keys) …
    var fnLabels: [String: String] = [:]           // … und für die Fn-Ebene
    var modeKeys: [String] = []
    var starIDs: [UInt32] = []
    var colorIDs: [UInt32] = []
    var starsClear: UInt32?
    var colorsClear: UInt32?

    // Schwarzweiß-Ebene der Farbregler
    var bwToggle: String?
    var bwAction: UInt32?
    var bwDials: [String: DialBinding] = [:]

    var dialSelect = DialSelect()

    /// Tasten wählen eine Ebene der Drehregler (Loupedeck in Lightroom: Hue/Sat/Lum → Farbregler).
    /// Die gewählte Ebene bleibt, bis eine andere Ebenen-Taste gedrückt wird; ohne Wahl gilt defaultLayer.
    struct DialLayer { var label: String; var dials: [String: DialBinding] }
    var layers: [String: DialLayer] = [:]
    var defaultLayer: String?

    var warnings: [String] = []

    init() {}

    init(json: [String: Any], catalog: Catalog) {
        app = json["app"] as? String ?? app
        var unknown: [String] = []
        /// Regler/Aktion aus der Datei: Lightroom-Name oder Hex-ID; Unbekanntes wird gemeldet
        func id(_ v: Any?, _ name: String) -> UInt32? {
            guard let s = v as? String else { return nil }
            if let i = catalog.resolve(s) { return i }
            unknown.append("\(name): \(s)")
            return nil
        }
        func dialsFrom(_ raw: [String: [String: Any]]) -> [String: DialBinding] {
            var out: [String: DialBinding] = [:]
            for (name, v) in raw {
                let p = id(v["param"], name)
                out[name] = DialBinding(param: p,
                                        perTick: v["perTick"] as? Double ?? p.flatMap { catalog.items[$0]?.step } ?? 0.1,
                                        plus: id(v["plus"], name),
                                        minus: id(v["minus"], name))
            }
            return out
        }

        let lay = json["layers"] as? [String: Any] ?? [:]
        defaultLayer = lay["default"] as? String
        for (button, v) in entries(lay) {
            layers[button] = DialLayer(label: v["label"] as? String ?? button, dials: dialsFrom(entries(v["dials"])))
        }

        // Hinweistexte überspringen: ein strenger Cast auf [String: Double] verwarf sonst den ganzen Abschnitt
        if let a = (json["acceleration"] as? [String: Any])?.compactMapValues({ $0 as? Double }) {
            accel = Accel(fastMs: a["fastMs"] ?? 20, fastFactor: a["fastFactor"] ?? 4,
                          mediumMs: a["mediumMs"] ?? 45, mediumFactor: a["mediumFactor"] ?? 2,
                          smoothing: a["smoothing"] ?? 0, ignoreReverseMs: a["ignoreReverseMs"] ?? 0)
        }
        dials = dialsFrom(entries(json["dials"]))
        fnDials = dialsFrom(entries(json["fnDials"]))
        func buttonsFrom(_ raw: [String: [String: Any]]) -> [String: ButtonBinding] {
            var out: [String: ButtonBinding] = [:]
            for (name, v) in raw {
                if let a = id(v["action"], name) {
                    out[name] = .action(a)
                } else if let k = v["keys"] as? String {
                    if let combo = Keys.parse(k) { out[name] = .keys(combo) } else { warnings.append(String(localized: "\(name): Tastenkürzel \(k) nicht lesbar")) }
                }
            }
            return out
        }
        buttons = buttonsFrom(entries(json["buttons"]))
        fnButtons = buttonsFrom(entries(json["fnButtons"]))
        labels = entries(json["buttons"]).compactMapValues { $0["label"] as? String }
        fnLabels = entries(json["fnButtons"]).compactMapValues { $0["label"] as? String }
        fnLatch = json["fnLatch"] as? Bool ?? false
        fnRing = (json["fnRing"] as? String).flatMap(hexID)

        let mod = json["modifiers"] as? [String: Any] ?? [:]
        fineFactor = mod["fine"] as? Double ?? fineFactor
        coarseFactor = mod["coarse"] as? Double ?? coarseFactor
        keyboardModifiers = mod["keyboard"] as? Bool ?? keyboardModifiers

        let mode = json["modeKeys"] as? [String: Any] ?? [:]
        modeToggle = mode["toggle"] as? String
        fnKey = json["fn"] as? String ?? mode["fn"] as? String ?? fnKey   // Kombi-Taste, z. B. "Side" bei der TourBox
        modeKeys = mode["keys"] as? [String] ?? []
        starIDs = (mode["stars"] as? [String] ?? []).compactMap { id($0, "stars") }
        colorIDs = (mode["colors"] as? [String] ?? []).compactMap { id($0, "colors") }
        starsClear = id(mode["starsClear"], "starsClear")
        colorsClear = id(mode["colorsClear"], "colorsClear")

        let bw = json["bwLayer"] as? [String: Any] ?? [:]
        bwToggle = bw["toggle"] as? String
        bwAction = id(bw["action"], "bwLayer")
        bwDials = dialsFrom(entries(bw["dials"]))

        let sel = json["dialSelect"] as? [String: Any] ?? [:]
        dialSelect.dial = sel["dial"] as? String
        dialSelect.ring = (sel["ring"] as? String).flatMap(hexID)
        let selKeys = entries(sel["keys"])
        let selDials = dialsFrom(selKeys)
        for (name, b) in selDials {
            dialSelect.keys[name] = DialSelect.Choice(binding: b, label: selKeys[name]?["label"] as? String ?? name,
                                                      color: (selKeys[name]?["color"] as? String).flatMap(hexID))
        }

        warnings += unknown.map { String(localized: "\($0) unbekannt") }
        // IDs gegen controls.xml prüfen
        guard catalog.hasCaptureOne else { return }
        let buttonIDs = (Array(buttons.values) + Array(fnButtons.values)).compactMap { b -> UInt32? in if case .action(let a) = b { return a } else { return nil } }
        let dialIDs = (Array(dials.values) + Array(fnDials.values) + Array(bwDials.values) + Array(selDials.values))
            .flatMap { [$0.param, $0.plus, $0.minus].compactMap { $0 } }
        let all = Set(dialIDs + buttonIDs + starIDs + colorIDs + [starsClear, colorsClear, bwAction].compactMap { $0 })
        for id in all where catalog.items[id] == nil { warnings.append(String(localized: "\(hexStr(id)) steht nicht in controls.xml")) }
    }

    /// Alle Regler-IDs, deren Startwert wir abfragen
    var allParams: Set<UInt32> {
        Set((Array(dials.values) + Array(fnDials.values) + Array(bwDials.values) + dialSelect.keys.values.map(\.binding)
             + layers.values.flatMap(\.dials.values)).compactMap(\.param))
    }
}
