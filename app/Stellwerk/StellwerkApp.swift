import SwiftUI

@main
struct StellwerkApp: App {
    @State private var engine = Engine()

    var body: some Scene {
        MenuBarExtra {
            StatusView(engine: engine)
        } label: {
            Image(nsImage: Self.menuBarIcon(connected: engine.hubState.isConnected))
        }
        .menuBarExtraStyle(.window)

        Window(SettingsView.windowTitle, id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)   // nicht beim Start öffnen
    }

    /// Weiche (⌥) als Template-Symbol; getrennt = gedimmt. `option` hat keine
    /// `.fill`-Variante, und `.opacity` wirkt im Menüleisten-Label nicht zuverlässig,
    /// deshalb wird die Deckkraft direkt ins Bild gezeichnet.
    private static func menuBarIcon(connected: Bool) -> NSImage {
        guard let symbol = NSImage(systemSymbolName: "option", accessibilityDescription: "Stellwerk")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) else { return NSImage() }
        guard !connected else {
            symbol.isTemplate = true
            return symbol
        }
        let dimmed = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        dimmed.isTemplate = true
        return dimmed
    }
}

extension TangentHub.State {
    var isConnected: Bool { if case .connected = self { return true } else { return false } }
}
