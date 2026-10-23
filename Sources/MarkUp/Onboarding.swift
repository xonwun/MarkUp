import SwiftUI

// Disambiguate the property wrapper from the SDK’s State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// First-run guidance: a welcome screen once, then one hint at a time at each feature the first time it matters.
@MainActor
final class Onboarding: ObservableObject {
    static let shared = Onboarding()

    enum Hint: String, CaseIterable {
        case sidebar, outline, layout, source, find
    }

    @Published private(set) var showWelcome: Bool
    @Published private(set) var current: Hint?
    private var done: Set<Hint>
    private var tipsOff: Bool
    private var pending: Task<Void, Never>?
    /// The open hint's anchor, in its window's top-left content coordinates. Clicks elsewhere in that window are held back.
    var target: (window: NSWindow, frame: CGRect)?
    private var clickMonitor: Any?
    /// A hint whose popover just closed, spent at the end of this event unless a blocked click restores it.
    private var closing: Hint?

    private init() {
        let defaults = UserDefaults.standard
        // Preferences outlive the app, so a fresh install or an update would otherwise skip the tour.
        // The stamp changes with the build number and each time the app is copied into place.
        let stamp = Self.installStamp
        if defaults.string(forKey: "onboardingInstall") != stamp {
            ["welcomeSeen", "hintsSeen", "hintsOff"].forEach(defaults.removeObject(forKey:))
            defaults.set(stamp, forKey: "onboardingInstall")
        }
        showWelcome = !defaults.bool(forKey: "welcomeSeen")
        done = Set((defaults.stringArray(forKey: "hintsSeen") ?? []).compactMap(Hint.init))
        tipsOff = defaults.bool(forKey: "hintsOff")
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.allows(event) ?? true } ? event : nil
        }
    }

    private static var installStamp: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let installed = values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
        return "\(build)-\(Int(installed.timeIntervalSince1970))"
    }

    /// While a hint is open, only its feature and the hint itself (another window) take clicks.
    /// The popover closes itself on a click elsewhere before this runs, so a blocked click brings it back.
    private func allows(_ event: NSEvent) -> Bool {
        guard current ?? closing != nil, let target, event.window === target.window, let content = target.window.contentView else { return true }
        let point = CGPoint(x: event.locationInWindow.x, y: content.frame.height - event.locationInWindow.y)
        if target.frame.insetBy(dx: -4, dy: -4).contains(point) { return true }
        if let closing { current = closing; self.closing = nil }
        return false
    }
    /// Long enough that a hint follows the user's attention instead of interrupting it.
    private static let delay: Duration = .milliseconds(900)

    func finishWelcome(document: EditorDocument) {
        UserDefaults.standard.set(true, forKey: "welcomeSeen")
        withAnimation(.interface(.welcomeDissolve)) { showWelcome = false }
        if let webView = document.webView { document.window?.makeFirstResponder(webView) }
        openWelcomeDocument(document)
        schedule(document)
    }

    /// Opens the guide as a real file the user owns, copied once to Application Support, so edits save normally.
    /// Skipped when MarkUp was launched to open a file.
    private func openWelcomeDocument(_ document: EditorDocument) {
        guard document.fileURL == nil, document.text.isEmpty,
              let source = Bundle.main.url(forResource: "Welcome", withExtension: "md", subdirectory: "Web") ?? Bundle.module.url(forResource: "Welcome", withExtension: "md", subdirectory: "Web") else { return }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("MarkUp", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("Welcome.md")
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
            document.openURL(target)
        } catch { document.report(error) }
    }

    /// The feature was used: its hint is spent, and the next one may follow.
    func used(_ hint: Hint, document: EditorDocument) {
        markDone(hint)
        if current == hint { current = nil }
        schedule(document)
    }

    /// Closed without using the feature, by Escape or a click on the feature itself.
    func dismiss(_ hint: Hint, document: EditorDocument) {
        guard current == hint else { return }
        current = nil
        closing = hint
        DispatchQueue.main.async { [weak self, weak document] in
            guard let self, let document, self.closing == hint else { return }
            self.closing = nil
            self.used(hint, document: document)
        }
    }

    func turnOff() {
        tipsOff = true
        UserDefaults.standard.set(true, forKey: "hintsOff")
        pending?.cancel()
        current = nil
    }

    /// The sidebar moved every anchor: hide the open hint without spending it, then pick again once it settles.
    func layoutChanged(document: EditorDocument) {
        if let current, current != .sidebar, current != .outline { self.current = nil }
        schedule(document)
    }

    func schedule(_ document: EditorDocument) {
        pending?.cancel()
        guard !tipsOff, !showWelcome, current == nil else { return }
        pending = Task { [weak self, weak document] in
            try? await Task.sleep(for: Self.delay)
            guard let self, let document, !Task.isCancelled, self.current == nil else { return }
            self.current = self.next(document)
        }
    }

    private func next(_ document: EditorDocument) -> Hint? {
        Hint.allCases.first { hint in
            guard !done.contains(hint) else { return false }
            switch hint {
            case .sidebar: return !document.showSidebar
            case .outline: return document.showSidebar && document.sidebarTab != "outline"
            case .layout, .source, .find: return document.ready
            }
        }
    }

    private func markDone(_ hint: Hint) {
        done.insert(hint)
        UserDefaults.standard.set(done.map(\.rawValue), forKey: "hintsSeen")
    }
}

extension Animation {
    /// The welcome glass clearing: long and decelerating, so the card surfaces through it rather than popping in.
    static let welcomeDissolve = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.7)
}

/// Glass over the whole window, holding a single word and one way forward. It dissolves to reveal the editor.
struct WelcomeScreen: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var onboarding: Onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Text(document.tr("Welcome", "欢迎"))
                // New York, the system serif: a book-like voice for a writing app, with nothing to bundle.
                .font(.system(size: 104, weight: .regular, design: .serif))
                .tracking(-2)
                .blur(radius: appeared || reduceMotion ? 0 : 12)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
                .opacity(appeared ? 1 : 0)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.55), value: appeared)
                .accessibilityAddTraits(.isHeader)
            Text(document.tr("A quiet place to write Markdown", "一个安静书写 Markdown 的地方"))
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .padding(.top, 18)
                .rise(appeared, delay: 0.26, reduceMotion: reduceMotion)
            Button { onboarding.finishWelcome(document: document) } label: {
                Text(document.tr("Start Writing", "开始写作")).padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 32)
            .rise(appeared, delay: 0.35, reduceMotion: reduceMotion)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WindowDragArea() }
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onExitCommand { onboarding.finishWelcome(document: document) }
        // Keys must not reach the editor hidden under the glass; Return still reaches the default button.
        .onAppear { appeared = true; document.window?.makeFirstResponder(nil) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private extension View {
    func rise(_ visible: Bool, delay: Double, reduceMotion: Bool) -> some View {
        offset(y: visible || reduceMotion ? 0 : 6)
            .opacity(visible ? 1 : 0)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22).delay(delay), value: visible)
    }
}

extension View {
    /// Anchors a hint's popover to the feature it describes.
    func onboardingHint(_ hint: Onboarding.Hint, document: EditorDocument) -> some View {
        modifier(HintAnchor(hint: hint, document: document, onboarding: .shared))
    }
}

private struct HintAnchor: ViewModifier {
    let hint: Onboarding.Hint
    let document: EditorDocument
    @ObservedObject var onboarding: Onboarding
    @ViewState private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0; claim() }
            .onChange(of: onboarding.current) { _, _ in claim() }
            .popover(isPresented: Binding(get: { onboarding.current == hint }, set: { if !$0 { onboarding.dismiss(hint, document: document) } }), arrowEdge: .bottom) {
            HintCard(hint: hint, document: document, onboarding: onboarding)
        }
    }

    private func claim() {
        if onboarding.current == hint, let window = document.window { onboarding.target = (window, frame) }
    }
}

private struct HintCard: View {
    let hint: Onboarding.Hint
    let document: EditorDocument
    let onboarding: Onboarding

    private var copy: (title: String, detail: String, shortcut: String?) {
        switch hint {
        case .sidebar: (document.tr("Your files live here", "文件都在这里"), document.tr("Open the sidebar for recent files and this document’s outline.", "打开侧边栏，查看最近的文件和本文档的大纲。"), "⌃⌘S")
        case .outline: (document.tr("Jump by heading", "按标题跳转"), document.tr("Outline lists every heading in the document. Click one to go there.", "大纲列出文档中的所有标题，点击即可跳转。"), nil)
        case .layout: (document.tr("Compact or Reading", "紧凑或阅读"), document.tr("Reading narrows the column for long stretches of text.", "阅读布局会收窄文本栏，适合长篇阅读。"), nil)
        case .source: (document.tr("See the Markdown", "查看 Markdown"), document.tr("Switch to source to edit the raw syntax.", "切换到源码，直接编辑原始语法。"), "⇧⌘M")
        case .find: (document.tr("Find in the document", "在文档中查找"), document.tr("Search the text without leaving the page.", "无需离开页面即可搜索文本。"), "⌘F")
        }
    }

    var body: some View {
        let copy = copy
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.title).font(.system(size: 13, weight: .semibold))
            Text(copy.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let shortcut = copy.shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                Spacer()
                Button(document.tr("Turn Off Tips", "关闭提示")) { onboarding.turnOff() }
                    .buttonStyle(.link).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }
}
