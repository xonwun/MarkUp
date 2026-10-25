import SwiftUI

enum InterfaceMetrics {
    /// The single corner radius for custom controls and editor blocks, always drawn continuous.
    static let controlCornerRadius: CGFloat = 8
    /// Inset controls subtract their padding so nested corners stay concentric.
    static let insetCornerRadius: CGFloat = 6
}

extension Shape where Self == RoundedRectangle {
    static var control: RoundedRectangle { RoundedRectangle(cornerRadius: InterfaceMetrics.controlCornerRadius, style: .continuous) }
    static var insetControl: RoundedRectangle { RoundedRectangle(cornerRadius: InterfaceMetrics.insetCornerRadius, style: .continuous) }
}

extension View {
    /// The track behind segmented choices: the sidebar's Files/Outline tabs and the Compact/Reading switch.
    /// Segments inside it use `SidebarButtonStyle(shape: .insetControl)`.
    func segmentTrack() -> some View {
        padding(2).background(RoundedRectangle.control.fill(Color.primary.opacity(0.05)))
    }
}

struct SidebarButtonStyle: ButtonStyle {
    var selected = false
    var shape: RoundedRectangle = .control

    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonSurface(configuration: configuration, selected: selected, shape: shape)
    }
}

// Disambiguate the property wrapper from the SDK’s State macro.
private typealias HoverState = SwiftUI.State<Bool>

private struct SidebarButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let shape: RoundedRectangle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @HoverState private var hovered = false

    var body: some View {
        configuration.label
            .contentShape(shape)
            .background {
                shape.fill(selected ? Color.interfaceAccent.opacity(0.14) : Color.primary.opacity(isEnabled && (hovered || configuration.isPressed) ? 0.06 : 0))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}
