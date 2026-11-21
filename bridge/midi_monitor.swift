// MIDI-Mitschreiber: zeigt alle Meldungen einer MIDI-Quelle (Standard: Loupedeck+).
// Start: swift midi_monitor.swift ["Gerätename"]
import CoreMIDI
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Loupedeck+"

func name(of obj: MIDIObjectRef) -> String {
    var n: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &n)
    return (n?.takeRetainedValue() as String?) ?? "?"
}

func describe(_ b: [UInt8]) -> String {
    let hex = b.map { String(format: "%02X", $0) }.joined(separator: " ")
    guard let s = b.first else { return hex }
    let ch = Int(s & 0x0F) + 1
    switch s & 0xF0 {
    case 0x90: return "\(hex)   NoteOn  ch\(ch) note=\(b[1]) vel=\(b[2])"
    case 0x80: return "\(hex)   NoteOff ch\(ch) note=\(b[1])"
    case 0xB0:
        let v = Int(b[2]), rel = v < 64 ? "+\(v)" : "-\(128 - v)"
        return "\(hex)   CC      ch\(ch) cc=\(b[1]) wert=\(v) (relativ \(rel))"
    case 0xE0: return "\(hex)   PitchBend ch\(ch) wert=\(Int(b[1]) | Int(b[2]) << 7)"
    default: return hex
    }
}

var client = MIDIClientRef()
MIDIClientCreateWithBlock("HardwareController-Monitor" as CFString, &client, nil)

var port = MIDIPortRef()
MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
    for packet in list.unsafeSequence() {
        for word in packet.words() where word >> 28 == 0x2 {   // MIDI-1.0-Kanalmeldung
            let b = [UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF)]
            let t = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
            print(t, describe(b))
        }
    }
}

var found = false
for i in 0..<MIDIGetNumberOfSources() {
    let src = MIDIGetSource(i)
    if name(of: src).contains(wanted) {
        MIDIPortConnectSource(port, src, nil)
        found = true
        print("Höre auf:", name(of: src))
    }
}
if !found { print("Quelle \(wanted) nicht gefunden"); exit(1) }
setvbuf(stdout, nil, _IOLBF, 0)
RunLoop.main.run()
