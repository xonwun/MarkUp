import SwiftUI
import Combine
import WebKit
import UniformTypeIdentifiers

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    var id: String { rawValue }
    var name: String { self == .english ? "English" : "简体中文" }
    static var saved: Self { Self(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") ?? .english }
}

enum EditorLayout: String, CaseIterable, Identifiable {
    case compact, reading
    var id: String { rawValue }
    static var saved: Self { Self(rawValue: UserDefaults.standard.string(forKey: "editorLayout") ?? "compact") ?? .compact }
}

@main
struct MarkUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var document = EditorDocument.shared
    init() {
        UserDefaults.standard.set([InterfaceLanguage.saved.rawValue], forKey: "AppleLanguages")
        // Controls, focus rings, and text selection outside the editor stay graphite whatever accent the system
        // uses; the editor keeps its own teal. The argument domain is in memory only, so nothing is written.
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleAccentColor"] = -1
        arguments["AppleHighlightColor"] = "0.847059 0.847059 0.862745 Graphite"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
    var body: some Scene {
        Settings {
            Form {
                Picker(document.tr("Interface language", "界面语言"), selection: $document.language) {
                    ForEach(InterfaceLanguage.allCases) { language in Text(language.name).tag(language) }
                }
                Text(document.tr("System menus and dialogs update after restarting MarkUp.md.", "系统菜单和对话框将在重新启动 MarkUp.md 后更新。"))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(document.tr("Save changes automatically", "自动保存更改"), isOn: $document.autoSave)
                Text(document.tr("Files you’ve saved once keep saving as you write. New documents still ask where to go.", "保存过的文件会在你写作时自动保存。新文稿仍需选择保存位置。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 400)
                .tint(.interfaceAccent)
                .environment(\.locale, Locale(identifier: document.language.rawValue))
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(document.tr("New", "新建")) { document.newFile() }.keyboardShortcut("n")
                Button(document.tr("Open…", "打开…")) { document.open() }.keyboardShortcut("o")
            }
            // With no SwiftUI window scene, the File menu has no Close item unless it is added here.
            CommandGroup(after: .newItem) {
                Divider()
                Button(document.tr("Close", "关闭")) { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .saveItem) {
                Button(document.tr("Save", "保存")) { document.save() }.keyboardShortcut("s")
                Button(document.tr("Save As…", "另存为…")) { document.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button(document.tr("Undo", "撤销")) { document.command("undo") }.keyboardShortcut("z")
                Button(document.tr("Redo", "重做")) { document.command("redo") }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button(document.tr("Find…", "查找…")) { document.toggleFind() }.keyboardShortcut("f")
                Button(document.tr("Find Next", "查找下一个")) { document.findAgain() }.keyboardShortcut("g")
                Button(document.tr("Find Previous", "查找上一个")) { document.findAgain(backward: true) }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button(document.tr("Bold", "加粗")) { document.command("bold") }.keyboardShortcut("b")
                Button(document.tr("Italic", "斜体")) { document.command("italic") }.keyboardShortcut("i")
            }
            CommandMenu(document.tr("Language", "语言")) {
                Picker(document.tr("Interface language", "界面语言"), selection: $document.language) {
                    ForEach(InterfaceLanguage.allCases) { language in Text(language.name).tag(language) }
                }
            }
            CommandGroup(after: .toolbar) {
                Button(document.showSidebar ? document.tr("Hide Sidebar", "隐藏侧边栏") : document.tr("Show Sidebar", "显示侧边栏")) { document.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button(document.sourceMode ? document.tr("Show Formatted Text", "显示排版") : document.tr("Show Source", "显示源码")) { document.toggleMode() }.keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let document = EditorDocument.shared
    private var editorController: EditorWindowController?
    func showEditor() {
        if editorController == nil { editorController = EditorWindowController(document: document) }
        editorController?.showWindow(nil)
        document.presentEditorWindow()
    }
    func applicationDidFinishLaunching(_ notification: Notification) { showEditor() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return false
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Receive document events even before any SwiftUI view has appeared.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openDocuments(_:reply:)), forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }
    @objc private func openDocuments(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let files = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)), files.numberOfItems > 0,
              let url = files.atIndex(1)?.fileURLValue else { return }
        receive(url) { _ in }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !document.closeApproved else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await document.confirmDiscard()) }
        return .terminateLater
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else { sender.reply(toOpenOrPrint: .failure); return }
        receive(URL(fileURLWithPath: path)) { sender.reply(toOpenOrPrint: $0) }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { receive(url) { _ in } }
    }
    private func receive(_ url: URL, completion: @escaping (NSApplication.DelegateReply) -> Void) {
        showEditor()
        document.openURL(url, completion: completion)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class EditorWindowController: NSWindowController {
    let editorDocument: EditorDocument
    init(document: EditorDocument) {
        self.editorDocument = document
        // No toolbar: the title bar is transparent and the toolbar row lives at the top of the card.
        let window = GlassWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: document.minimumWindowWidth, height: InterfaceMetrics.windowMinHeight)
        super.init(window: window)
        document.attachWindow(window)
        let content = NSHostingController(rootView: EditorWindow(document: document))
        content.sizingOptions = []
        window.contentViewController = content
        // Set after the content controller, which resizes the window. The saved frame wins; the first launch
        // opens full height and half the screen's width, centered.
        if !window.setFrameUsingName("MarkUpEditor") {
            if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                let width = min(max((screen.width / 2).rounded(), window.contentMinSize.width), screen.width)
                window.setFrame(NSRect(x: (screen.midX - width / 2).rounded(), y: screen.minY, width: width, height: screen.height), display: false)
            } else {
                window.center()
            }
        }
        window.setFrameAutosaveName("MarkUpEditor")
        // A frame saved before the limits existed, or with a narrower sidebar, grows to fit them.
        document.enforceMinimumSize()
        window.layoutIfNeeded()
        document.trafficLightsMaxX = window.trafficLightsMaxX
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not supported") }
}

@MainActor
final class EditorDocument: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    static let shared = EditorDocument()
    @Published var language = InterfaceLanguage.saved {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage")
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
            updateTitle()
            if ready { Task { do { try await syncLanguage() } catch { report(error) } } }
        }
    }
    func tr(_ english: String, _ chinese: String) -> String { language == .english ? english : chinese }
    func syncLanguage() async throws {
        _ = try await call("language", arguments: ["value": language.rawValue], script: "window.markup.language(value)")
    }
    @Published private(set) var layout = EditorLayout.saved
    func setLayout(_ next: EditorLayout) {
        guard ready, next != layout else { return }
        perform {
            let applied = try await self.call("layout", arguments: ["value": next.rawValue], script: "return window.markup.layout(value)") as? Bool
            if applied == true {
                self.layout = next
                UserDefaults.standard.set(next.rawValue, forKey: "editorLayout")
            }
        }
    }
    let recentFiles = RecentFiles()
    @Published var showSidebar = UserDefaults.standard.bool(forKey: "sidebarVisible") {
        didSet {
            UserDefaults.standard.set(showSidebar, forKey: "sidebarVisible")
            resizeForSidebar()
        }
    }
    static let defaultSidebarWidth: CGFloat = 200
    static let sidebarWidths: ClosedRange<CGFloat> = 200...420
    static let editorMinWidth: CGFloat = 540
    @Published private(set) var sidebarWidth: CGFloat = {
        let saved = CGFloat(UserDefaults.standard.double(forKey: "sidebarWidth"))
        return saved > 0 ? min(max(saved, sidebarWidths.lowerBound), sidebarWidths.upperBound) : defaultSidebarWidth
    }()
    /// Resizes within limits that always leave the editor its minimum width, widening the window when it has
    /// no room to give. Only the final width is saved.
    func resizeSidebar(to width: CGFloat, persist: Bool = false) {
        var upper = Self.sidebarWidths.upperBound
        if let window {
            let wanted = min(width, upper) + Self.editorMinWidth + InterfaceMetrics.windowInset
            if wanted > window.contentLayoutRect.width, let screen = window.screen?.visibleFrame {
                var frame = window.frame
                frame.size.width = min(frame.width + wanted - window.contentLayoutRect.width, screen.maxX - frame.minX)
                window.setFrame(frame, display: true)
            }
            upper = min(upper, window.contentLayoutRect.width - Self.editorMinWidth - InterfaceMetrics.windowInset)
        }
        sidebarWidth = min(max(width.rounded(), Self.sidebarWidths.lowerBound), max(upper, Self.sidebarWidths.lowerBound))
        if persist { UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth") }
        resizeForSidebar()
    }
    /// The card keeps the editor minimum; glass shows on its right, and on its left unless the sidebar fills that side.
    var minimumWindowWidth: CGFloat { Self.editorMinWidth + InterfaceMetrics.windowInset + (showSidebar ? sidebarWidth : InterfaceMetrics.windowInset) }
    /// Where the traffic lights end, so the toolbar clears them while the sidebar is hidden.
    @Published var trafficLightsMaxX: CGFloat = 0
    @Published var sidebarTab = UserDefaults.standard.string(forKey: "sidebarTab") ?? "outline" {
        didSet { UserDefaults.standard.set(sidebarTab, forKey: "sidebarTab") }
    }
    @Published var headings: [Heading] = []
    var activeHeading: Int? { headings.last(where: { $0.line <= line })?.line }
    func toggleSidebar() { withAnimation(.interface(.sidebar)) { showSidebar.toggle() } }
    private func resizeForSidebar() { enforceMinimumSize() }
    /// The smallest window that keeps the toolbar, editor, and sidebar usable.
    var minimumWindowSize: NSSize { NSSize(width: minimumWindowWidth, height: InterfaceMetrics.windowMinHeight) }
    func enforceMinimumSize() {
        guard let window else { return }
        let minimum = minimumWindowSize
        window.contentMinSize = minimum
        if window.frame.width < minimum.width || window.frame.height < minimum.height {
            var frame = window.frame
            frame.origin.y -= max(0, minimum.height - frame.height)
            frame.size = NSSize(width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
            window.setFrame(frame, display: true)
        }
    }
    /// The hosting view can loosen the window's own limits, so every live resize is held to them here too.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = minimumWindowSize
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
    }
    func goToHeading(_ heading: Heading) {
        guard ready, !composing else { return }
        perform { _ = try await self.call("goToHeading", arguments: ["line": heading.line], script: "return window.markup.goToHeading(line)") }
    }
    @Published var text = ""
    /// An empty window shows the start page until a file opens or a new one starts. The welcome path skips it.
    @Published var showStart = !Onboarding.shared.showWelcome
    @Published var savedText = ""
    @Published var fileURL: URL?
    @Published var sourceMode = false
    @Published var ready = false
    @Published var showFind = false
    @Published var query = ""
    @Published var searchMissed = false
    var findStatus: String { searchMissed ? tr("Not found", "未找到") : "" }
    @Published var line = 1
    @Published var busy = false
    weak var webView: WKWebView?
    /// The bundled index.html, the one page the web view may show.
    var editorPageURL: URL?
    weak var window: NSWindow?
    private var allowClose = false
    var closeApproved: Bool { allowClose }
    private var pendingOpens: [(URL, (NSApplication.DelegateReply) -> Void)] = []
    private var bridgeReady = false
    private var pendingPresentation = false
    private var diskData: Data?
    /// On by default: a document with a file saves itself shortly after typing stops, and before it is left.
    @Published var autoSave = UserDefaults.standard.object(forKey: "autoSave") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSave, forKey: "autoSave") }
    }
    private var pendingAutoSave: Task<Void, Never>?
    /// Typing pauses this long before a save, so a burst of keys writes once.
    private static let autoSaveDelay: Duration = .seconds(1)
    private var composing = false
    var dirty: Bool { text != savedText }
    var title: String { fileURL?.lastPathComponent ?? tr("Untitled", "未命名") }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            bridgeReady = true
            Task {
                do {
                    try await syncLanguage()
                    _ = try await call("layout", arguments: ["value": layout.rawValue], script: "return window.markup.layout(value)")
                    _ = try await call("load", arguments: ["text": text], script: "window.markup.load(text)")
                    ready = true
                    drainOpenRequests()
                } catch { report(error) }
            }
        case "change": text = body["text"] as? String ?? text; updateTitle(); scheduleAutoSave()
        case "selection": line = body["line"] as? Int ?? 1
        case "outline":
            headings = (body["headings"] as? [[String: Any]] ?? []).compactMap {
                guard let line = $0["line"] as? Int, line > 0,
                      let level = $0["level"] as? Int, (1...6).contains(level),
                      let title = $0["title"] as? String else { return nil }
                return Heading(line: line, level: level, title: title)
            }
        case "composition": composing = body["active"] as? Bool ?? false
        default: break
        }
    }
    func attach(_ web: WKWebView) {
        ready = false
        bridgeReady = false
        webView = web
    }
    func call(_ name: String, arguments: [String: Any] = [:], script: String? = nil) async throws -> Any? {
        guard bridgeReady, let webView else { throw EditorError.message(tr("The editor is not ready. Please try again in a moment.", "编辑器尚未准备好，请稍后重试。")) }
        return try await webView.callAsyncJavaScript(script ?? "return window.markup.\(name)()", arguments: arguments, in: nil, contentWorld: .page)
    }
    func snapshot() async throws -> String {
        guard !composing else { throw EditorError.message(tr("Finish the current input before saving or switching files.", "请先完成当前输入，再保存或切换文件。")) }
        guard let value = try await call("snapshot") as? String else { throw EditorError.message(tr("Unable to read the editor content. Your file has not been changed.", "无法读取编辑内容，文件未被修改。")) }
        text = value
        return value
    }
    func updateTitle() {
        window?.title = title
        window?.isDocumentEdited = dirty
        window?.representedURL = fileURL
    }
    func report(_ error: Error) { let alert = NSAlert(error: error); if let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String { alert.informativeText = detail }; if let button = alert.buttons.first { button.title = tr("OK", "好") }; alert.runModal() }
    func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false; drainOpenRequests() }; do { try await operation() } catch { report(error) } }
    }
    func newFile() { perform { if await self.confirmDiscard() { try await self.replace(text: "", url: nil, data: nil) } } }
    func open() {
        perform {
            guard await self.confirmDiscard() else { return }
            let panel = NSOpenPanel(); panel.title = self.tr("Open Markdown", "打开 Markdown"); panel.prompt = self.tr("Open", "打开"); panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText, .plainText]; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try await self.read(url)
        }
    }
    func presentEditorWindow() {
        pendingPresentation = true
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        pendingPresentation = false
    }
    func attachWindow(_ window: NSWindow) {
        self.window = window
        window.delegate = self
        window.tabbingMode = .disallowed
        resizeForSidebar()
        updateTitle()
        if pendingPresentation { presentEditorWindow() }
    }
    func openURL(_ url: URL, completion: @escaping (NSApplication.DelegateReply) -> Void = { _ in }) {
        guard url.isFileURL else { completion(.failure); return }
        presentEditorWindow()
        hideStart()
        pendingOpens.append((url.standardizedFileURL.resolvingSymlinksInPath(), completion))
        drainOpenRequests()
    }
    private func drainOpenRequests() {
        guard ready, !busy, !pendingOpens.isEmpty else { return }
        let (url, completion) = pendingOpens.removeFirst()
        busy = true
        Task {
            defer { busy = false; drainOpenRequests() }
            // Reopening the current file must preserve unsaved edits.
            if url == fileURL?.standardizedFileURL {
                recentFiles.recordAccess(url)
                presentEditorWindow()
                completion(.success)
                return
            }
            guard await confirmDiscard() else { restoreStart(); completion(.cancel); return }
            do {
                try await read(url)
                presentEditorWindow()
                completion(.success)
            } catch {
                restoreStart()
                report(error)
                completion(.failure)
            }
        }
    }
    func read(_ requestedURL: URL) async throws {
        let url = requestedURL.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw EditorError.message(tr("This file is not UTF-8 encoded. Convert it to UTF-8 before opening. The original file has not been changed.", "此文件不是 UTF-8 编码。请转换为 UTF-8 后打开，原文件未被修改。")) }
        try await replace(text: text, url: url, data: data)
    }
    func replace(text value: String, url: URL?, data: Data?) async throws {
        _ = try await call("load", arguments: ["text": value], script: "window.markup.load(text)")
        text = value; savedText = value; fileURL = url; diskData = data; line = 1; updateTitle()
        if let url { recentFiles.recordAccess(url) }
        hideStart()
        if let webView { window?.makeFirstResponder(webView) }
    }
    private func hideStart() {
        guard showStart else { return }
        withAnimation(.interface(.easeOut(duration: 0.2))) { showStart = false }
    }
    /// A file that failed to open leaves the window as empty as before, so the start page comes back.
    private func restoreStart() {
        guard fileURL == nil, text.isEmpty, !Onboarding.shared.showWelcome else { return }
        withAnimation(.interface(.easeOut(duration: 0.2))) { showStart = true }
    }
    func save(asNew: Bool = false) { perform { _ = try await self.write(asNew: asNew) } }
    func write(asNew: Bool = false) async throws -> Bool {
        let content = try await snapshot()
        var destination = fileURL
        if asNew || destination == nil {
            let panel = NSSavePanel(); panel.title = tr("Save Markdown", "保存 Markdown"); panel.prompt = tr("Save", "保存"); panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = fileURL?.lastPathComponent ?? tr("Untitled.md", "未命名.md")
            panel.directoryURL = fileURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK else { return false }; destination = panel.url
        }
        guard let chosenTarget = destination else { return false }
        let target = chosenTarget.standardizedFileURL.resolvingSymlinksInPath()
        if target == fileURL, let diskData {
            let current = try Data(contentsOf: target)
            if current != diskData {
                let alert = NSAlert(); alert.messageText = tr("The file was changed by another app", "文件已被其他应用修改"); alert.informativeText = tr("Replacing will overwrite the version on disk. Cancel and choose Save As to keep both versions.", "覆盖会替换磁盘上的版本。也可以取消，然后选择另存为保留两个版本。"); alert.addButton(withTitle: tr("Cancel", "取消")); alert.addButton(withTitle: tr("Replace", "覆盖"))
                guard alert.runModal() == .alertSecondButtonReturn else { return false }
            }
        }
        let bytes = Data(content.utf8)
        try bytes.write(to: target, options: .atomic)
        fileURL = target; savedText = content; diskData = bytes; updateTitle()
        recentFiles.recordAccess(target)
        return true
    }
    func confirmDiscard() async -> Bool {
        do { _ = try await snapshot() } catch { report(error); return false }
        guard dirty else { return true }
        // Leaving a file-backed document saves it, unless another app changed the file; then the user decides.
        if canAutoSave {
            do { if try await write() { return true } } catch { report(error); return false }
        }
        let alert = NSAlert(); alert.messageText = tr("Save changes to “\(title)”?", "要保存对“\(title)”的修改吗？"); alert.informativeText = tr("Your unsaved changes will be lost.", "未保存的修改将会丢失。"); alert.addButton(withTitle: tr("Save", "保存")); alert.addButton(withTitle: tr("Cancel", "取消")); alert.addButton(withTitle: tr("Don’t Save", "不保存"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: do { return try await write() } catch { report(error); return false }
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    /// Auto-save never overwrites a file another app changed; that waits for a save the user asks for.
    private var canAutoSave: Bool {
        guard autoSave, let fileURL, let diskData else { return false }
        return (try? Data(contentsOf: fileURL)) == diskData
    }
    private func scheduleAutoSave() {
        pendingAutoSave?.cancel()
        guard autoSave, fileURL != nil, dirty else { return }
        pendingAutoSave = Task { [weak self] in
            try? await Task.sleep(for: Self.autoSaveDelay)
            guard !Task.isCancelled else { return }
            self?.autoSaveNow()
        }
    }
    /// Saves quietly: skipped while busy or mid-composition, and retried on the next change.
    func autoSaveNow() {
        pendingAutoSave?.cancel()
        guard dirty, !busy, !composing, canAutoSave else { return }
        perform { _ = try await self.write() }
    }
    func windowDidResignKey(_ notification: Notification) { autoSaveNow() }
    /// The find field selects in the editor's teal, so a query looks the same as the match it finds.
    private lazy var findFieldEditor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.selectedTextAttributes = [.backgroundColor: NSColor.editorSelection]
        return editor
    }()
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client is NSTextField ? findFieldEditor : nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        guard !busy else { return false }
        perform { if await self.confirmDiscard() { self.allowClose = true; sender.close() } }
        return false
    }
    func toggleMode() {
        perform {
            let next = !self.sourceMode
            let result = try await self.call("mode", arguments: ["value": next], script: "return window.markup.mode(value)") as? Bool
            if result == true { self.sourceMode = next }
        }
    }
    func command(_ name: String) { perform { _ = try await self.call("command", arguments: ["name": name], script: "window.markup.command(name)") } }
    func toggleFind() {
        guard !showStart else { return }
        if showFind { closeFind() } else { withAnimation(.interface(.easeOut(duration: 0.18))) { showFind = true } }
    }
    func closeFind() {
        withAnimation(.interface(.easeIn(duration: 0.12))) { showFind = false }
        if let webView { window?.makeFirstResponder(webView) }
    }
    /// ⌘G repeats the last search, opening the find bar when there is nothing to repeat yet.
    func findAgain(backward: Bool = false) {
        guard !showStart else { return }
        if query.isEmpty { if !showFind { toggleFind() } } else { find(backward: backward) }
    }
    func find(backward: Bool = false) {
        perform {
            let found = try await self.call("find", arguments: ["query": self.query, "backward": backward], script: "return window.markup.find(query, backward)") as? Bool ?? false
            self.searchMissed = !found
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        bridgeReady = false
        report(EditorError.message(tr("The editor process stopped unexpectedly. Restoring the last received content. Please review it before saving.", "编辑进程意外退出。正在恢复最近收到的内容，请检查后保存。")))
        webView.reload()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Only the editor page loads. A file dropped on the editor would otherwise replace the page with its raw
        // text, so a Markdown file opens as a document and anything else is refused.
        guard let url = navigationAction.request.url, url.isFileURL else { decisionHandler(.cancel); return }
        if url.standardizedFileURL == editorPageURL?.standardizedFileURL { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if ["md", "markdown"].contains(url.pathExtension.lowercased()) { openURL(url) }
    }
}

enum EditorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct EditorWindow: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject private var onboarding = Onboarding.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            // Laid out at full width and revealed from its trailing edge, so it slides rather than reflows.
            EditorSidebar(document: document, files: document.recentFiles)
                .frame(width: document.sidebarWidth)
                .frame(width: document.showSidebar ? document.sidebarWidth : 0, alignment: .trailing).clipped()
                .allowsHitTesting(document.showSidebar).accessibilityHidden(!document.showSidebar)
            if document.showSidebar { SidebarResizeHandle(document: document) }
            editor.floatingCard().padding(document.showSidebar ? [.vertical, .trailing] : .all, InterfaceMetrics.windowInset)
                // Settles to full size as the welcome glass clears above it.
                .scaleEffect(onboarding.showWelcome && !reduceMotion ? 0.985 : 1)
        }
        .disabled(onboarding.showWelcome)
        .accessibilityHidden(onboarding.showWelcome)
        .frame(minWidth: document.minimumWindowWidth, minHeight: InterfaceMetrics.windowMinHeight)
        .background(WindowGlass())
        .overlay { HintLayer(document: document, onboarding: onboarding) }
        .coordinateSpace(.named(Onboarding.space))
        .overlay {
            if onboarding.showWelcome {
                WelcomeScreen(document: document, onboarding: onboarding).transition(.opacity)
            }
        }
        .tint(.interfaceAccent)
        .ignoresSafeArea()
        .onChange(of: document.query) { _, _ in document.searchMissed = false }
        // Reaching a feature spends its hint.
        .onChange(of: document.showSidebar) { _, shown in
            if shown { onboarding.used(.sidebar, document: document) }
            if shown && document.sidebarTab == "outline" { onboarding.used(.outline, document: document) }
            onboarding.schedule(document)
        }
        .onChange(of: document.sidebarTab) { _, tab in if tab == "outline" { onboarding.used(.outline, document: document) } }
        .onChange(of: document.layout) { _, _ in onboarding.used(.layout, document: document) }
        .onChange(of: document.sourceMode) { _, _ in onboarding.used(.source, document: document) }
        .onChange(of: document.showFind) { _, shown in if shown { onboarding.used(.find, document: document) } }
        .onChange(of: document.ready) { _, ready in if ready { onboarding.schedule(document) } }
        .onChange(of: document.showStart) { _, _ in onboarding.schedule(document) }
    }
    private var editor: some View {
        VStack(spacing: 0) {
            EditorToolbar(document: document)
            if document.showFind {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(document.tr("Find text", "查找文本"), text: $document.query).textFieldStyle(.plain).focused($searchFocused).task { await Task.yield(); searchFocused = true }.onDisappear { searchFocused = false }.onSubmit { document.find() }
                        Text(document.findStatus).font(.caption).foregroundStyle(.secondary).fixedSize().accessibilityLabel(document.findStatus)
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle.control.fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle.control.strokeBorder(Color.secondary.opacity(searchFocused ? 0.6 : 0), lineWidth: 1))
                    .animation(.interface(.easeOut(duration: 0.12)), value: searchFocused)
                    .contentShape(RoundedRectangle.control)
                    .onTapGesture { searchFocused = true }
                    Button { document.find(backward: true) } label: { Image(systemName: "chevron.up").frame(width: 40, height: 40) }.buttonStyle(SidebarButtonStyle()).disabled(document.query.isEmpty).accessibilityLabel(document.tr("Previous match", "上一个")).help(document.tr("Previous match", "上一个"))
                    Button { document.find() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40) }.buttonStyle(SidebarButtonStyle()).disabled(document.query.isEmpty).accessibilityLabel(document.tr("Next match", "下一个")).help(document.tr("Next match", "下一个"))
                    Button { document.closeFind() } label: { Text(document.tr("Done", "完成")).frame(minWidth: 44, minHeight: 40) }.buttonStyle(SidebarButtonStyle()).keyboardShortcut(.escape, modifiers: [])
                }.padding(.horizontal, 12).padding(.vertical, 4)
                .transition(.opacity)
            }
            ZStack {
                VStack(spacing: 0) {
                    WebEditor(document: document)
                    statusRow
                }
                if document.showStart {
                    StartPage(document: document, files: document.recentFiles).transition(.opacity)
                }
            }
        }
    }
    private var statusRow: some View {
        HStack(spacing: 8) {
            Text(document.dirty ? document.tr("Unsaved", "未保存") : document.fileURL == nil ? document.tr("Local Markdown", "本地 Markdown") : document.tr("Saved", "已保存"))
            Spacer()
            Text(document.tr(document.text.count == 1 ? "1 character" : "\(document.text.count) characters", "\(document.text.count) 字符")).frame(minWidth: 90, alignment: .trailing)
            Text(document.tr("Line \(document.line)", "第 \(document.line) 行")).frame(minWidth: 48, alignment: .trailing)
        }.font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().padding(.horizontal, 12).frame(height: 40)
    }
}

final class DocumentWebView: WKWebView {
    weak var editorDocument: EditorDocument?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, let editorDocument else { return }
        editorDocument.attachWindow(window)
    }
}

struct WebEditor: NSViewRepresentable {
    let document: EditorDocument
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: "document.documentElement.dataset.layout = '\(document.layout.rawValue)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(document, name: "editor")
        let web = DocumentWebView(frame: .zero, configuration: config)
        web.editorDocument = document
        web.navigationDelegate = document
        web.setValue(false, forKey: "drawsBackground")
        document.attach(web)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") ?? Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            document.editorPageURL = url
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
