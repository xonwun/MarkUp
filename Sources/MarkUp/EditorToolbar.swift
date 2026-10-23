import SwiftUI

/// The toolbar's two clusters. They sit on borderless toolbar items, so macOS draws no glass container,
/// and use the sidebar's own button and segment styles.
struct ToolbarCluster: View {
    enum Placement { case navigation, actions }
    @ObservedObject var document: EditorDocument
    let placement: Placement
    var body: some View {
        HStack(spacing: 2) {
            switch placement {
            case .navigation:
                icon("sidebar.left", document.tr("Toggle Sidebar", "切换侧边栏"), "⌃⌘S", on: document.showSidebar) { document.toggleSidebar() }
                icon("folder", document.tr("Open", "打开"), "⌘O") { document.open() }
            case .actions:
                HStack(spacing: 2) {
                    layoutTab(.compact, symbol: "text.justify.left", title: document.tr("Compact", "紧凑"))
                    layoutTab(.reading, symbol: "book", title: document.tr("Reading", "阅读"))
                }
                .segmentTrack()
                .disabled(document.busy || !document.ready)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(document.tr("Editor layout", "编辑布局"))
                .padding(.trailing, 6)
                icon("magnifyingglass", document.tr("Find", "查找"), "⌘F", on: document.showFind) { document.toggleFind() }
                icon("chevron.left.forwardslash.chevron.right", document.tr("Toggle Source", "切换源码"), "⇧⌘M", on: document.sourceMode) { document.toggleMode() }
                icon("square.and.arrow.down", document.tr("Save", "保存"), "⌘S") { document.save() }
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
    private func layoutTab(_ layout: EditorLayout, symbol: String, title: String) -> some View {
        let selected = document.layout == layout
        return Button { document.setLayout(layout) } label: {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 30, height: 22)
        }
        .buttonStyle(SidebarButtonStyle(selected: selected, shape: .insetControl))
        .help(document.tr("\(title) layout", "\(title)布局"))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
