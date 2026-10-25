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
    /// Shown once the last tip is spent, so the user knows the tour is over.
    @Published private(set) var finished = false
    /// Each feature's frame in the window's coordinate space, kept current as the layout moves.
    @Published private(set) var anchors: [Hint: CGRect] = [:]
    /// The open card's frame, so clicks on it get through.
    var cardFrame: CGRect = .zero
    nonisolated static let space = "onboardingWindow"
    private var done: Set<Hint>
    private var tipsOff: Bool
    private var toured = false
    /// How the editor looked when the tour began, so each feature tried can be put back.
    private var baseline: (layout: EditorLayout, sourceMode: Bool, showSidebar: Bool, sidebarTab: String)?
    /// The step just completed, undone once the next tip is up.
    private var lastUsed: Hint?
    /// Long enough to see what the click changed before it is put back.
    private static let revertDelay: Duration = .milliseconds(900)
    private var pending: Task<Void, Never>?
    private weak var window: NSWindow?
    private weak var document: EditorDocument?
    private var monitors: [Any] = []

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
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.allows(event) ?? true } ? event : nil
        } as Any)
        // Escape skips the open tip, as it would close a popover.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let skipped = MainActor.assumeIsolated {
                guard let self, let hint = self.current, let document = self.document else { return false }
                self.used(hint, document: document)
                return true
            }
            return skipped ? nil : event
        } as Any)
    }

    private static var installStamp: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let installed = values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
        return "\(build)-\(Int(installed.timeIntervalSince1970))"
    }

    /// While a tip is open, only its feature and the tip card take clicks.
    private func allows(_ event: NSEvent) -> Bool {
        guard let hint = current, let window, event.window === window, let content = window.contentView else { return true }
        let point = CGPoint(x: event.locationInWindow.x, y: content.frame.height - event.locationInWindow.y)
        return cardFrame.contains(point) || (anchors[hint]?.insetBy(dx: -4, dy: -4).contains(point) ?? false)
    }
    /// Long enough that the first tip follows the user's attention instead of interrupting it.
    private static let delay: Duration = .milliseconds(900)
    /// After a step, the next tip arrives with the change it responds to.
    private static let followDelay: Duration = .milliseconds(120)

    func setAnchor(_ hint: Hint, frame: CGRect) {
        if anchors[hint] != frame { anchors[hint] = frame }
    }

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

    /// The feature was used, or its tip skipped: the tip is spent, and the next one follows.
    func used(_ hint: Hint, document: EditorDocument) {
        markDone(hint)
        if current == hint { lastUsed = hint; withAnimation(.interface(.easeOut(duration: 0.15))) { current = nil } }
        schedule(document, after: Self.followDelay)
    }

    func turnOff() {
        tipsOff = true
        toured = false
        lastUsed = nil
        UserDefaults.standard.set(true, forKey: "hintsOff")
        pending?.cancel()
        withAnimation(.interface(.easeOut(duration: 0.15))) { current = nil }
    }

    func closeFinished() {
        guard finished else { return }
        // The blur clears slowly, so the editor comes back into focus rather than snapping in.
        withAnimation(.interface(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9))) { finished = false }
        if let document { revert(before: nil, document: document) }
    }

    /// Puts back what the finished step changed, so the user leaves the tour with the editor as they found it.
    /// The sidebar stays open while the outline tip still needs it.
    private func revert(before next: Hint?, document: EditorDocument) {
        guard let hint = lastUsed, let baseline else { return }
        lastUsed = nil
        switch hint {
        case .sidebar where next == .outline: lastUsed = .sidebar
        case .sidebar, .outline:
            if document.sidebarTab != baseline.sidebarTab { document.sidebarTab = baseline.sidebarTab }
            if document.showSidebar != baseline.showSidebar { document.toggleSidebar() }
        case .layout: document.setLayout(baseline.layout)
        case .source: if document.sourceMode != baseline.sourceMode { document.toggleMode() }
        case .find: if document.showFind { document.closeFind() }
        }
    }

    func schedule(_ document: EditorDocument, after delay: Duration = Onboarding.delay) {
        pending?.cancel()
        self.document = document
        window = document.window
        guard !tipsOff, !showWelcome, current == nil else { return }
        pending = Task { [weak self, weak document] in
            try? await Task.sleep(for: delay)
            guard let self, let document, !Task.isCancelled, self.current == nil else { return }
            if let next = self.next(document) {
                if !self.toured { self.baseline = (document.layout, document.sourceMode, document.showSidebar, document.sidebarTab) }
                self.toured = true
                withAnimation(.interface(.easeOut(duration: 0.2))) { self.current = next }
                Task { [weak self, weak document] in
                    try? await Task.sleep(for: Self.revertDelay)
                    guard let self, let document else { return }
                    self.revert(before: next, document: document)
                }
            } else if self.toured, document.ready, !document.showStart {
                self.finish()
            }
        }
    }

    /// Tips whose moment never came (the sidebar was already open, say) are spent with the rest.
    private func finish() {
        toured = false
        Hint.allCases.forEach(markDone)
        withAnimation(.interface(.easeOut(duration: 0.25))) { finished = true }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2600))
            self?.closeFinished()
        }
    }

    private func next(_ document: EditorDocument) -> Hint? {
        // Hints point at the editor; the start page is a moment to choose a file, not to learn controls.
        guard !document.showStart else { return nil }
        return Hint.allCases.first { hint in
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
            Greeting(document: document, reduceMotion: reduceMotion)
                .blur(radius: appeared || reduceMotion ? 0 : 12)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
                .opacity(appeared ? 1 : 0)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.55), value: appeared)
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

/// "Hello", then the other greetings in a shuffled loop, typed in with a caret: a writing app writing.
private struct Greeting: View {
    @ObservedObject var document: EditorDocument
    let reduceMotion: Bool
    @ViewState private var shown: String?
    @ViewState private var typing = false
    @ViewState private var caretOn = true
    /// Long enough to read each one; it is the only thing moving on the screen.
    private static let hold: Duration = .milliseconds(2600)
    /// One keystroke; deleting runs at under half of it, and a space takes a beat longer.
    private static let keystroke = 0.06
    private static let size: CGFloat = 104

    private var hello: String { document.tr("Hello", "你好") }
    private var others: [String] { [document.tr("Howdy", "嗨"), "Aloha", document.tr("Have you eaten?", "吃了吗？")] }

    var body: some View {
        let text = shown ?? hello
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // A zero-width space keeps the baseline while the line is empty between words.
            Text(text.isEmpty ? "\u{200B}" : text)
                // New York, the system serif: a book-like voice for a writing app, with nothing to bundle.
                .font(.system(size: Self.size, weight: .regular, design: .serif))
                .tracking(-2)
            RoundedRectangle(cornerRadius: 1.5)
                .frame(width: 3, height: Self.size * 0.82)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Self.size * 0.06 }
                .opacity(caretOn ? 0.7 : 0)
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .padding(.horizontal, 24)
        // One line at full size, so typing never moves what sits below.
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hello)
        .accessibilityAddTraits(.isHeader)
        .task { await cycle() }
        .task { await blink() }
    }

    private func cycle() async {
        var queue: [String] = []
        var last = hello
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            if queue.isEmpty {
                // Reshuffle each round, never repeating the word just shown.
                queue = others.shuffled()
                if queue.first == last { queue.swapAt(0, queue.count - 1) }
            }
            let next = queue.removeFirst()
            if reduceMotion { shown = next } else { await type(from: last, to: next) }
            last = next
        }
    }

    private func type(from old: String, to next: String) async {
        typing = true
        defer { typing = false }
        var current = old
        while !current.isEmpty {
            current.removeLast()
            shown = current
            try? await Task.sleep(for: .seconds(Self.keystroke * 0.45))
        }
        try? await Task.sleep(for: .milliseconds(220))
        for character in next {
            current.append(character)
            shown = current
            let beat = Self.keystroke * Double.random(in: 0.7...1.3) * (character == " " ? 1.8 : 1)
            try? await Task.sleep(for: .seconds(beat))
        }
    }

    /// The caret holds steady while typing and blinks once it rests, like a text cursor. Still under Reduce Motion.
    private func blink() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            caretOn = typing || reduceMotion ? true : !caretOn
        }
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
    /// Marks the feature a tip points at; the tip itself is drawn by `HintLayer`.
    func onboardingHint(_ hint: Onboarding.Hint, document: EditorDocument) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Onboarding.space)) } action: {
            Onboarding.shared.setAnchor(hint, frame: $0)
        }
    }
}

private extension Color {
    /// Raised above the page: white in light mode, a step lighter than the paper in dark.
    static let tipSurface = Color(nsColor: NSColor(name: "tipSurface") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x30 / 255, green: 0x30 / 255, blue: 0x2e / 255, alpha: 1)
            : .white
    })
}

/// Tips drawn inside the window rather than in popovers, so the feature under a tip takes the click directly
/// and the next tip can arrive as the interface changes. Laid over the whole window in `Onboarding.space`.
struct HintLayer: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var onboarding: Onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let width: CGFloat = 260
    private static let margin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let hint = onboarding.current, let anchor = onboarding.anchors[hint] {
                    let x = min(max(anchor.midX - Self.width / 2, Self.margin), proxy.size.width - Self.width - Self.margin)
                    HintCard(hint: hint, document: document, onboarding: onboarding, arrowX: anchor.midX - x)
                        .frame(width: Self.width)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Onboarding.space)) } action: { onboarding.cardFrame = $0 }
                        .offset(x: x, y: anchor.maxY + 10)
                        .animation(.interface(.sidebar), value: anchor)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        .id(hint)
                    TourPointer(reduceMotion: reduceMotion)
                        .offset(x: anchor.midX - 2, y: anchor.midY - 1)
                        .animation(.interface(.sidebar), value: anchor)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                        .id("pointer-\(hint.rawValue)")
                }
                if onboarding.finished {
                    FinishedScreen(document: document, onboarding: onboarding, reduceMotion: reduceMotion)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

private extension Color {
    /// The editor's accent (`--accent` in style.css), so the tour points in the app's own color.
    static let tourGreen = Color(nsColor: NSColor(name: "tourGreen") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x96 / 255, green: 0xc6 / 255, blue: 0xb8 / 255, alpha: 1)
            : NSColor(srgbRed: 0x35 / 255, green: 0x6c / 255, blue: 0x64 / 255, alpha: 1)
    })
}

/// A pointer that glides in from the tip, presses the feature with a green ripple, lifts, and repeats.
/// Its tip sits at the origin; under Reduce Motion it rests on the feature without moving.
private struct TourPointer: View {
    let reduceMotion: Bool
    private static let period = 1.6
    private static let start = CGSize(width: 34, height: 46)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.55 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            let state = Self.state(at: t)
            ZStack(alignment: .topLeading) {
                Circle().strokeBorder(Color.tourGreen, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(state.ripple.scale)
                    .opacity(reduceMotion ? 0 : state.ripple.opacity)
                    .offset(x: -9, y: -10)
                PointerShape().fill(Color.black.opacity(0.88))
                    .overlay(PointerShape().stroke(.white, lineWidth: 1.2))
                    .frame(width: 18, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .scaleEffect(state.press, anchor: UnitPoint(x: 3 / 18, y: 2 / 22))
                    .offset(state.offset)
                    .opacity(reduceMotion ? 1 : state.opacity)
            }
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
    }

    /// The loop, as fractions of the period: glide in (0–45%), press (45–60%), rest, then fade (60–85%).
    private static func state(at t: Double) -> (offset: CGSize, press: CGFloat, opacity: Double, ripple: (scale: CGFloat, opacity: Double)) {
        func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
        func span(_ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
        let glide = 1 - ease(span(0, 0.45))
        let offset = CGSize(width: start.width * glide, height: start.height * glide)
        let press: CGFloat = t < 0.52 ? 1 - 0.14 * ease(span(0.45, 0.52)) : 0.86 + 0.14 * ease(span(0.52, 0.6))
        let opacity = t < 0.12 ? span(0, 0.12) : 1 - span(0.6, 0.85)
        let wave = span(0.5, 0.75)
        let ripple = (scale: CGFloat(0.4 + wave), opacity: t < 0.5 ? 0 : t < 0.54 ? 0.7 * span(0.5, 0.54) : 0.7 * (1 - span(0.54, 0.75)))
        return (offset, press, opacity, ripple)
    }
}

/// The classic arrow pointer, drawn in an 18×22 box with its tip at (2, 1.5).
private struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18, sy = rect.height / 22
        var path = Path()
        for (i, point) in [(2, 1.5), (2, 17.5), (6.2, 13.6), (8.9, 19.8), (11.5, 18.7), (8.8, 12.6), (15, 12.6)].enumerated() {
            let p = CGPoint(x: point.0 * sx, y: point.1 * sy)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

private struct TipSurface: ViewModifier {
    var arrowX: CGFloat?
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.tipSurface)
                    .overlay(alignment: .topLeading) {
                        if let arrowX {
                            Rectangle().fill(Color.tipSurface).frame(width: 10, height: 10)
                                .rotationEffect(.degrees(45))
                                .offset(x: arrowX - 5, y: -4)
                        }
                    }
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct HintCard: View {
    let hint: Onboarding.Hint
    let document: EditorDocument
    let onboarding: Onboarding
    let arrowX: CGFloat

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TipSurface(arrowX: arrowX))
        .accessibilityElement(children: .contain)
    }
}

/// The tour's last word, centered on glass that blurs the editor, then clears to hand it back.
/// A click anywhere ends it early.
private struct FinishedScreen: View {
    let document: EditorDocument
    let onboarding: Onboarding
    let reduceMotion: Bool
    @ViewState private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Text(document.tr("You’re all set", "一切就绪"))
                // The welcome screen's serif, so the tour ends in the voice it began with.
                .font(.system(size: 44, weight: .regular, design: .serif)).tracking(-0.5)
            Text(document.tr("That’s every tip. Happy writing.", "提示已全部完成，祝写作愉快。"))
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture { onboarding.closeFinished() }
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
