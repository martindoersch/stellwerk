// Xencelabs-Quick-Keys-Mitschreiber (HID, Kabel oder Funk-Dongle): listet die HID-Schnittstellen,
// meldet sich am Gerät an und zeigt Rohdaten + gedeutete Ereignisse. Schreibt zum Test Texte ins Display.
// Start: swift quickkeys_monitor.swift          → anmelden und mitschreiben
//        swift quickkeys_monitor.swift list     → nur Schnittstellen auflisten
//        swift quickkeys_monitor.swift texte "█▓▒░" "äöü" …   → eigene Texte für Taste 0–7 (Schrift testen)
// Den Xencelabs-Treiber vorher beenden – er spricht sonst dazwischen.
// Protokoll-Quelle: Julusian/node-xencelabs-quick-keys (packages/core: device.ts, wireless-device.ts)
// Hinweis: macOS liefert die Report-ID (0x02) als Byte 0 mit, die Offsets hier sind daher um 1 größer als in node.
import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)   // zeilenweise ausgeben, auch durch „| tee"

let vendorID = 0x28BD
let wiredPID = 0x5202, wirelessPID = 0x5203
let listOnly = CommandLine.arguments.dropFirst().first == "list"
let customTexts = CommandLine.arguments.dropFirst().first == "texte" ? Array(CommandLine.arguments.dropFirst(2)) : []
let start = Date()

func prop(_ d: IOHIDDevice, _ key: String) -> Int { (IOHIDDeviceGetProperty(d, key as CFString) as? Int) ?? -1 }
func hex(_ b: some Sequence<UInt8>) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }
func stamp() -> String { String(format: "%8.3f  ", Date().timeIntervalSince(start)) }

// 32-Byte-Report, Byte 0 = Report-ID 0x02; beim Dongle steht die Geräte-ID in Byte 10–15
func report(_ bytes: [Int: UInt8], id: [UInt8]? = nil) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 32)
    r[0] = 0x02
    for (i, v) in bytes { r[i] = v }
    if let id { r.replaceSubrange(10..<16, with: id) }
    return r
}

func send(_ d: IOHIDDevice, _ r: [UInt8], _ what: String) {
    let res = r.withUnsafeBufferPointer { IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, CFIndex(r[0]), $0.baseAddress!, r.count) }
    print(stamp() + "→ \(what): \(hex(r))" + (res == kIOReturnSuccess ? "" : String(format: "  FEHLER 0x%08X", res)))
}

func keyText(_ d: IOHIDDevice, key: Int, _ text: String, id: [UInt8]?) {
    let utf16 = Array(text.prefix(8).utf16)
    var r = report([1: 0xB1, 3: UInt8(key + 1), 5: UInt8(utf16.count * 2)], id: id)
    for (i, c) in utf16.enumerated() { r[16 + i * 2] = UInt8(c & 0xFF); r[17 + i * 2] = UInt8(c >> 8) }
    send(d, r, "Text Taste \(key)")
}

// Overlay bis 32 Zeichen in Blöcken zu 8: erster Block 0x05, danach immer mindestens ein Block 0x06
// (wie node: Byte 6 = „es folgt noch ein Block“, beim ersten Block immer 0)
func overlay(_ d: IOHIDDevice, _ text: String, seconds: UInt8, id: [UInt8]?) {
    let chars = Array(text.prefix(32).utf16)
    for (n, offset) in stride(from: 0, to: max(chars.count, 9), by: 8).enumerated() {
        let chunk = Array(chars[min(offset, chars.count)..<min(offset + 8, chars.count)])
        let more: UInt8 = n > 0 && chars.count > offset + 8 ? 1 : 0
        var r = report([1: 0xB1, 2: n == 0 ? 0x05 : 0x06, 3: seconds, 5: UInt8(chunk.count * 2), 6: more], id: id)
        for (i, c) in chunk.enumerated() { r[16 + i * 2] = UInt8(c & 0xFF); r[17 + i * 2] = UInt8(c >> 8) }
        send(d, r, "Overlay \(n + 1)")
    }
}

// Anmelden: Tasten-/Radereignisse und Akku abonnieren, Testtexte und Ringfarbe setzen
func hello(_ d: IOHIDDevice, id: [UInt8]?) {
    send(d, report([1: 0xB0, 2: 0x04], id: id), "Ereignisse abonnieren")
    send(d, report([1: 0xB4, 2: 0x10], id: id), "Akku abonnieren")
    for k in 0..<8 { keyText(d, key: k, customTexts[safe: k] ?? "Taste \(k)", id: id) }
    send(d, report([1: 0xB4, 2: 0x01, 3: 0x01, 6: 0xC8, 7: 0xF0, 8: 0x00], id: id), "Ring lime")
    overlay(d, "Stellwerk verbunden", seconds: 5, id: id)
}

var lastButtons: [Int: UInt16] = [:]   // je Gerät (Hash), um Drücken/Loslassen zu erkennen
var buffers: [UnsafeMutablePointer<UInt8>] = []

let callback: IOHIDReportCallback = { context, _, sender, _, _, reportPtr, length in
    let d = Unmanaged<IOHIDDevice>.fromOpaque(context!).takeUnretainedValue()
    let r = Array(UnsafeBufferPointer(start: reportPtr, count: length))
    var note = ""
    if r.count > 7, r[0] == 0x02 {
        switch r[1] {
        case 0xF8:   // Dongle: Gerätestatus, ID in Byte 10–15
            let id = Array(r[10..<16])
            let status = ["2": "verbunden", "3": "schon verbunden", "4": "Verbindung verloren"]["\(r[2])"] ?? "Status \(r[2])"
            note = "Dongle: Gerät \(hex(id)) \(status)"
            if r[2] == 2 || r[2] == 3 { DispatchQueue.main.async { hello(d, id: id) } }
        case 0xF0 where r[7] > 0:
            note = r[7] & 0x01 != 0 ? "Rad rechts" : "Rad links"
        case 0xF0:
            let now = UInt16(r[2]) | UInt16(r[3]) << 8
            let before = lastButtons[d.hashValue, default: 0]
            lastButtons[d.hashValue] = now
            let changes = (0..<16).compactMap { i -> String? in
                let bit = UInt16(1) << i
                guard (now ^ before) & bit != 0 else { return nil }
                return "Taste \(i) " + (now & bit != 0 ? "gedrückt" : "los")
            }
            note = changes.joined(separator: ", ")
        case 0xF2 where r[2] == 0x01:
            note = "Akku \(r[3]) %"
        default: break
        }
    }
    print(stamp() + hex(r) + (note.isEmpty ? "" : "   ← " + note))
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
guard !devices.isEmpty else { print("Keine Xencelabs-Geräte gefunden (Hersteller 0x28BD). Dongle/Kabel angesteckt?"); exit(1) }

print("Xencelabs-HID-Schnittstellen:")
for d in devices {
    print(String(format: "  Produkt 0x%04X  UsagePage 0x%04X  Usage 0x%04X  Eingang %d  Ausgang %d  %@",
                 prop(d, kIOHIDProductIDKey), prop(d, kIOHIDPrimaryUsagePageKey), prop(d, kIOHIDPrimaryUsageKey),
                 prop(d, kIOHIDMaxInputReportSizeKey), prop(d, kIOHIDMaxOutputReportSizeKey),
                 (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "?"))
}
if listOnly { exit(0) }

// Die Quick-Keys-Schnittstelle ist herstellerspezifisch (UsagePage ≥ 0xFF00) mit 32-Byte-Ausgang
let targets = devices.filter { prop($0, kIOHIDPrimaryUsagePageKey) >= 0xFF00 && prop($0, kIOHIDMaxOutputReportSizeKey) >= 32 }
guard !targets.isEmpty else { print("Keine passende Schnittstelle (UsagePage ≥ 0xFF00, Ausgang ≥ 32 Bytes)."); exit(1) }

for d in targets {
    let size = max(prop(d, kIOHIDMaxInputReportSizeKey), 64)
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    buffers.append(buf)
    IOHIDDeviceRegisterInputReportCallback(d, buf, size, callback, Unmanaged.passUnretained(d).toOpaque())
    let pid = prop(d, kIOHIDProductIDKey)
    print(String(format: "\nÖffne Produkt 0x%04X (%@)", pid, pid == wirelessPID ? "Funk-Dongle" : pid == wiredPID ? "Kabel" : "unbekannt"))
    if pid == wirelessPID {
        send(d, report([1: 0xB8, 2: 0x01]), "Dongle: Geräte suchen")
    } else {
        hello(d, id: nil)
    }
}

print("\nTasten drücken, Rad drehen (Ctrl+C beendet)")
CFRunLoopRun()

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
