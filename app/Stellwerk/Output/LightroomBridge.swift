// Ausgabe-Adapter Lightroom Classic: verbindet sich mit dem Stellwerk-Plug-in (lightroom/Stellwerk.lrplugin).
// Lightroom-Plug-ins können nur lauschen → das Plug-in öffnet zwei Ports und schreibt sie nach
// ~/Library/Application Support/Stellwerk/lightroom-ports („Empfangsport|Sendeport|Startzeit“).
// Zeilenprotokoll siehe Kopf von Init.lua im Plug-in.
import Foundation
import Network

/// Regler und Aktionen von Lightroom mit eigenen IDs (Bereich 0x4C52xxxx, „LR“), damit Belegung und Engine
/// sie wie Capture-One-IDs behandeln. key = Name im Lightroom-SDK (Regler) bzw. Aktion des Plug-ins.
/// Die IDs gelten nur zur Laufzeit; in den Belegungsdateien stehen die keys.
enum LightroomControls {
    struct Control { let key: String; let name: String; let isParam: Bool; let step: Double }

    static let base: UInt32 = 0x4C52_0000
    static let bundleID = "com.adobe.LightroomClassicCC7"

    private static let colors = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    static let all: [Control] = {
        func p(_ key: String, _ name: String, _ step: Double = 1) -> Control { Control(key: key, name: name, isParam: true, step: step) }
        func a(_ key: String, _ name: String) -> Control { Control(key: key, name: name, isParam: false, step: 0) }
        var list = [
            p("Temperature", "Temperature"), p("Tint", "Tint"), p("Exposure2012", "Exposure", 0.05),
            p("Contrast2012", "Contrast"), p("Highlights2012", "Highlights"), p("Shadows2012", "Shadows"),
            p("Whites2012", "Whites"), p("Blacks2012", "Blacks"), p("Texture", "Texture"), p("Clarity2012", "Clarity"),
            p("Dehaze", "Dehaze"), p("Vibrance", "Vibrance"), p("Saturation", "Saturation"),
            p("PostCropVignetteAmount", "Post-Crop Vignetting"), p("straightenAngle", "Straighten", 0.1),
        ]
        for c in colors {
            list += [p("HueAdjustment" + c, "Hue " + c), p("SaturationAdjustment" + c, "Saturation " + c),
                     p("LuminanceAdjustment" + c, "Luminance " + c)]
        }
        list += [a("next", "Next Photo"), a("previous", "Previous Photo"), a("undo", "Undo"), a("redo", "Redo"),
                 a("pick", "Flag as Pick"), a("reject", "Flag as Rejected"), a("unflag", "Remove Flag"),
                 a("develop", "Develop Module"), a("library", "Library Module")]
        list += (0 ... 5).map { a("rating\($0)", "Rating \($0)") }
        list += ["red", "yellow", "green", "blue", "purple"].map { a($0, "Toggle \($0.capitalized) Label") }
        return list
    }()

    static let byID: [UInt32: Control] =
        Dictionary(uniqueKeysWithValues: all.enumerated().map { (base + UInt32($0.offset + 1), $0.element) })
    static let idByKey: [String: UInt32] = Dictionary(uniqueKeysWithValues: byID.map { ($0.value.key, $0.key) })

    static func contains(_ id: UInt32) -> Bool { id & 0xFFFF_0000 == base }
}

final class LightroomBridge {
    var onConnection: ((Bool) -> Void)?
    var onValue: ((UInt32, Float) -> Void)?
    var onLog: ((String) -> Void)?
    private(set) var isConnected = false

    /// Regler, deren Werte Stellwerk sehen will (Display, Startwerte); Lightroom meldet auch Mausänderungen
    var watched: Set<UInt32> = [] { didSet { if isConnected, watched != oldValue { sendWatch() } } }

    static let portFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Stellwerk/lightroom-ports")

    private var toLR: NWConnection?
    private var fromLR: NWConnection?
    private var connectedPorts: String?        // Inhalt der Portdatei der laufenden Verbindung
    private var buffer = Data()

    // Flusskontrolle: Lightroom braucht ~50 ms pro setValue (Bild wird neu berechnet). Pro Regler ist deshalb
    // höchstens ein Befehl unterwegs; weitere Drehschritte sammeln sich und gehen los, sobald der Wert zurückkommt.
    private var pending: [String: Double] = [:]
    private var inFlight: [String: TimeInterval] = [:]
    private var retryScheduled: Set<String> = []
    private static let replyTimeout = 0.3

    func start() { poll() }

    func stop() { disconnect(log: false) }

    // MARK: Verbinden

    /// Alle 2 s: Portdatei lesen; neue Ports (Plug-in neu gestartet) → neu verbinden
    private func poll() {
        let ports = (try? String(contentsOf: Self.portFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ports, ports != connectedPorts { connect(ports) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func connect(_ ports: String) {
        let parts = ports.split(separator: "|")
        guard parts.count >= 2, let r = UInt16(parts[0]), let s = UInt16(parts[1]),
              let commandPort = NWEndpoint.Port(rawValue: r), let replyPort = NWEndpoint.Port(rawValue: s) else { return }
        disconnect(log: false)
        connectedPorts = ports
        let to = NWConnection(host: "127.0.0.1", port: commandPort, using: .tcp)     // Lightroom empfängt Befehle
        let from = NWConnection(host: "127.0.0.1", port: replyPort, using: .tcp)     // Lightroom meldet Werte
        for c in [to, from] {
            c.stateUpdateHandler = { [weak self] st in
                MainActor.assumeIsolated {
                    switch st {
                    // .waiting = niemand lauscht (Lightroom zu, alte Portdatei) → beim nächsten Lesen erneut versuchen
                    case .failed, .waiting: if self?.toLR === to { self?.disconnect(log: true); self?.connectedPorts = nil }
                    case .cancelled: break
                    default: break
                    }
                }
            }
            c.start(queue: .main)
        }
        toLR = to
        fromLR = from
        receive(from)
    }

    private func disconnect(log: Bool) {
        let was = isConnected
        toLR?.cancel(); fromLR?.cancel()
        toLR = nil; fromLR = nil
        isConnected = false
        buffer.removeAll(); pending.removeAll(); inFlight.removeAll()
        if was {
            if log { onLog?(String(localized: "Lightroom getrennt")) }
            onConnection?(false)
        }
    }

    // MARK: Empfangen

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            MainActor.assumeIsolated {
                guard let self, c === self.fromLR else { return }
                if let data { self.buffer.append(data); self.lines() }
                if done || err != nil { self.disconnect(log: true); self.connectedPorts = nil; return }
                self.receive(c)
            }
        }
    }

    private func lines() {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex ..< nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex ... nl)
            handle(line)
        }
    }

    private func handle(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        switch parts.first {
        case "hello":
            isConnected = true
            onLog?(String(localized: "Lightroom verbunden"))
            onConnection?(true)
            sendWatch()
        case "value" where parts.count == 3:
            let key = parts[1]
            inFlight[key] = nil
            if let id = LightroomControls.idByKey[key], let v = Float(parts[2]) { onValue?(id, v) }
            flush(key)
        case "error":
            onLog?("Lightroom: " + (parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""))
        default:
            break   // module, photo, pong: derzeit nicht gebraucht
        }
    }

    // MARK: Senden

    private func send(_ line: String) {
        guard isConnected, let toLR else { return }
        toLR.send(content: Data((line + "\n").utf8), completion: .contentProcessed { _ in })
    }

    private func sendWatch() {
        let keys = watched.compactMap { LightroomControls.byID[$0]?.key }.sorted()
        if !keys.isEmpty { send("watch " + keys.joined(separator: ",")) }
    }

    func change(_ id: UInt32, by delta: Double) {
        guard isConnected, let key = LightroomControls.byID[id]?.key else { return }
        pending[key, default: 0] += delta
        flush(key)
    }

    /// Gesammelte Schritte eines Reglers senden – nur wenn kein Befehl mehr unterwegs ist (oder die Antwort ausbleibt)
    private func flush(_ key: String) {
        guard let d = pending[key], d != 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let sent = inFlight[key], now - sent < Self.replyTimeout {
            // Antwort fehlt noch; spätestens nach dem Timeout erneut versuchen (nur einmal eingeplant)
            guard !retryScheduled.contains(key) else { return }
            retryScheduled.insert(key)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.replyTimeout - (now - sent)) { [weak self] in
                MainActor.assumeIsolated { self?.retryScheduled.remove(key); self?.flush(key) }
            }
            return
        }
        pending[key] = nil
        inFlight[key] = now
        send("change \(key) \(d)")
    }

    func reset(_ id: UInt32) {
        guard let key = LightroomControls.byID[id]?.key else { return }
        pending[key] = nil
        send("reset " + key)
    }

    func request(_ id: UInt32) {
        if let key = LightroomControls.byID[id]?.key { send("get " + key) }
    }

    func action(_ id: UInt32) {
        if let key = LightroomControls.byID[id]?.key { send("do " + key) }
    }
}
