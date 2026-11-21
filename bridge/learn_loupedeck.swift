// Geführtes Anlernen: fragt jedes Bedienelement des Loupedeck+ einzeln ab
// (Bildschirm + Sprachausgabe), merkt sich die MIDI-Meldung und schreibt
// mappings/loupedeck-plus.json.
//
// Start (im Ordner bridge):  swift learn_loupedeck.swift
// Enter = Element gibt es nicht / überspringen, "z" + Enter = vorheriges wiederholen
import CoreMIDI
import Foundation

enum Kind: String { case dial, button }
struct Item { let name: String; let kind: Kind }

// Reihenfolge nach Gruppen; Positionen auf dem Gerät sind nicht dokumentiert,
// daher fragen wir nach Beschriftung.
let items: [Item] =
    ["Contrast", "Exposure", "Clarity", "Shadows", "Highlights", "Whites", "Blacks",
     "Vibrance", "Saturation", "White Balance / Temp", "Tint", "D1", "D2",
     "Control Dial (großes Rad)"].map { Item(name: $0, kind: .dial) } +
    ["Farbregler 1 (Rot)", "Farbregler 2 (Orange)", "Farbregler 3 (Gelb)", "Farbregler 4 (Grün)",
     "Farbregler 5 (Aqua)", "Farbregler 6 (Blau)", "Farbregler 7 (Lila)", "Farbregler 8 (Magenta)"]
        .map { Item(name: $0, kind: .dial) } +
    (["Hue", "Sat", "Lum", "Clr/BW"] +
     (1...8).map { "P\($0)" } +
     ["L1", "L2", "L3"] + (1...6).map { "C\($0)" } +
     ["Undo", "Redo", "Copy", "Paste", "Before/After", "Export", "Screen Mode", "Custom Mode",
      "--/Clr (Sterne/Farben)"] +
     (0...5).map { "Bewertungstaste \($0) (falls vorhanden)" } +
     ["Pfeil links", "Pfeil rechts", "Pfeil oben", "Pfeil unten", "Fn"])
        .map { Item(name: $0, kind: .button) }

// MARK: MIDI

let lock = NSLock()
var waitingFor: Kind?
var captured: (status: UInt8, number: UInt8)?
let signal = DispatchSemaphore(value: 0)

var client = MIDIClientRef()
MIDIClientCreateWithBlock("HardwareController-Learn" as CFString, &client, nil)
var port = MIDIPortRef()
MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
    for packet in list.unsafeSequence() {
        for word in packet.words() where word >> 28 == 0x2 {
            let status = UInt8((word >> 16) & 0xFF), number = UInt8((word >> 8) & 0xFF)
            let type = status & 0xF0
            lock.lock()
            if let kind = waitingFor, captured == nil,
               (kind == .dial && type == 0xB0) || (kind == .button && type == 0x90) {
                captured = (status, number)
                waitingFor = nil
                signal.signal()
            }
            lock.unlock()
        }
    }
}

func displayName(_ obj: MIDIObjectRef) -> String {
    var n: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &n)
    return (n?.takeRetainedValue() as String?) ?? ""
}
var connected = false
for i in 0..<MIDIGetNumberOfSources() where displayName(MIDIGetSource(i)).contains("Loupedeck") {
    MIDIPortConnectSource(port, MIDIGetSource(i), nil)
    connected = true
}
guard connected else { print("Loupedeck+ nicht gefunden – angesteckt? Loupedeck-Software beendet?"); exit(1) }

// Enter auf stdin = überspringen
var lastLine = ""
Thread {
    while let line = readLine() {
        lock.lock()
        if waitingFor != nil { lastLine = line; waitingFor = nil; signal.signal() }
        lock.unlock()
    }
}.start()

func say(_ text: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-v", "Anna", text]
    try? p.run()
}

// MARK: Ablauf

setvbuf(stdout, nil, _IOLBF, 0)
print("Loupedeck+ anlernen – \(items.count) Elemente. Enter = überspringen, z + Enter = zurück.\n")
var results: [String: [String: Any]] = [:]
var i = 0
while i < items.count {
    let item = items[i]
    let verb = item.kind == .dial ? "Drehe" : "Drücke"
    print(String(format: "[%2d/%d] %@: %@ … ", i + 1, items.count, verb, item.name), terminator: "")
    fflush(stdout)
    say("\(verb) \(item.name.components(separatedBy: " (").first!)")

    lock.lock(); captured = nil; lastLine = ""; waitingFor = item.kind; lock.unlock()
    signal.wait()
    lock.lock(); let got = captured; let line = lastLine; lock.unlock()

    if let got {
        let ch = Int(got.status & 0x0F) + 1
        let type = item.kind == .dial ? "cc" : "note"
        results[item.name] = ["kind": item.kind.rawValue, "channel": ch, type: Int(got.number)]
        print("\(type) \(got.number)")
        Thread.sleep(forTimeInterval: item.kind == .dial ? 1.2 : 0.4)   // Nachlauf ignorieren
        i += 1
    } else if line.lowercased() == "z" {
        print("zurück")
        i = max(0, i - 1)
    } else {
        print("übersprungen")
        i += 1
    }
}

// Doppelte Zuordnungen melden
var seen: [String: String] = [:]
for (name, r) in results.sorted(by: { $0.key < $1.key }) {
    let key = "\(r["kind"]!)-\(r["cc"] ?? r["note"]!)"
    if let other = seen[key] { print("⚠️  \(name) und \(other) senden dasselbe (\(key))") }
    seen[key] = name
}

let out = URL(fileURLWithPath: "mappings/loupedeck-plus.json")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let json = try JSONSerialization.data(withJSONObject: ["device": "Loupedeck+", "controls": results],
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: out)
print("\nGespeichert: bridge/\(out.path) (\(results.count) Elemente)")
say("Fertig, danke!")
Thread.sleep(forTimeInterval: 1.5)
