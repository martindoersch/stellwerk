// Eingabe-Adapter TourBox Elite (Plus) per USB-Kabel: serielles Gerät, ein Byte pro Druck/Raste.
// Ohne Unlock + Konfiguration sendet die Elite nichts. Protokoll: docs/tourbox-protokoll.md
// Die TourBox Console darf nicht laufen – sie hält die Schnittstelle sonst belegt.
import Foundation
import IOKit
import IOKit.serial

final class TourBoxInput {
    var onByte: ((UInt8) -> Void)?             // Ereignis-Byte (auf dem Main-Thread)
    var onConnection: ((String?) -> Void)?     // Gerätename oder nil
    var onLog: ((String) -> Void)?

    static let vendorID = 0xC251               // TourBoxTech

    private static let unlock = "5500078894001afe"
    // Vorlage aus tuxbox (haptic.py), Haptik aus
    private static let config = "b5005d04" + "00050006000700080009000b000c000d" + "000e000f0026002700280029003b003c003d003e"
        + "003f004000410042004300440045004600470048" + "0049004a004b004c004d004e004f005000510052"
        + "0053005400a800a900aa00ab00fe"

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var timer: Timer?
    private var ignoreUntil: TimeInterval = 0   // Antwort auf die Konfiguration ist kein Tastendruck
    private var lastFailedPath: String?

    func start() {
        connect()
        // An- und Abstecken: alle 2 s nachsehen, solange keine TourBox verbunden ist
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.fd < 0 { self.connect() } }
        }
    }

    func stop() { disconnect() }

    private func connect() {
        guard let (path, name) = Self.findPort() else { lastFailedPath = nil; return }
        let f = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else {
            if lastFailedPath != path {   // nur einmal melden, nicht alle 2 s
                onLog?(String(localized: "TourBox: \(path) belegt – TourBox Console beenden? (\(String(cString: strerror(errno))))"))
                lastFailedPath = path
            }
            return
        }
        lastFailedPath = nil
        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(f, TCSANOW, &t)
        tcflush(f, TCIOFLUSH)
        fd = f

        let src = DispatchSource.makeReadSource(fileDescriptor: f, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        src.setCancelHandler { close(f) }
        src.resume()
        source = src

        send(Self.unlock)
        ignoreUntil = ProcessInfo.processInfo.systemUptime + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fd == f else { return }
                self.send(Self.config)
                self.ignoreUntil = ProcessInfo.processInfo.systemUptime + 0.5
            }
        }
        onConnection?(name)
    }

    private func disconnect() {
        guard fd >= 0 else { return }
        source?.cancel()   // schließt die Datei
        source = nil
        fd = -1
        onConnection?(nil)
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                // Nur kurz nach Unlock/Konfiguration verwerfen (Antwortblock). Später nie nach Größe filtern:
                // gestaute Rasten kämen sonst samt „losgelassen" weg → Side bliebe gehalten.
                guard ProcessInfo.processInfo.systemUptime >= ignoreUntil else { continue }
                for b in buf[0 ..< n] { onByte?(b) }
            } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                return
            } else {   // 0 = abgesteckt, sonst Fehler
                disconnect()
                return
            }
        }
    }

    private func send(_ hex: String) {
        let chars = Array(hex.utf8)
        let bytes = stride(from: 0, to: chars.count - 1, by: 2).compactMap {
            UInt8(String(decoding: chars[$0 ... $0 + 1], as: UTF8.self), radix: 16)
        }
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    }

    /// Sucht die serielle Schnittstelle einer TourBox (Hersteller-Kennung) → Pfad und Gerätename
    private static func findPort() -> (String, String)? {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return nil }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        let up = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        while case let service = IOIteratorNext(it), service != 0 {
            defer { IOObjectRelease(service) }
            let vendor = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "idVendor" as CFString, nil, up) as? Int
            guard vendor == vendorID,
                  let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                      .takeRetainedValue() as? String else { continue }
            let name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "USB Product Name" as CFString, nil, up) as? String
            return (path, name ?? "TourBox")
        }
        return nil
    }
}
