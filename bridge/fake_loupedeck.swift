// Virtuelles Test-Gerät „Loupedeck Test": Stellwerk erkennt es wie ein echtes Loupedeck+.
// Drückt 3× --/Clr (Note 65) und 1× Clr/BW (Note 101) – zum Testen ohne Hardware.
// Start: swift bridge/fake_loupedeck.swift (Stellwerk muss laufen)
import CoreMIDI
import Foundation
var c = MIDIClientRef(); MIDIClientCreate("fake" as CFString, nil, nil, &c)
var src = MIDIEndpointRef(); MIDISourceCreate(c, "Loupedeck Test" as CFString, &src)
func send(_ b: [UInt8]) {
    var list = MIDIPacketList(); var p = MIDIPacketListInit(&list)
    p = MIDIPacketListAdd(&list, 1024, p, 0, b.count, b)
    MIDIReceived(src, &list)
}
Thread.sleep(forTimeInterval: 3)       // App findet die neue Quelle
for _ in 0..<3 { send([0x90, 65, 64]); Thread.sleep(forTimeInterval: 0.1); send([0x80, 65, 0]); Thread.sleep(forTimeInterval: 0.8) }
send([0x90, 101, 64]); Thread.sleep(forTimeInterval: 0.1); send([0x80, 101, 0])   // Clr/BW
Thread.sleep(forTimeInterval: 2)
print("fake fertig")
