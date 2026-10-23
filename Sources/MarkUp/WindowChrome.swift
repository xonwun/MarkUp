import SwiftUI

extension InterfaceMetrics {
    /// Glass visible around the main card, and the card's distance from the window edges.
    static let windowInset: CGFloat = 6
    /// The system window corner: 16pt from macOS 26, 10pt before.
    static let windowCornerRadius: CGFloat = {
        if #available(macOS 26, *) { return 16 }
        return 10
    }()
    /// Concentric with the window corner (outer minus inset), so the glass margin stays even around it.
    static let cardCornerRadius = max(windowCornerRadius - windowInset, 6)
    /// The toolbar row at the top of the card; the traffic lights center on it.
    static let toolbarHeight: CGFloat = 40
}

extension Animation {
    /// Interface motion, dropped when Reduce Motion is on so the change applies at once.
    static func interface(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }
    /// The sidebar opening or closing: content already on screen moves, so it eases in and out.
    static let sidebar = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.25)
}

extension Shape where Self == RoundedRectangle {
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: InterfaceMetrics.cardCornerRadius, style: .continuous) }
}

extension Color {
    /// Matches the editor's `--paper`, so the toolbar and status rows read as one surface with the page.
    /// sRGB of `oklch(0.991 0.004 90)` and `oklch(0.25 0.003 90)`.
    static let paper = Color(nsColor: NSColor(name: "paper") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x22 / 255, green: 0x22 / 255, blue: 0x20 / 255, alpha: 1)
            : NSColor(srgbRed: 0xfd / 255, green: 0xfc / 255, blue: 0xf9 / 255, alpha: 1)
    })
}

extension View {
    /// The main card's surface: held above the glass rather than set into it.
    func floatingCard() -> some View { modifier(FloatingCard()) }
}

private struct FloatingCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .clipShape(.card)
            .background {
                RoundedRectangle.card.fill(Color.paper)
                    // Lift: wide and soft, dropped below the card so it reads as hovering over the glass.
                    .shadow(color: .black.opacity(dark ? 0.20 : 0.08), radius: 8, y: 4)
                    // Contact: tight and crisp, anchoring the edge.
                    .shadow(color: .black.opacity(dark ? 0.24 : 0.05), radius: 1, y: 1)
            }
            .overlay {
                // A ring in place of a border. Light: a faint dark line just outside the edge. Dark: shadows barely
                // show, so the edge is a light rim just inside, brighter at the top where light would catch it.
                if dark {
                    RoundedRectangle.card.strokeBorder(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .allowsHitTesting(false)
                } else {
                    RoundedRectangle.card.inset(by: -1).strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// A full-size-content window whose title bar is transparent, with the traffic lights moved down to center
/// on the card's toolbar row. The transparent title bar passes clicks through to the toolbar beneath it.
final class GlassWindow: NSWindow {
    /// The close button sits as far from the left edge as its center is from the top.
    static let trafficLightCenter = InterfaceMetrics.windowInset + InterfaceMetrics.toolbarHeight / 2
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        placeTrafficLights()
    }
    /// The right edge of the zoom button, in window coordinates.
    var trafficLightsMaxX: CGFloat {
        guard let zoom = standardWindowButton(.zoomButton) else { return 0 }
        return zoom.convert(zoom.bounds, to: nil).maxX
    }
    private func placeTrafficLights() {
        guard !styleMask.contains(.fullScreen),
              let close = standardWindowButton(.closeButton), let titlebar = close.superview,
              let container = titlebar.superview else { return }
        let height = Self.trafficLightCenter * 2
        if container.frame.height != height {
            container.frame = NSRect(x: container.frame.minX, y: frame.height - height, width: container.frame.width, height: height)
        }
        let shift = Self.trafficLightCenter - close.frame.width / 2 - close.frame.minX
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(kind) else { continue }
            let origin = NSPoint(x: button.frame.minX + shift, y: ((titlebar.bounds.height - button.frame.height) / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

extension NSWindow {
    /// Clicks on custom title areas: drag the window, and on double-click follow the system title-bar setting.
    func titleAreaMouseDown(_ event: NSEvent, zooms: Bool) {
        guard zooms, event.clickCount == 2 else { performDrag(with: event); return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": performMiniaturize(nil)
        case "None": break
        default: performZoom(nil)
        }
    }
}

/// The window background: a glass layer the sidebar sits on and the card floats over. Dragging it moves the window.
struct WindowGlass: NSViewRepresentable {
    final class GlassView: NSVisualEffectView {
        override func mouseDown(with event: NSEvent) { window?.titleAreaMouseDown(event, zooms: false) }
    }
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Behaves like a title bar: drags the window and zooms on double-click.
struct WindowDragArea: NSViewRepresentable {
    var toolTip: String?
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.titleAreaMouseDown(event, zooms: true) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.toolTip = toolTip }
}
