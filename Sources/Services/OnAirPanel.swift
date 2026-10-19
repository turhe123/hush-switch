import AppKit
import SwiftUI

/// Screen corner where the on-air pill is placed.
enum ScreenCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// Shows a small click-through "ON AIR" pill in a borderless status-level panel while the mic is live.
final class OnAirPanel {
    private var panel: NSPanel?
    private let size = NSSize(width: 104, height: 30)

    func show(at corner: ScreenCorner) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 16
        let x = corner == .topLeft || corner == .bottomLeft ? screen.minX + margin : screen.maxX - size.width - margin
        let y = corner == .bottomLeft || corner == .bottomRight ? screen.minY + margin : screen.maxY - size.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OnAirPill())
        return panel
    }
}

/// The red pill rendered inside the on-air panel.
private struct OnAirPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.white).frame(width: 8, height: 8)
            Text("ON AIR").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: 104, height: 30)
        .background(Capsule().fill(Color.red.gradient))
    }
}
