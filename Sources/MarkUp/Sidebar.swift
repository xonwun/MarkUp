import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Sidebar drags stay inside MarkUp, so Finder and the editor never receive a file or path.
    static let sidebarFile = UTType(exportedAs: "local.markup.sidebar-file", conformingTo: .data)
}

// Disambiguate the property wrapper from the SDK’s State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// An insertion point between rows: `index` counts rows in the Pinned or Recents section.
struct SidebarDropSlot: Equatable {
    let pinned: Bool
    let index: Int
}

struct Heading: Identifiable, Equatable {
    let line: Int
    let level: Int
    let title: String
    var id: Int { line }
}

struct EditorSidebar: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var files: RecentFiles
    @ViewState private var dragging: URL?
    @ViewState private var dropSlot: SidebarDropSlot?
    var body: some View {
        // No background: the sidebar sits directly on the window glass.
        VStack(spacing: 0) {
            // The traffic lights' row, level with the card's toolbar.
            WindowDragArea().frame(height: InterfaceMetrics.windowInset + InterfaceMetrics.toolbarHeight)
            HStack(spacing: 2) {
                tab("files", symbol: "doc.on.doc", title: document.tr("Files", "文件"))
                tab("outline", symbol: "list.bullet.indent", title: document.tr("Outline", "大纲"))
                    .onboardingHint(.outline, document: document)
            }.segmentTrack().padding(.horizontal, 8).padding(.bottom, 4)
            if document.sidebarTab == "files" { fileContent } else { outlineContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func tab(_ id: String, symbol: String, title: String) -> some View {
        let selected = document.sidebarTab == id
        return Button { document.sidebarTab = id } label: {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(SidebarButtonStyle(selected: selected, shape: .insetControl))
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var fileContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                sectionTitle(document.tr("Pinned", "已固定"), symbol: "pin").fileDrop(SidebarDropSlot(pinned: true, index: 0), sidebar: self)
                if files.pinned.isEmpty {
                    Text(document.tr("Drag a file here, or right-click it, to pin it.", "将文件拖到这里，或右键点击文件，即可固定。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle.control.fill(Color.interfaceAccent.opacity(dropSlot == SidebarDropSlot(pinned: true, index: 0) ? 0.14 : 0)))
                        .padding(.bottom, 4)
                        .fileDrop(SidebarDropSlot(pinned: true, index: 0), sidebar: self)
                } else {
                    rows(files.pinned, pinned: true)
                }
                Divider().padding(.vertical, 10)
                sectionTitle(document.tr("Recents", "最近使用"), symbol: "clock").fileDrop(SidebarDropSlot(pinned: false, index: 0), sidebar: self)
                if files.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(document.tr("Open a .md file to find it here next time.", "打开 .md 文件，下次可在这里找到它。"))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(document.tr("Open File…", "打开文件…")) { document.open() }
                            .controlSize(.large).disabled(document.busy || !document.ready)
                    }.padding(.horizontal, 8).padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle.control.fill(Color.interfaceAccent.opacity(dropSlot == SidebarDropSlot(pinned: false, index: 0) ? 0.14 : 0)))
                        .fileDrop(SidebarDropSlot(pinned: false, index: 0), sidebar: self)
                } else {
                    rows(files.recent, pinned: false)
                }
            }.padding(8)
        }
    }
    private func rows(_ urls: [URL], pinned: Bool) -> some View {
        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
            SidebarFileButton(url: url, document: document, files: files)
                .overlay(alignment: .top) { insertionMark(dropSlot == SidebarDropSlot(pinned: pinned, index: index), edge: .top) }
                .overlay(alignment: .bottom) { insertionMark(index == urls.count - 1 && dropSlot == SidebarDropSlot(pinned: pinned, index: index + 1), edge: .bottom) }
                .onDrag {
                    dragging = url
                    setDropSlot(nil)
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.sidebarFile.identifier, visibility: .ownProcess) { completion in
                        completion(Data(url.path.utf8), nil)
                        return nil
                    }
                    return provider
                }
                .fileDrop(SidebarDropSlot(pinned: pinned, index: index), splitsRow: true, sidebar: self)
        }
    }
    private func insertionMark(_ visible: Bool, edge: VerticalEdge) -> some View {
        Capsule().fill(Color.interfaceAccent).frame(height: 2).padding(.horizontal, 6)
            .offset(y: edge == .top ? -2 : 2)
            .opacity(visible ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
    }
    fileprivate func setDropSlot(_ slot: SidebarDropSlot?) {
        guard slot != dropSlot else { return }
        withAnimation(.easeOut(duration: 0.12)) { dropSlot = slot }
    }
    fileprivate func clearDropSlot(ifIn slots: [SidebarDropSlot]) {
        if let dropSlot, slots.contains(dropSlot) { setDropSlot(nil) }
    }
    fileprivate func drop(at slot: SidebarDropSlot) -> Bool {
        defer { dragging = nil; setDropSlot(nil) }
        guard let dragging else { return false }
        files.move(dragging, toPinned: slot.pinned, at: slot.index)
        return true
    }
    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
    private var outlineContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(document.headings.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption).frame(minWidth: 24, alignment: .trailing)
            }.frame(height: 32).padding(.horizontal, 16)
            if document.headings.isEmpty {
                sidebarMessage("list.bullet.indent", title: document.tr("No headings yet", "暂无标题"), detail: document.tr("Add a heading with # to navigate your document.", "使用 # 添加标题，即可在这里跳转章节。"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(document.headings) { heading in
                                Button { document.goToHeading(heading) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Text("H\(heading.level)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(heading.title.isEmpty ? document.tr("Untitled heading", "未命名标题") : heading.title)
                                            .font(.system(size: 12, weight: heading.level == 1 ? .medium : .regular)).lineLimit(2)
                                        Spacer(minLength: 0)
                                    }.padding(.leading, CGFloat(heading.level - 1) * 10).padding(.horizontal, 8).padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(SidebarButtonStyle(selected: document.activeHeading == heading.line)).id(heading.line).disabled(document.busy || !document.ready)
                                    .help(document.tr("Line \(heading.line)", "第 \(heading.line) 行"))
                                    .accessibilityLabel("H\(heading.level) \(heading.title.isEmpty ? document.tr("Untitled heading", "未命名标题") : heading.title)")
                                    .accessibilityAddTraits(document.activeHeading == heading.line ? .isSelected : [])
                            }
                        }.padding(8)
                    }.onChange(of: document.activeHeading) { _, line in
                        if let line { proxy.scrollTo(line) }
                    }
                }
            }
        }
    }
    private func sidebarMessage(_ symbol: String, title: String, detail: String, actionTitle: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: action).controlSize(.large).padding(.top, 4)
                    .disabled(document.busy || !document.ready)
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarFileButton: View {
    let url: URL
    @ObservedObject var document: EditorDocument
    @ObservedObject var files: RecentFiles
    private var selected: Bool { document.fileURL == url }
    private var parentPath: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        Button { document.openURL(url) } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Text(parentPath).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Circle().frame(width: 5, height: 5)
                    .opacity(selected && document.dirty ? 1 : 0).accessibilityHidden(true)
            }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(SidebarButtonStyle(selected: selected))
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected && document.dirty ? document.tr("Unsaved", "未保存") : "")
        .help(url.path)
        .contextMenu {
            Button(document.tr("Open", "打开")) { document.openURL(url) }
                .disabled(document.busy || !document.ready)
            Button(document.tr("Show in Finder", "在 Finder 中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button(document.tr("Remove from Recents", "从最近使用中移除")) { files.remove(url) }
            Button(files.isPinned(url) ? document.tr("Unpin this File", "取消固定此文件") : document.tr("Pin this File", "固定此文件")) {
                files.togglePin(url)
            }
        }
    }
}

private struct FileDropDelegate: DropDelegate {
    let slot: SidebarDropSlot
    let splitsRow: Bool
    let height: CGFloat
    let sidebar: EditorSidebar
    private func target(_ info: DropInfo) -> SidebarDropSlot {
        // Over a row, the lower half inserts after it.
        splitsRow && info.location.y > height / 2 ? SidebarDropSlot(pinned: slot.pinned, index: slot.index + 1) : slot
    }
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.sidebarFile]) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        sidebar.setDropSlot(target(info))
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        sidebar.clearDropSlot(ifIn: [slot, SidebarDropSlot(pinned: slot.pinned, index: slot.index + 1)])
    }
    func performDrop(info: DropInfo) -> Bool { sidebar.drop(at: target(info)) }
}

private struct FileDropModifier: ViewModifier {
    let slot: SidebarDropSlot
    let splitsRow: Bool
    let sidebar: EditorSidebar
    @ViewState private var height: CGFloat = 40
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.sidebarFile], delegate: FileDropDelegate(slot: slot, splitsRow: splitsRow, height: height, sidebar: sidebar))
    }
}

private extension View {
    func fileDrop(_ slot: SidebarDropSlot, splitsRow: Bool = false, sidebar: EditorSidebar) -> some View {
        modifier(FileDropModifier(slot: slot, splitsRow: splitsRow, sidebar: sidebar))
    }
}

/// The sidebar's trailing edge, where the card begins: drag to resize, double-click to restore the default width.
struct SidebarResizeHandle: View {
    @ObservedObject var document: EditorDocument
    @ViewState private var startWidth: CGFloat?
    @ViewState private var cursorPushed = false
    var body: some View {
        Color.clear.frame(width: 0)
            .overlay(alignment: .trailing) {
                // Most of the hit area sits over the sidebar's inset so the editor keeps its clicks.
                Color.clear.frame(width: 8).contentShape(Rectangle()).offset(x: 2)
                    .onHover { updateCursor(hovering: $0) }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = startWidth ?? document.sidebarWidth
                            startWidth = start
                            document.resizeSidebar(to: start + value.translation.width)
                        }
                        .onEnded { _ in
                            startWidth = nil
                            document.resizeSidebar(to: document.sidebarWidth, persist: true)
                            updateCursor(hovering: false)
                        })
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        document.resizeSidebar(to: EditorDocument.defaultSidebarWidth, persist: true)
                    })
                    .accessibilityHidden(true)
            }
            .zIndex(1)
    }
    private func updateCursor(hovering: Bool) {
        let wanted = hovering || startWidth != nil
        if wanted && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
        if !wanted && cursorPushed { NSCursor.pop(); cursorPushed = false }
    }
}
