import SwiftUI
import UniformTypeIdentifiers

// Disambiguate the property wrapper from the SDK’s State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// What an empty window shows instead of a blank page: one way in, then the files the user already knows.
/// Never shown over the welcome screen; that path opens the Welcome guide.
struct StartPage: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var files: RecentFiles
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var targeted = false
    private static let recentLimit = 8
    private static let openableExtensions: Set<String> = ["md", "markdown"]

    /// Files moved or deleted since they were listed stay in the sidebar, but a start page should only offer what opens.
    private func existing(_ urls: [URL]) -> [URL] { urls.filter { FileManager.default.fileExists(atPath: $0.path) } }

    var body: some View {
        // The sidebar already lists these files; showing them twice side by side is noise.
        let lists = !document.showSidebar
        let pinned = lists ? existing(files.pinned) : []
        let recent = lists ? Array(existing(files.recent).prefix(Self.recentLimit)) : []
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    dropZone
                    if !pinned.isEmpty { section(document.tr("Pinned", "已固定"), symbol: "pin", urls: pinned) }
                    if !recent.isEmpty { section(document.tr("Recents", "最近使用"), symbol: "clock", urls: recent) }
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 32).padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .animation(.interface(.sidebar), value: lists)
            }
        }
        .background(Color.paper)
        // The whole page takes the drop, so a file let go near the zone still opens.
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, Self.openableExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in document.openURL(url) }
            }
            return true
        }
        // Keys must not reach the editor hidden underneath.
        .onAppear { document.window?.makeFirstResponder(nil) }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(document.tr("Drop a Markdown file here", "将 Markdown 文件拖到这里"))
                    .font(.system(size: 15, weight: .semibold))
                Text(document.tr("or open one from your Mac", "或从你的 Mac 中打开"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { document.open() } label: { Text(document.tr("Open File…", "打开文件…")).padding(.horizontal, 4) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button { document.newFile() } label: { Text(document.tr("New Document", "新建文稿")).padding(.horizontal, 4) }
            }
            .controlSize(.large)
            .disabled(document.busy || !document.ready)
        }
        .padding(.vertical, 40).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(targeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [5, 4]))
        )
        .scaleEffect(targeted && !reduceMotion ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: targeted)
    }

    private func section(_ title: String, symbol: String, urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(urls, id: \.self) { url in
                SidebarFileButton(url: url, document: document, files: files)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
