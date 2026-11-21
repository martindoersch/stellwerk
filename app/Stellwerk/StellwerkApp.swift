import SwiftUI

@main
struct StellwerkApp: App {
    @State private var engine = Engine()

    var body: some Scene {
        MenuBarExtra {
            StatusView(engine: engine)
        } label: {
            Image(systemName: engine.hubState.isConnected ? "dial.medium.fill" : "dial.medium")
        }
        .menuBarExtraStyle(.window)

        Window("Stellwerk – Einstellungen", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)   // nicht beim Start öffnen
    }
}

extension TangentHub.State {
    var isConnected: Bool { if case .connected = self { return true } else { return false } }
}
