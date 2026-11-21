// Ausgabe-Adapter Capture One: Stellwerk spielt den Tangent Hub auf 127.0.0.1:64246.
// Capture One verbindet sich nur beim Start → Stellwerk muss vor Capture One laufen.
import Foundation
import Network

private struct Writer {
    var data = Data()
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
}

private extension Data {
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
    enum State: Equatable { case starting, listening, connected(String), failed(String) }

    // Hub → App
    private static let initiateComms: UInt32 = 0x01, paramChange: UInt32 = 0x02, paramReset: UInt32 = 0x03
    private static let valueRequest: UInt32 = 0x04, actionOn: UInt32 = 0x08, actionOff: UInt32 = 0x0B
    static let port: NWEndpoint.Port = 64246

    private var listener: NWListener?
    private var conn: NWConnection?
    private var pending: [UInt32: Float] = [:]     // Deltas sammeln, alle 15 ms senden
    private var flushScheduled = false

    var onState: ((State) -> Void)?
    var onValue: ((UInt32, Float, Bool) -> Void)?   // id, Wert, Standardwert?
    var onLog: ((String) -> Void)?
    private(set) var state = State.starting { didSet { onState?(state) } }
    var isConnected: Bool { if case .connected = state { return true } else { return false } }

    func start() {
        let params = NWParameters.tcp
        // Fest an 127.0.0.1 binden: nur lokal erreichbar, nicht im WLAN
        // (requiredInterfaceType = .loopback allein lauschte trotzdem auf *:64246)
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 64246)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else {
            state = .failed("Port 64246 nicht verfügbar"); return
        }
        // Alle Handler laufen auf der Main-Queue → MainActor
        l.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                switch st {
                case .ready: self?.state = .listening
                case .failed(let e): self?.state = .failed("Port 64246 belegt? (\(e.localizedDescription))")
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] c in MainActor.assumeIsolated { self?.accept(c) } }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        conn?.cancel(); listener?.cancel()
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch st {
                case .failed, .cancelled:
                    if self.conn === c { self.conn = nil; self.state = .listening; self.onLog?("Capture One getrennt") }
                default: break
                }
            }
        }
        c.start(queue: .main)
        var w = Writer()
        w.u32(Self.initiateComms); w.u32(5); w.u32(0)   // Protokoll-Rev. 5, keine Panels
        send(w.data)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] head, _, _, err in
            MainActor.assumeIsolated {
                guard let self, let head, head.count == 4, err == nil, let n = head.u32(0) else { return }
                if n == 0 { self.receive(c); return }
                c.receive(minimumIncompleteLength: Int(n), maximumLength: Int(n)) { body, _, _, err in
                    MainActor.assumeIsolated {
                        guard let body, body.count == Int(n), err == nil else { return }
                        self.handle(body)
                        self.receive(c)
                    }
                }
            }
        }
    }

    private func handle(_ body: Data) {
        guard let cmd = body.u32(0) else { return }
        switch cmd {
        case 0x81:   // ApplicationDefinition
            state = .connected(body.string(4)?.0 ?? "Capture One")
        case 0x82:   // ParameterValue: id, float, bool atDefault
            guard let id = body.u32(4), let bits = body.u32(8) else { return }
            onValue?(id, Float(bitPattern: bits), body.u32(12) == 1)
        case 0x85, 0x86:   // ModeValue, DisplayText: derzeit nicht genutzt
            break
        default:
            onLog?("Tangent: unbekannter Befehl \(hexStr(cmd))")
        }
    }

    private func send(_ body: Data) {
        guard let conn else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flushScheduled = false
                for (id, d) in self.pending where d != 0 { self.cmd(Self.paramChange, id, d) }
                self.pending.removeAll()
            }
        }
    }
    func reset(_ id: UInt32) { cmd(Self.paramReset, id) }
    func request(_ id: UInt32) { cmd(Self.valueRequest, id) }
    func action(_ id: UInt32) { cmd(Self.actionOn, id); cmd(Self.actionOff, id) }
}
