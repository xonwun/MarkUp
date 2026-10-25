import SwiftUI

// Disambiguate the property wrapper from the SDK’s State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// The row at the top of the card: no background, divider, or containers. Its empty space works as a title bar.
struct EditorToolbar: View {
    @ObservedObject var document: EditorDocument
    @ViewState private var navigationWidth: CGFloat = 0
    @ViewState private var actionsWidth: CGFloat = 0
    private static let padding: CGFloat = 6
    /// With the sidebar hidden, the traffic lights float over the card's top-left corner.
    private var leadingInset: CGFloat {
        document.showSidebar ? 0 : max(0, document.trafficLightsMaxX + 8 - InterfaceMetrics.windowInset - Self.padding)
    }
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ToolbarCluster(document: document, placement: .navigation)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { navigationWidth = $0 }
                Spacer(minLength: 0)
                // The editing controls have nothing to act on until a document is open.
                ToolbarCluster(document: document, placement: .actions)
                    .opacity(document.showStart ? 0 : 1).allowsHitTesting(!document.showStart)
                    .accessibilityHidden(document.showStart)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
            }
            .padding(.leading, leadingInset)
            // Centered on the card, clear of whichever cluster is wider.
            Text(document.showStart ? "" : document.title).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 260)
                .overlay(WindowDragArea(toolTip: document.fileURL?.path ?? document.title))
                .padding(.horizontal, max(navigationWidth + leadingInset, actionsWidth) + 12)
        }
        .padding(.horizontal, Self.padding)
        .frame(height: InterfaceMetrics.toolbarHeight)
        .background(WindowDragArea())
    }
}

/// The toolbar's two clusters, drawn with the sidebar's own button and segment styles.
struct ToolbarCluster: View {
    enum Placement { case navigation, actions }
    @ObservedObject var document: EditorDocument
    let placement: Placement
    var body: some View {
        HStack(spacing: 2) {
            switch placement {
            case .navigation:
                icon("sidebar.left", document.tr("Toggle Sidebar", "切换侧边栏"), "⌃⌘S", on: document.showSidebar) { document.toggleSidebar() }
                    .onboardingHint(.sidebar, document: document)
                icon("folder", document.tr("Open", "打开"), "⌘O") { document.open() }
            case .actions:
                segmented(document.tr("Editor layout", "编辑布局")) {
                    segment("text.justify.left", document.tr("Compact layout", "紧凑布局"), selected: document.layout == .compact) { document.setLayout(.compact) }
                    segment("book", document.tr("Reading layout", "阅读布局"), selected: document.layout == .reading) { document.setLayout(.reading) }
                }
                .onboardingHint(.layout, document: document)
                segmented(document.tr("Text view", "文本视图")) {
                    segment("textformat", document.tr("Formatted · ⇧⌘M", "排版 · ⇧⌘M"), selected: !document.sourceMode) { if document.sourceMode { document.toggleMode() } }
                    segment("chevron.left.forwardslash.chevron.right", document.tr("Source · ⇧⌘M", "源码 · ⇧⌘M"), selected: document.sourceMode) { if !document.sourceMode { document.toggleMode() } }
                }
                .onboardingHint(.source, document: document)
                icon("magnifyingglass", document.tr("Find", "查找"), "⌘F", on: document.showFind) { document.toggleFind() }
                    .onboardingHint(.find, document: document)
            }
        }
        .fixedSize()
    }
    /// `on` marks a toggle whose mode is active, using the same tint as a selected sidebar row.
    private func icon(_ symbol: String, _ title: String, _ shortcut: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14))
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(SidebarButtonStyle(selected: on))
        .help("\(title) · \(shortcut)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    /// A two-way switch drawn like the sidebar's Files/Outline tabs.
    private func segmented<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .segmentTrack()
            .disabled(document.busy || !document.ready)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .padding(.trailing, 6)
    }
    private func segment(_ symbol: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 30, height: 22)
        }
        .buttonStyle(SidebarButtonStyle(selected: selected, shape: .insetControl))
        .help(title)
        .accessibilityLabel(title.components(separatedBy: " · ")[0])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
