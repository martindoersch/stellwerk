// Eingabe-Adapter MIDI (CoreMIDI): verbindet sich mit allen Quellen, deren Name `match` enthält,
// und meldet sich neu an, wenn Geräte an- oder abgesteckt werden.
import CoreMIDI
import Foundation

final class MIDIInput {
    var onMessage: ((UInt8, Int, Int) -> Void)?   // Status, Data1, Data2 (auf dem Main-Thread)
    var onConnection: ((String?) -> Void)?        // Gerätename oder nil

    private let match: String
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []

    init(match: String) { self.match = match }

    func start() {
        let bridge = MIDIBridge(owner: self)
        client = MIDIInput.makeClient(bridge)
        port = MIDIInput.makePort(client, bridge)
        rescan()
    }

    func rescan() {
        for src in connected { MIDIPortDisconnectSource(port, src) }
        connected.removeAll()
        var names: [String] = []
        for i in 0 ..< MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            let name = Self.displayName(src)
            guard name.localizedCaseInsensitiveContains(match) else { continue }
            MIDIPortConnectSource(port, src, nil)
            connected.append(src)
            names.append(name)
        }
        onConnection?(names.first)
    }

    fileprivate func receive(_ status: UInt8, _ d1: Int, _ d2: Int) { onMessage?(status, d1, d2) }

    nonisolated private static func displayName(_ obj: MIDIObjectRef) -> String {
        var n: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &n)
        return (n?.takeRetainedValue() as String?) ?? ""
    }

    // CoreMIDI ruft auf eigenen Threads zurück → bewusst außerhalb des MainActors,
    // weitergereicht per DispatchQueue.main.
    nonisolated private static func makeClient(_ bridge: MIDIBridge) -> MIDIClientRef {
        var c = MIDIClientRef()
        MIDIClientCreateWithBlock("Stellwerk" as CFString, &c) { note in
            guard note.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { bridge.owner?.rescan() } }
        }
        return c
    }

    nonisolated private static func makePort(_ client: MIDIClientRef, _ bridge: MIDIBridge) -> MIDIPortRef {
        var p = MIDIPortRef()
        MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &p) { list, _ in
            for packet in list.unsafeSequence() {
                for word in packet.words() where word >> 28 == 0x2 {   // MIDI-1.0-Kanalnachricht
                    let status = UInt8((word >> 16) & 0xFF), d1 = Int((word >> 8) & 0x7F), d2 = Int(word & 0x7F)
                    DispatchQueue.main.async { MainActor.assumeIsolated { bridge.owner?.receive(status, d1, d2) } }
                }
            }
        }
        return p
    }
}

/// Schwache Rückverbindung, die CoreMIDI-Threads sicher mitnehmen dürfen
private final class MIDIBridge: @unchecked Sendable {
    weak var owner: MIDIInput?
    init(owner: MIDIInput) { self.owner = owner }
}
