// Eingabe-Adapter Xencelabs Quick Keys (HID, Kabel oder Funk-Dongle): 8 Tasten mit Display, Taste unten,
// Rad mit Taste, LED-Ring. Schreibt auch zurück: Tastentexte, Einblendung, Ringfarbe. Protokoll: docs/quickkeys-protokoll.md
// Parallel zum Xencelabs-Treiber (Tablett) nur sinnvoll, wenn dort die Quick-Keys-Tasten deaktiviert sind.
import Foundation
import IOKit.hid

final class QuickKeysInput {
    var onButton: ((Int, Bool) -> Void)?       // Tastennummer 0–9, gedrückt? (auf dem Main-Thread)
    var onWheel: ((Int) -> Void)?              // +1 = rechts, −1 = links
    var onConnection: ((String?) -> Void)?     // Gerätename oder nil
    var onReady: (() -> Void)?                 // angemeldet → Display neu beschriften
    var onBattery: ((Int) -> Void)?            // Akkustand in Prozent
    var onLog: ((String) -> Void)?

    static let vendorID = 0x28BD
    private static let wirelessPID = 0x5203
    private static let usagePage = 0xFF0A      // herstellerspezifische Schnittstelle (auch beim Dongle)
    static let name = "Xencelabs Quick Keys"

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var deviceID: [UInt8]?             // Funk: Geräte-ID hinter dem Dongle (Byte 10–15 beim Senden)
    private var buttons: UInt16 = 0
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    // Senden dauert über Funk ~16 ms pro Report → eigene Warteschlange, damit der Main-Thread frei bleibt
    private let sendQueue = DispatchQueue(label: "Stellwerk.QuickKeys")
    private var shownTexts: [Int: String] = [:]
    private var pendingTexts: [Int: String] = [:]
    private var pendingOverlay: (String, UInt8)?
    private var flushScheduled = false

    var isConnected: Bool { device != nil && (deviceID != nil || !isWireless) }
    private var isWireless = false

    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: Self.vendorID,
                                          kIOHIDPrimaryUsagePageKey: Self.usagePage] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // Rückrufe kommen über den Main-Runloop
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
            MainActor.assumeIsolated { Unmanaged<QuickKeysInput>.fromOpaque(ctx!).takeUnretainedValue().attach(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, dev in
            MainActor.assumeIsolated { Unmanaged<QuickKeysInput>.fromOpaque(ctx!).takeUnretainedValue().detach(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    func stop() {
        if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }

    private func attach(_ dev: IOHIDDevice) {
        guard device == nil else { return }   // ein Gerät genügt
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, buffer, 64, { ctx, _, _, _, _, report, length in
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { Unmanaged<QuickKeysInput>.fromOpaque(ctx!).takeUnretainedValue().handle(bytes) }
        }, ctx)
        isWireless = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int) == Self.wirelessPID
        if isWireless {
            send(report([1: 0xB8, 2: 0x01]))   // Dongle: angemeldete Geräte melden → Antwort 0xF8
        } else {
            hello()
        }
    }

    private func detach(_ dev: IOHIDDevice) {
        guard dev == device else { return }
        lost()
        device = nil
    }

    /// Gerät weg (Dongle abgesteckt, Funk verloren): gehaltene Tasten loslassen
    private func lost() {
        for i in 0 ..< 10 where buttons & (1 << i) != 0 { onButton?(i, false) }
        buttons = 0
        deviceID = nil
        shownTexts.removeAll()
        onConnection?(nil)
    }

    private func hello() {
        send(report([1: 0xB0, 2: 0x04]))   // Tasten- und Radereignisse
        send(report([1: 0xB4, 2: 0x10]))   // Akku
        shownTexts.removeAll()
        onConnection?(Self.name)
        onReady?()
    }

    // MARK: Empfangen (Byte 0 = Report-ID 0x02)

    private func handle(_ r: [UInt8]) {
        guard r.count >= 18, r[0] == 0x02 else { return }
        switch r[1] {
        case 0xF8:   // Dongle: Gerätestatus, ID in Byte 10–15
            switch r[2] {
            case 2, 3: deviceID = Array(r[10 ..< 16]); hello()
            case 4: lost()
            default: break
            }
        case 0xF0 where r[7] != 0:   // Rad: eine Meldung pro Raste
            onWheel?(r[7] & 0x01 != 0 ? 1 : -1)
        case 0xF0:   // Tasten: Bitmaske, Tasten 0–7 in Byte 2, 8 (unten) und 9 (Rad) in Byte 3
            let now = UInt16(r[2]) | UInt16(r[3]) << 8
            let changed = now ^ buttons
            buttons = now
            for i in 0 ..< 10 where changed & (1 << i) != 0 { onButton?(i, now & (1 << i) != 0) }
        case 0xF2 where r[2] == 0x01:   // Akku (nach dem Abonnieren und bei Änderung)
            onBattery?(Int(r[3]))
        default: break
        }
    }

    // MARK: Senden

    /// Text neben Taste 0–7 (höchstens 8 Zeichen). Gleiche Texte werden nicht erneut geschickt.
    func setText(_ key: Int, _ text: String) {
        guard (0 ..< 8).contains(key) else { return }
        pendingTexts[key] = String(text.prefix(8))
        scheduleFlush()
    }

    /// Einblendung quer übers Display (höchstens 32 Zeichen)
    func overlay(_ text: String, seconds: UInt8 = 1) {
        pendingOverlay = (text, max(1, seconds))
        scheduleFlush()
    }

    /// Alles beim nächsten Mal neu schicken, z. B. wenn der Xencelabs-Treiber dazwischengeschrieben hat
    func invalidate() { shownTexts.removeAll() }

    func ring(_ rgb: UInt32) {
        guard isConnected else { return }
        send(report([1: 0xB4, 2: 0x01, 3: 0x01,
                     6: UInt8(rgb >> 16 & 0xFF), 7: UInt8(rgb >> 8 & 0xFF), 8: UInt8(rgb & 0xFF)]))
    }

    // Beim Drehen ändern sich Werte schnell → höchstens alle 60 ms schicken, nur das Neueste
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        guard isConnected else { return }
        for (key, text) in pendingTexts.sorted(by: { $0.key < $1.key }) where shownTexts[key] != text {
            shownTexts[key] = text
            send(textReport([1: 0xB1, 3: UInt8(key + 1)], Array(text.utf16)))
        }
        pendingTexts.removeAll()
        if let (text, seconds) = pendingOverlay {
            // Blöcke zu 8 Zeichen: erster 0x05, danach immer mindestens ein 0x06; Byte 6 = es folgt noch einer
            let chars = Array(text.prefix(32).utf16)
            for (n, offset) in stride(from: 0, to: max(chars.count, 9), by: 8).enumerated() {
                let chunk = Array(chars[min(offset, chars.count) ..< min(offset + 8, chars.count)])
                let more: UInt8 = n > 0 && chars.count > offset + 8 ? 1 : 0
                send(textReport([1: 0xB1, 2: n == 0 ? 0x05 : 0x06, 3: seconds, 6: more], chunk))
            }
            pendingOverlay = nil
        }
    }

    /// 32-Byte-Report, Byte 0 = Report-ID 0x02; beim Dongle die Geräte-ID in Byte 10–15
    private func report(_ bytes: [Int: UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 32)
        r[0] = 0x02
        for (i, v) in bytes { r[i] = v }
        if let id = deviceID { r.replaceSubrange(10 ..< 16, with: id) }
        return r
    }

    /// Report mit Text: Länge in Byte 5, UTF-16LE ab Byte 16 (8 Zeichen)
    private func textReport(_ bytes: [Int: UInt8], _ utf16: [UInt16]) -> [UInt8] {
        var r = report(bytes)
        let chars = utf16.prefix(8)
        r[5] = UInt8(chars.count * 2)
        for (i, c) in chars.enumerated() { r[16 + i * 2] = UInt8(c & 0xFF); r[17 + i * 2] = UInt8(c >> 8) }
        return r
    }

    private func send(_ r: [UInt8]) {
        guard let device else { return }
        let target = HIDTarget(device: device, owner: self)
        sendQueue.async {
            let res = r.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(target.device, kIOHIDReportTypeOutput, CFIndex(r[0]), $0.baseAddress!, r.count)
            }
            guard res != kIOReturnSuccess else { return }
            let code = String(format: "0x%08X", res)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    target.owner?.onLog?(String(localized: "Quick Keys: Senden fehlgeschlagen (\(code))"))
                }
            }
        }
    }
}

/// IOHIDDevice und schwache Rückverbindung in die Sende-Warteschlange mitnehmen (SetReport ist threadsicher)
private final class HIDTarget: @unchecked Sendable {
    let device: IOHIDDevice
    weak var owner: QuickKeysInput?
    init(device: IOHIDDevice, owner: QuickKeysInput) { self.device = device; self.owner = owner }
}
