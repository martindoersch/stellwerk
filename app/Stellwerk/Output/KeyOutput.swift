// Ausgabe-Adapter Tastatur: Menüeinträge per Bedienungshilfen klicken, echte Tasten melden,
// Event-Tap für gehaltene Modifier. Braucht die Freigabe unter
// Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen.
import AppKit
import ApplicationServices

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fragt einmalig nach der Freigabe (System-Dialog)
    @discardableResult
    static func request() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class KeyOutput {
    var onLog: ((String) -> Void)?

    // MARK: Tastenkürzel an eine App (über deren Menü)

    /// Undo & Co. wirken aufs aktive Fenster → App bei Bedarf kurz nach vorne holen,
    /// dann den Menüeintrag mit diesem Kürzel klicken (sprachunabhängig). Notlösung: Tastendruck.
    func send(_ k: KeyCombo, toBundleID bundleID: String) {
        guard Accessibility.isTrusted else { onLog?("⚠️ Bedienungshilfen-Freigabe fehlt"); return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            onLog?("⚠️ \(bundleID) läuft nicht"); return
        }
        if app.isActive {
            deliver(k, to: app)
        } else {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.deliver(k, to: app) }
            }
        }
    }

    /// Kürzel ans vordere Programm (Programmprofile). Ohne Menüsuche = schneller, z. B. für Drehregler.
    func sendToFront(_ k: KeyCombo, viaMenu: Bool = true) {
        guard Accessibility.isTrusted else { onLog?("⚠️ Bedienungshilfen-Freigabe fehlt"); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        deliver(k, to: app, viaMenu: viaMenu)
    }

    private func deliver(_ k: KeyCombo, to app: NSRunningApplication, viaMenu: Bool = true) {
        if viaMenu, let title = pressMenuItem(pid: app.processIdentifier, k) {
            onLog?("Menü „\(title)\"")
            return
        }
        // Kein Menüeintrag (z. B. Enter, Esc): als echter Tastendruck an die vorderste App,
        // die wir gerade nach vorne geholt haben. postToPid landete teils im Terminal.
        if !k.flags.contains(.maskCommand) { onLog?("Taste \(prettyKeys(k.text))") }
        else { onLog?("kein Menüeintrag für \(prettyKeys(k.text)) → Tastendruck") }
        // Gehaltene Modifier (Mac-Tastatur oder Loupedeck im Tasten-Modus) wirken mit, z. B. Shift + Pfeil
        let live = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        var flags = k.flags.union(live).union(CGEventFlags(rawValue: ModifierTap.extra))
        if (123...126).contains(k.code) { flags.formUnion([.maskNumericPad, .maskSecondaryFn]) }   // Pfeiltasten wie echt
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: k.code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Modifier-Kodierung der Bedienungshilfen: Shift 1, Option 2, Control 4, ohne ⌘ 8 (⌘ ist Standard)
    private static func axModifiers(_ k: KeyCombo) -> Int {
        var mods = 0
        if k.flags.contains(.maskShift) { mods |= 1 }
        if k.flags.contains(.maskAlternate) { mods |= 2 }
        if k.flags.contains(.maskControl) { mods |= 4 }
        if !k.flags.contains(.maskCommand) { mods |= 8 }
        return mods
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Schlüssel für das Verzeichnis der Menü-Kürzel
    static func menuKey(_ k: KeyCombo) -> String? { k.char.map { "\(axModifiers(k)):\($0)" } }

    /// Alle Kürzel aus der Menüleiste eines Programms → „Menü › Eintrag" (auch selbst vergebene Kürzel)
    static func menuShortcuts(pid: pid_t) -> [String: String] {
        var out: [String: String] = [:]
        func walk(_ el: AXUIElement, path: [String], depth: Int) {
            let title = attr(el, kAXTitleAttribute) as? String ?? ""
            if let c = attr(el, kAXMenuItemCmdCharAttribute) as? String, !c.isEmpty, !title.isEmpty {
                let mods = attr(el, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
                let key = "\(mods):\(c.uppercased())"
                if out[key] == nil { out[key] = (path + [title]).joined(separator: " › ") }
            }
            guard depth < 8, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return }
            // Nur Titel von Menüs/Einträgen in den Pfad, nicht die unsichtbaren Menü-Container
            let next = depth > 0 && !title.isEmpty && title != path.last ? path + [title] : path
            for kid in kids { walk(kid, path: next, depth: depth + 1) }
        }
        let appEl = AXUIElementCreateApplication(pid)
        if let bar = attr(appEl, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            walk(bar as! AXUIElement, path: [], depth: 0)
        }
        return out
    }

    /// Sucht in der Menüleiste den Eintrag mit diesem Kürzel und klickt ihn; liefert dessen Titel.
    private func pressMenuItem(pid: pid_t, _ k: KeyCombo) -> String? {
        guard let ch = k.char, k.flags.contains(.maskCommand) else { return nil }
        let mods = Self.axModifiers(k)
        func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? { Self.attr(el, name) }

        func search(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            if let c = attr(el, kAXMenuItemCmdCharAttribute) as? String, c.uppercased() == ch,
               (attr(el, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0) == mods { return el }
            guard depth < 6, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
            for kid in kids { if let hit = search(kid, depth: depth + 1) { return hit } }
            return nil
        }
        let appEl = AXUIElementCreateApplication(pid)
        guard let bar = attr(appEl, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let item = search(bar as! AXUIElement, depth: 0) else { return nil }
        let title = attr(item, kAXTitleAttribute) as? String ?? k.text
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? title : nil
    }

    // MARK: Echte Tasten (Modifier-Modus)

    static let realKeys: [String: (code: CGKeyCode, flag: CGEventFlags?)] = [
        "Shift": (56, .maskShift), "Ctrl": (59, .maskControl), "Cmd": (55, .maskCommand),
        "Alt": (58, .maskAlternate), "Tab": (48, nil)]
    private(set) var realDown = Set<String>()

    func postReal(_ name: String, down: Bool) {
        guard let k = Self.realKeys[name] else { return }
        if down { realDown.insert(name) } else { realDown.remove(name) }
        var flags: CGEventFlags = []
        for n in realDown { if let f = Self.realKeys[n]?.flag { flags.insert(f) } }
        ModifierTap.setExtraFlags(flags)
        let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: k.code, keyDown: down)
        if k.flag != nil { e?.type = .flagsChanged }
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    /// Beim Beenden nichts „hängen" lassen
    func releaseAll() { for n in realDown { postReal(n, down: false) } }
}

/// Echte Maus- und Tastatur-Ereignisse tragen nur den Zustand der echten Tastatur.
/// Solange am Gerät Shift/Cmd/… gehalten wird, setzt der Event-Tap die Taste dazu.
enum ModifierTap {
    nonisolated(unsafe) private static var extraFlags: UInt64 = 0
    nonisolated(unsafe) private static var tap: CFMachPort?
    nonisolated private static let lock = NSLock()

    nonisolated static func setExtraFlags(_ f: CGEventFlags) {
        lock.lock(); extraFlags = f.rawValue; lock.unlock()
    }

    nonisolated private static func currentExtra() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return extraFlags
    }

    static var isRunning: Bool { tap != nil }

    /// Gerade am Gerät gehaltene Modifier
    nonisolated static var extra: UInt64 { currentExtra() }

    @discardableResult
    static func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                    .rightMouseDragged, .otherMouseDown, .otherMouseUp, .scrollWheel,
                                    .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = ModifierTap.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let extra = ModifierTap.currentExtra()
            if extra != 0 { event.flags = CGEventFlags(rawValue: event.flags.rawValue | extra) }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
        guard let tap else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
