// Kurze Einblendung beim Moduswechsel: schwebt über allem, fängt keine Klicks ab,
// nimmt der aktiven App nicht den Fokus.
import AppKit
import SwiftUI

final class HUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, symbol: String) {
        // Größe einmal messen und fest setzen. Die Ansicht darf die Fenstergröße nicht selbst steuern,
        // sonst schaukeln sich Fenster und SwiftUI-Layout auf (Absturz „Update Constraints in Window").
        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol))
        host.sizingOptions = []
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        let p = panel ?? makePanel()
        panel = p

        // Bildschirm, auf dem der Mauszeiger ist; unteres Drittel, mittig
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        p.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.18,
                          width: size.width, height: size.height), display: false)
        p.contentView = host
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    self?.panel?.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { if self?.panel?.alphaValue == 0 { self?.panel?.orderOut(nil) } }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }
}

private struct HUDView: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.lime)
            Text(text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)   // Platz für den Schatten
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}
