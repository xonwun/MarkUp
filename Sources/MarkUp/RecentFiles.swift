import Foundation
import Combine

@MainActor
final class RecentFiles: ObservableObject {
    private struct State {
        var pinned: [URL]
        var recent: [URL]
    }

    static let limit = 50
    private let defaults: UserDefaults
    private static let storageKey = "sidebarRecentFiles"
    @Published private var state: State
    var pinned: [URL] { state.pinned }
    var recent: [URL] { state.recent }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.storageKey)
        let pinned = Self.unique(saved?["pinned"] as? [String] ?? [])
        let recent = Self.unique(saved?["recent"] as? [String] ?? []).filter { !pinned.contains($0) }
        state = State(pinned: pinned, recent: Array(recent.prefix(Self.limit)))
    }

    /// Adds a newly opened file to the top of Recents. Listed files keep the position the user gave them.
    func recordAccess(_ url: URL) {
        guard let url = Self.markdownURL(url), !pinned.contains(url), !recent.contains(url) else { return }
        var next = state
        next.recent.insert(url, at: 0)
        update(next)
    }

    func isPinned(_ url: URL) -> Bool {
        guard let url = Self.markdownURL(url) else { return false }
        return pinned.contains(url)
    }

    func togglePin(_ url: URL) {
        guard let url = Self.markdownURL(url) else { return }
        var next = state
        if next.pinned.contains(url) {
            next.pinned.removeAll { $0 == url }
            next.recent.removeAll { $0 == url }
            next.recent.insert(url, at: 0)
        } else {
            next.recent.removeAll { $0 == url }
            next.pinned.append(url)
        }
        update(next)
    }

    /// Moves a listed file to `index` in Pinned or Recents, measured before the file is removed from its old place.
    func move(_ url: URL, toPinned: Bool, at index: Int) {
        guard let url = Self.markdownURL(url) else { return }
        var next = state
        let source = toPinned ? next.pinned.firstIndex(of: url) : next.recent.firstIndex(of: url)
        guard next.pinned.contains(url) || next.recent.contains(url) else { return }
        var target = index
        if let source, source < index { target -= 1 }
        next.pinned.removeAll { $0 == url }
        next.recent.removeAll { $0 == url }
        if toPinned {
            next.pinned.insert(url, at: min(max(target, 0), next.pinned.count))
        } else {
            next.recent.insert(url, at: min(max(target, 0), next.recent.count))
        }
        update(next)
    }

    func remove(_ url: URL) {
        guard let url = Self.markdownURL(url) else { return }
        var next = state
        next.pinned.removeAll { $0 == url }
        next.recent.removeAll { $0 == url }
        update(next)
    }

    private func update(_ next: State) {
        state = State(pinned: next.pinned, recent: Array(next.recent.prefix(Self.limit)))
        defaults.set(["pinned": pinned.map(\.path), "recent": recent.map(\.path)], forKey: Self.storageKey)
    }

    private static func markdownURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        return canonical.pathExtension.lowercased() == "md" ? canonical : nil
    }

    private static func unique(_ paths: [String]) -> [URL] {
        var seen: Set<URL> = []
        return paths.compactMap { path in
            guard path.hasPrefix("/"), let url = markdownURL(URL(fileURLWithPath: path)), seen.insert(url).inserted else { return nil }
            return url
        }
    }
}
