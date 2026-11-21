// TourBox-Mitschreiber (USB-Kabel): zeigt die Rohdaten der seriellen Schnittstelle als Hex.
// Start: swift tourbox_monitor.swift                → listet serielle Geräte (/dev/cu.*)
//        swift tourbox_monitor.swift /dev/cu.X      → liest mit 115200 Baud mit
//        swift tourbox_monitor.swift /dev/cu.X elite      → schickt vorher Unlock + Konfiguration (Elite/Elite Plus)
//        swift tourbox_monitor.swift /dev/cu.X "55 AA …"  → schickt vorher diese Bytes
// Die TourBox Console vorher beenden – sie hält die Schnittstelle sonst belegt.
import Foundation

let args = CommandLine.arguments
setvbuf(stdout, nil, _IOLBF, 0)   // zeilenweise ausgeben, auch durch „| tee"

guard args.count > 1 else {
    let devs = (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?
        .filter { $0.hasPrefix("cu.") }.sorted() ?? []
    print("Serielle Geräte:")
    for d in devs { print("  /dev/\(d)") }
    print("\nTourBox ist meist /dev/cu.usbmodem… oder /dev/cu.usbserial… – damit neu starten.")
    exit(0)
}

let path = args[1]
let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
guard fd >= 0 else { print("Kann \(path) nicht öffnen: \(String(cString: strerror(errno)))"); exit(1) }

// Roh-Modus, 115200 Baud, 8N1 – danach wieder blockierend lesen
var t = termios()
tcgetattr(fd, &t)
cfmakeraw(&t)
cfsetspeed(&t, speed_t(B115200))
t.c_cflag |= tcflag_t(CLOCAL | CREAD)
tcsetattr(fd, TCSANOW, &t)
_ = fcntl(fd, F_SETFL, 0)

func send(_ hex: String) {
    let clean = hex.replacingOccurrences(of: " ", with: "")
    let bytes = stride(from: 0, to: clean.count, by: 2).compactMap { i -> UInt8? in
        let s = clean.index(clean.startIndex, offsetBy: i)
        return UInt8(clean[s ..< clean.index(s, offsetBy: 2)], radix: 16)
    }
    _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    print("→ gesendet (\(bytes.count) Bytes): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
}

if args.count > 2 {
    if args[2] == "elite" {
        // Quelle: tuxbox (AndyCappDev), device_usb.py + haptic.py – Elite/Elite Plus senden erst nach Unlock + Konfiguration
        send("5500078894001afe")
        usleep(300_000)
        send("b5005d04" + "00050006000700080009000b000c000d" + "000e000f0026002700280029003b003c003d003e"
             + "003f004000410042004300440045004600470048" + "0049004a004b004c004d004e004f005000510052"
             + "0053005400a800a900aa00ab00fe")
    } else {
        send(args[2])
    }
}

print("Lese \(path) … Tasten drücken, Regler drehen (Ctrl+C beendet)")
let start = Date()
var buf = [UInt8](repeating: 0, count: 256)
while true {
    let n = read(fd, &buf, buf.count)
    if n < 0 { print("Lesefehler: \(String(cString: strerror(errno)))"); break }
    if n == 0 { continue }
    let hex = buf[0..<n].map { String(format: "%02X", $0) }.joined(separator: " ")
    let bin = buf[0..<n].map { String($0, radix: 2).leftPad(8) }.joined(separator: " ")
    print(String(format: "%8.3f  ", Date().timeIntervalSince(start)) + hex + "   " + bin)
}

extension String {
    func leftPad(_ n: Int) -> String { String(repeating: "0", count: max(0, n - count)) + self }
}
