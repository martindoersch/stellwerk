// Stellwerk-Prototyp: Loupedeck+ (MIDI) → Capture One (Tangent-Protokoll)
//
// Die Bridge spielt den Tangent Hub auf 127.0.0.1:64246. Capture One verbindet
// sich nur beim Start → zuerst die Bridge starten, dann Capture One.
//
// Start (im Ordner bridge):  swift stellwerk.swift
//
// Dateien in mappings/:
//   loupedeck-plus.json              MIDI-Nummer → Beschriftung (aus learn_loupedeck.swift)
//   loupedeck-plus-captureone.json   Beschriftung → Capture-One-Regler/-Aktion
//   capture-one-controls.json        Namen und Schrittweiten (aus parse_controls.py)
//
// Terminal-Befehle (zum Testen ohne Gerät):
//   d <Name> <Schritte>   Drehregler simulieren, z. B. "d exposure 5" oder "d tint -3"
//   b <Name>              Taste simulieren, z. B. "b undo"
//   p <id> <delta>        Regler direkt ändern, z. B. "p 0x26 0.1"
//   r <id>                Regler zurücksetzen
//   a <id>                Aktion auslösen, z. B. "a 0x77"
//   l                     Belegung anzeigen
//   q                     beenden
import AppKit
import Carbon.HIToolbox
import CoreMIDI
import Foundation
import Network

setvbuf(stdout, nil, _IOLBF, 0)
let core = DispatchQueue(label: "stellwerk")   // alles Zustandsbehaftete läuft hier
let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("mappings")

func loadJSON(_ name: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func hexID(_ s: String) -> UInt32? {
    let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
    return UInt32(t, radix: 16)
}

func hexStr(_ id: UInt32) -> String { String(format: "0x%X", id) }

// MARK: - Capture-One-Katalog (Namen, Schrittweiten)

struct C1Control { let name: String; let isParam: Bool; let step: Double }
var catalog: [UInt32: C1Control] = [:]
if let c1 = loadJSON("capture-one-controls.json"), let groups = c1["groups"] as? [[String: Any]] {
    var counts: [String: Int] = [:]
    for g in groups { for i in g["items"] as? [[String: Any]] ?? [] { counts[i["name"] as! String, default: 0] += 1 } }
    for g in groups {
        for i in g["items"] as? [[String: Any]] ?? [] {
            guard let id = hexID(i["id"] as! String) else { continue }
            let name = i["name"] as! String
            let display = counts[name]! > 1 ? "\(g["name"]!) \(name)" : name
            catalog[id] = C1Control(name: display, isParam: i["kind"] as? String == "parameter",
                                    step: i["step"] as? Double ?? 0.1)
        }
    }
} else {
    print("⚠️  capture-one-controls.json fehlt – zuerst python3 parse_controls.py")
}
func c1Name(_ id: UInt32) -> String { catalog[id]?.name ?? hexStr(id) }

// MARK: - Tangent Hub

struct Writer {
    var data = Data()
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
}

extension Data {
    func u32(_ off: Int) -> UInt32? {
        guard off + 4 <= count else { return nil }
        return self[startIndex + off ..< startIndex + off + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
    func string(_ off: Int) -> (String, Int)? {
        guard let n = u32(off).map(Int.init), off + 4 + n <= count else { return nil }
        let s = String(decoding: self[startIndex + off + 4 ..< startIndex + off + 4 + n], as: UTF8.self)
        return (s, off + 4 + n)
    }
}

final class TangentHub {
    // Hub → App
    static let initiateComms: UInt32 = 0x01, paramChange: UInt32 = 0x02, paramReset: UInt32 = 0x03
    static let valueRequest: UInt32 = 0x04, actionOn: UInt32 = 0x08, actionOff: UInt32 = 0x0B

    private var listener: NWListener?
    private var conn: NWConnection?
    private var pending: [UInt32: Float] = [:]     // Deltas sammeln, alle 15 ms senden
    private var flushScheduled = false
    private var lastNotConnectedWarning = Date.distantPast
    var onConnected: (() -> Void)?
    var lastValues: [UInt32: Float] = [:]

    func start() {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback   // nur lokal erreichbar
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: 64246) else {
            print("❌ Port 64246 nicht verfügbar"); exit(1)
        }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: print("🟢 Hub lauscht auf 127.0.0.1:64246 – jetzt Capture One starten (oder neu starten)")
            case .failed(let e):
                print("❌ Hub-Fehler: \(e) – läuft schon ein Tangent Hub oder fake_tangent_hub.py?"); exit(1)
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: core)
        listener = l
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: print("🔌 Client verbunden")
            case .failed, .cancelled:
                print("🔌 Verbindung beendet")
                if self?.conn === c { self?.conn = nil }
            default: break
            }
        }
        c.start(queue: core)
        var w = Writer()
        w.u32(Self.initiateComms); w.u32(5); w.u32(0)   // Protokoll-Rev. 5, keine Panels
        send(w.data)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] head, _, done, err in
            guard let self, let head, head.count == 4, err == nil, let n = head.u32(0) else { return }
            if n == 0 { self.receive(c); return }
            c.receive(minimumIncompleteLength: Int(n), maximumLength: Int(n)) { body, _, _, err in
                guard let body, body.count == Int(n), err == nil else { return }
                self.handle(body)
                self.receive(c)
            }
            _ = done
        }
    }

    private func handle(_ body: Data) {
        guard let cmd = body.u32(0) else { return }
        switch cmd {
        case 0x81:   // ApplicationDefinition
            let app = body.string(4)?.0 ?? "?"
            print("✅ Angemeldet: \(app)")
            onConnected?()
        case 0x82:   // ParameterValue: id, float, bool atDefault
            guard let id = body.u32(4), let bits = body.u32(8) else { return }
            let v = Float(bitPattern: bits)
            lastValues[id] = v
            print(String(format: "   ← %@ = %.2f%@", c1Name(id), v, body.u32(12) == 1 ? " (Standard)" : ""))
        case 0x85:
            print("   ← Modus \(hexStr(body.u32(4) ?? 0))")
        case 0x86:   // DisplayText: Anzahl Zeilen, dann Strings
            var lines: [String] = []
            var off = 8
            for _ in 0 ..< Int(body.u32(4) ?? 0) {
                guard let (s, next) = body.string(off) else { break }
                lines.append(s); off = next
            }
            print("   ← Anzeige: \(lines.joined(separator: " | "))")
        default:
            print("   ← Befehl \(hexStr(cmd)) (\(body.count) Bytes)")
        }
    }

    private func send(_ body: Data) {
        guard let conn else {
            if Date().timeIntervalSince(lastNotConnectedWarning) > 3 {
                print("⚠️  Capture One nicht verbunden (Capture One nach der Bridge starten)")
                lastNotConnectedWarning = Date()
            }
            return
        }
        var w = Writer(); w.u32(UInt32(body.count))
        conn.send(content: w.data + body, completion: .contentProcessed { _ in })
    }

    private func cmd(_ c: UInt32, _ id: UInt32, _ f: Float? = nil) {
        var w = Writer(); w.u32(c); w.u32(id)
        if let f { w.f32(f) }
        send(w.data)
    }

    func change(_ id: UInt32, by delta: Float) {
        pending[id, default: 0] += delta
        guard !flushScheduled else { return }
        flushScheduled = true
        core.asyncAfter(deadline: .now() + 0.015) { [self] in
            flushScheduled = false
            for (id, d) in pending where d != 0 { cmd(Self.paramChange, id, d) }
            pending.removeAll()
        }
    }
    func reset(_ id: UInt32) { cmd(Self.paramReset, id) }
    func request(_ id: UInt32) { cmd(Self.valueRequest, id) }
    func action(_ id: UInt32) { cmd(Self.actionOn, id); cmd(Self.actionOff, id) }
}

// MARK: - Tastenkürzel (Ausweg für Funktionen ohne Tangent-ID, z. B. Undo)

let captureOneBundleID = "com.captureone.captureone16"
struct KeyCombo { let code: CGKeyCode; let flags: CGEventFlags; let text: String; let char: String? }

let namedKeys: [String: CGKeyCode] = ["left": 123, "right": 124, "down": 125, "up": 126, "return": 36,
                                      "tab": 48, "space": 49, "delete": 51, "esc": 53]

/// Sucht im aktuellen Tastaturlayout die Taste, die `ch` erzeugt (deutsch: Z und Y vertauscht).
/// Muss auf dem Haupt-Thread laufen (Text-Input-Services).
func keyCode(for ch: Character) -> CGKeyCode? {
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
func parseKeys(_ s: String) -> KeyCombo? {
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
            code = namedKeys[part] ?? (part.count == 1 ? keyCode(for: part.first!) : nil)
            if part.count == 1 { char = part.uppercased() }
        }
    }
    return code.map { KeyCombo(code: $0, flags: flags, text: s, char: char) }
}

/// Sucht in der Menüleiste der App den Eintrag mit diesem Tastenkürzel und klickt ihn
/// (Bedienungshilfen-API). Klappt auch im Hintergrund und unabhängig von der Menüsprache.
func pressMenuItem(pid: pid_t, _ k: KeyCombo) -> Bool {
    guard let ch = k.char, k.flags.contains(.maskCommand) else { return false }
    // Modifier-Kodierung der Bedienungshilfen: Shift 1, Option 2, Control 4 (⌘ ist Standard)
    var mods = 0
    if k.flags.contains(.maskShift) { mods |= 1 }
    if k.flags.contains(.maskAlternate) { mods |= 2 }
    if k.flags.contains(.maskControl) { mods |= 4 }

    func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    func search(_ el: AXUIElement, depth: Int) -> AXUIElement? {
        if let c = attr(el, kAXMenuItemCmdCharAttribute) as? String, c.uppercased() == ch,
           (attr(el, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0) == mods { return el }
        guard depth < 6, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for kid in kids { if let hit = search(kid, depth: depth + 1) { return hit } }
        return nil
    }
    let appEl = AXUIElementCreateApplication(pid)
    guard let bar = attr(appEl, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
          let item = search(bar as! AXUIElement, depth: 0) else { return false }
    let title = attr(item, kAXTitleAttribute) as? String ?? "?"
    let enabled = attr(item, kAXEnabledAttribute) as? Bool ?? true
    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
    print("   Menü „\(title)\" \(enabled ? "aktiv" : "AUSGEGRAUT"), \(err == .success ? "geklickt" : "nicht klickbar (\(err.rawValue))")")
    return err == .success
}

func sendKeys(_ k: KeyCombo) {
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
        print("⚠️  Tastenkürzel brauchen die Freigabe unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen (für das Terminal)")
        return
    }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: captureOneBundleID).first else {
        print("⚠️  Capture One läuft nicht"); return
    }
    // Undo & Co. wirken aufs aktive Fenster → Capture One muss vorne sein
    if !app.isActive {
        print("   Capture One nach vorne holen")
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { deliverKeys(k, to: app) }
    } else {
        deliverKeys(k, to: app)
    }
}

func deliverKeys(_ k: KeyCombo, to app: NSRunningApplication) {
    // 1. Weg: Menüeintrag direkt auslösen (kommt sicher bei Capture One an)
    if pressMenuItem(pid: app.processIdentifier, k) { return }
    // 2. Weg (Notlösung): Tastendruck an Capture One schicken
    print("   kein Menüeintrag für \(k.text) gefunden → Tastendruck")
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: k.code, keyDown: down)
        e?.flags = k.flags
        e?.postToPid(app.processIdentifier)   // gezielt an Capture One, auch im Hintergrund
    }
}

// MARK: - Belegung

struct DialBinding { var param: UInt32?; var perTick: Double; var plus: UInt32?; var minus: UInt32? }
struct Accel { var fastMs = 20.0, fastFactor = 4.0, mediumMs = 45.0, mediumFactor = 2.0 }
enum ButtonBinding { case action(UInt32), keys(KeyCombo) }

var dials: [String: DialBinding] = [:]
var buttons: [String: ButtonBinding] = [:]
var accel = Accel()

guard let binding = loadJSON("loupedeck-plus-captureone.json") else {
    print("❌ mappings/loupedeck-plus-captureone.json fehlt oder ist kein gültiges JSON"); exit(1)
}
if let a = binding["acceleration"] as? [String: Double] {
    accel = Accel(fastMs: a["fastMs"] ?? 20, fastFactor: a["fastFactor"] ?? 4,
                  mediumMs: a["mediumMs"] ?? 45, mediumFactor: a["mediumFactor"] ?? 2)
}
func parseDials(_ raw: [String: [String: Any]]) -> [String: DialBinding] {
    var out: [String: DialBinding] = [:]
    for (name, v) in raw {
        let p = (v["param"] as? String).flatMap(hexID)
        out[name] = DialBinding(param: p,
                                perTick: v["perTick"] as? Double ?? p.flatMap { catalog[$0]?.step } ?? 0.1,
                                plus: (v["plus"] as? String).flatMap(hexID),
                                minus: (v["minus"] as? String).flatMap(hexID))
    }
    return out
}
dials = parseDials(binding["dials"] as? [String: [String: Any]] ?? [:])

// Schwarzweiß-Ebene: Clr/BW schaltet SW ein/aus und belegt die Farbregler um
let bwCfg = binding["bwLayer"] as? [String: Any] ?? [:]
let bwToggle = bwCfg["toggle"] as? String
let bwAction = (bwCfg["action"] as? String).flatMap(hexID)
let bwDials = parseDials(bwCfg["dials"] as? [String: [String: Any]] ?? [:])
var bwActive = false

/// Belegung eines Drehreglers in der gerade aktiven Ebene
func dialBinding(_ name: String) -> DialBinding? { (bwActive ? bwDials[name] : nil) ?? dials[name] }
for (name, v) in binding["buttons"] as? [String: [String: Any]] ?? [:] {
    if let a = (v["action"] as? String).flatMap(hexID) {
        buttons[name] = .action(a)
    } else if let k = v["keys"] as? String {
        if let combo = parseKeys(k) { buttons[name] = .keys(combo) } else { print("⚠️  \(name): Tastenkürzel \(k) nicht lesbar") }
    }
}

// Fein/Grob (wie Photoshop: Alt = fein, Shift = grob)
let modCfg = binding["modifiers"] as? [String: Any] ?? [:]
let fineFactor = modCfg["fine"] as? Double ?? 0.2
let coarseFactor = modCfg["coarse"] as? Double ?? 4
let keyboardModifiers = modCfg["keyboard"] as? Bool ?? true

// Modus-Tasten: --/Clr wechselt Sterne ↔ Farben, Fn + --/Clr = Modifier-Modus
enum KeyMode: String { case stars = "Sterne", colors = "Farben", modifiers = "Modifier (Shift/Ctrl/Cmd/Alt/Tab)" }
let modeCfg = binding["modeKeys"] as? [String: Any] ?? [:]
let modeToggle = modeCfg["toggle"] as? String
let fnKey = modeCfg["fn"] as? String ?? "Fn"
let modeKeys = modeCfg["keys"] as? [String] ?? []
let starIDs = (modeCfg["stars"] as? [String] ?? []).compactMap(hexID)
let colorIDs = (modeCfg["colors"] as? [String] ?? []).compactMap(hexID)
let starsClear = (modeCfg["starsClear"] as? String).flatMap(hexID)
let colorsClear = (modeCfg["colorsClear"] as? String).flatMap(hexID)
var keyMode = KeyMode.stars
var held = Set<String>()   // gerade gedrückte Loupedeck-Tasten

// IDs gegen controls.xml prüfen
let buttonIDs = buttons.values.compactMap { b -> UInt32? in if case .action(let a) = b { return a } else { return nil } }
    + starIDs + colorIDs + [starsClear, colorsClear].compactMap { $0 }
for id in Set((Array(dials.values) + Array(bwDials.values)).flatMap { [$0.param, $0.plus, $0.minus].compactMap { $0 } } + buttonIDs)
where !catalog.isEmpty && catalog[id] == nil {
    print("⚠️  \(hexStr(id)) steht nicht in controls.xml (Test, ob Capture One es trotzdem kennt)")
}

// MIDI-Nummer → Beschriftung aus dem Anlernen
var dialByCC: [Int: String] = [:]
var nameByNote: [Int: String] = [:]   // Tasten und Drücken der Drehregler
if let learned = loadJSON("loupedeck-plus.json"), let controls = learned["controls"] as? [String: [String: Any]] {
    // Drücken eines Drehreglers sendet die Note mit seiner CC-Nummer; echte Tasten haben Vorrang
    for (name, c) in controls { if let cc = c["cc"] as? Int { dialByCC[cc] = name; nameByNote[cc] = name } }
    for (name, c) in controls { if let note = c["note"] as? Int { nameByNote[note] = name } }
    print("🎛  Angelernt: \(dialByCC.count) Drehregler, \(controls.count - dialByCC.count) Tasten")
} else {
    print("ℹ️  mappings/loupedeck-plus.json fehlt – zuerst swift learn_loupedeck.swift. Simulation (d/b) geht trotzdem.")
}

// MARK: - Router

let hub = TangentHub()
var lastTick: [String: TimeInterval] = [:]

func findName(_ query: String, in names: [String]) -> String? {
    let q = query.lowercased()
    if let exact = names.first(where: { $0.lowercased() == q }) { return exact }
    let hits = names.filter { $0.lowercased().hasPrefix(q) }
    return hits.count == 1 ? hits[0] : nil
}

func turn(_ name: String, ticks: Int) {
    guard let b = dialBinding(name) else { print("   \(name): nicht belegt"); return }
    if let plus = b.plus, let minus = b.minus {   // Drehregler löst Aktionen aus
        for _ in 0 ..< abs(ticks) { hub.action(ticks > 0 ? plus : minus) }
        print("→ \(name): \(c1Name(ticks > 0 ? plus : minus)) ×\(abs(ticks))")
        return
    }
    guard let p = b.param else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let ms = (now - (lastTick[name] ?? 0)) * 1000
    lastTick[name] = now
    let factor = ms < accel.fastMs ? accel.fastFactor : ms < accel.mediumMs ? accel.mediumFactor : 1
    hub.change(p, by: Float(Double(ticks) * b.perTick * factor * modifierFactor()))
}

/// Alt/⌥ = fein, Shift/⇧ = grob (fein gewinnt, wenn beides gehalten wird)
func modifierFactor() -> Double {
    let kb = keyboardModifiers ? CGEventSource.flagsState(.combinedSessionState) : []
    let padMods = keyMode == .modifiers
    if kb.contains(.maskAlternate) || (padMods && held.contains("Alt")) { return fineFactor }
    if kb.contains(.maskShift) || (padMods && held.contains("Shift")) { return coarseFactor }
    return 1
}

// Modifier-Modus: Loupedeck-Tasten wirken als echte Tastatur-Tasten (an die App im Vordergrund)
let realKeyCodes: [String: (code: CGKeyCode, flag: CGEventFlags?)] = [
    "Shift": (56, .maskShift), "Ctrl": (59, .maskControl), "Cmd": (55, .maskCommand),
    "Alt": (58, .maskAlternate), "Tab": (48, nil)]
var realDown = Set<String>()   // Tasten, die wir gerade als gedrückt gemeldet haben

func postRealKey(_ name: String, down: Bool) {
    guard let k = realKeyCodes[name] else { return }
    if down { realDown.insert(name) } else { realDown.remove(name) }
    var flags: CGEventFlags = []
    for n in realDown { if let f = realKeyCodes[n]?.flag { flags.insert(f) } }
    extraFlagsLock.lock(); extraFlags = flags.rawValue; extraFlagsLock.unlock()
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: k.code, keyDown: down)
    if k.flag != nil { e?.type = .flagsChanged }
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
}

// Event-Tap: Echte Maus- und Tastatur-Ereignisse tragen nur den Zustand der echten Tastatur.
// Solange am Loupedeck Shift/Cmd/… gehalten wird, setzen wir die Taste hier dazu.
let extraFlagsLock = NSLock()
var extraFlags: UInt64 = 0
var modifierTap: CFMachPort?

func startModifierTap() {
    let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                .rightMouseDragged, .otherMouseDown, .otherMouseUp, .scrollWheel,
                                .keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    modifierTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = modifierTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        extraFlagsLock.lock(); let extra = extraFlags; extraFlagsLock.unlock()
        if extra != 0 { event.flags = CGEventFlags(rawValue: event.flags.rawValue | extra) }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)
    guard let tap = modifierTap else {
        print("⚠️  Event-Tap nicht möglich – Bedienungshilfen-Freigabe fürs Terminal prüfen"); return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("⌨️  Event-Tap aktiv (Loupedeck-Modifier wirken auf Maus und Tastatur)")
}

/// Beim Beenden nichts „hängen" lassen
func releaseAllRealKeys() { for n in realDown { postRealKey(n, down: false) } }

func release(_ name: String) {
    held.remove(name)
    if realDown.contains(name) { postRealKey(name, down: false) }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

func press(_ name: String) {
    held.insert(name)
    if name == modeToggle {
        keyMode = held.contains(fnKey) ? .modifiers : (keyMode == .stars ? .colors : .stars)
        print("🔀 Modus: \(keyMode.rawValue)")
        return
    }
    if let i = modeKeys.firstIndex(of: name) {
        let fn = held.contains(fnKey)
        switch keyMode {
        case .stars:
            if let a = fn ? starsClear : starIDs[safe: i] { print("→ \(name): \(c1Name(a))"); hub.action(a) }
        case .colors:
            if let a = fn ? colorsClear : colorIDs[safe: i] { print("→ \(name): \(c1Name(a))"); hub.action(a) }
        case .modifiers:
            print("⌨️  \(name)\(name == "Alt" ? " (Drehen fein)" : name == "Shift" ? " (Drehen grob)" : "")")
            postRealKey(name, down: true)
        }
        return
    }
    if name == fnKey { return }   // Fn wirkt nur in Kombination
    if name == bwToggle {
        bwActive.toggle()
        print("🔀 Farbregler: \(bwActive ? "Schwarzweiß" : "Farbbalance")")
        if let a = bwAction { hub.action(a) }
        return
    }
    if case .action(let a)? = buttons[name] {
        print("→ \(name): \(c1Name(a))"); hub.action(a)
    } else if case .keys(let k)? = buttons[name] {
        print("→ \(name): Tastenkürzel \(k.text)"); DispatchQueue.main.async { sendKeys(k) }
    } else if let p = dialBinding(name)?.param {
        print("→ \(name) gedrückt: \(c1Name(p)) zurücksetzen"); hub.reset(p)
    } else {
        print("   \(name): nicht belegt")
    }
}

hub.onConnected = {
    for p in Set((Array(dials.values) + Array(bwDials.values)).compactMap(\.param)) { hub.request(p) }   // Startwerte holen
}

// MARK: - MIDI

var client = MIDIClientRef()
MIDIClientCreateWithBlock("Stellwerk" as CFString, &client, nil)
var port = MIDIPortRef()
MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
    for packet in list.unsafeSequence() {
        for word in packet.words() where word >> 28 == 0x2 {
            let status = UInt8((word >> 16) & 0xFF), d1 = Int((word >> 8) & 0x7F), d2 = Int(word & 0x7F)
            core.async {
                switch status & 0xF0 {
                case 0xB0:
                    let ticks = d2 < 64 ? d2 : d2 - 128   // relativ: 01 = +1, 7F = −1
                    if let name = dialByCC[d1] { turn(name, ticks: ticks) } else { print("   CC \(d1): nicht angelernt") }
                case 0x90 where d2 > 0:
                    if let name = nameByNote[d1] { press(name) } else { print("   Note \(d1): nicht angelernt") }
                case 0x80, 0x90:   // NoteOff bzw. NoteOn mit Velocity 0 = losgelassen
                    if let name = nameByNote[d1] { release(name) }
                default: break
                }
            }
        }
    }
}
func midiName(_ obj: MIDIObjectRef) -> String {
    var n: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &n)
    return (n?.takeRetainedValue() as String?) ?? ""
}
var midiConnected = false
for i in 0 ..< MIDIGetNumberOfSources() where midiName(MIDIGetSource(i)).contains("Loupedeck") {
    MIDIPortConnectSource(port, MIDIGetSource(i), nil)
    midiConnected = true
    print("🎛  MIDI: \(midiName(MIDIGetSource(i)))")
}
if !midiConnected { print("ℹ️  Loupedeck+ nicht gefunden – nur Simulation über das Terminal") }

// MARK: - Terminal

hub.start()
DispatchQueue.main.async { startModifierTap() }
Thread {
    while let line = readLine() {
        let parts = line.split(separator: " ").map(String.init)
        guard let c = parts.first else { continue }
        core.async {
            switch c {
            case "q": releaseAllRealKeys(); exit(0)
            case "l":
                for (n, b) in dials.sorted(by: { $0.key < $1.key }) {
                    print("  Regler \(n) → \(b.param.map(c1Name) ?? "\(b.plus.map(c1Name) ?? "") / \(b.minus.map(c1Name) ?? "")")")
                }
                for (n, b) in buttons.sorted(by: { $0.key < $1.key }) {
                    switch b {
                    case .action(let a): print("  Taste  \(n) → \(c1Name(a))")
                    case .keys(let k): print("  Taste  \(n) → Tastenkürzel \(k.text)")
                    }
                }
            case "d" where parts.count >= 3:
                guard let ticks = Int(parts.last!) else { print("? Schritte als Zahl"); return }
                let q = parts.dropFirst().dropLast().joined(separator: " ")
                guard let name = findName(q, in: Array(dials.keys)) else { print("? Regler \(q) unbekannt/mehrdeutig"); return }
                turn(name, ticks: ticks)
            case "b" where parts.count >= 2:
                let q = parts.dropFirst().joined(separator: " ")
                let all = Array(buttons.keys) + Array(dials.keys) + modeKeys + [modeToggle, fnKey, bwToggle].compactMap { $0 }
                guard let name = findName(q, in: all) else { print("? Taste \(q) unbekannt/mehrdeutig"); return }
                press(name); release(name)
            case "p" where parts.count == 3:
                if let id = hexID(parts[1]), let d = Float(parts[2]) { hub.change(id, by: d) } else { print("? p <id> <delta>") }
            case "r" where parts.count == 2:
                if let id = hexID(parts[1]) { hub.reset(id) }
            case "a" where parts.count == 2:
                if let id = hexID(parts[1]) { print("→ Aktion \(c1Name(id))"); hub.action(id) }
            default: print("? Befehle: d <Regler> <Schritte>, b <Taste>, p/r/a <id>, l, q")
            }
        }
    }
    exit(0)   // stdin geschlossen
}.start()

RunLoop.main.run()
