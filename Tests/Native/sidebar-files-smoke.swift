import Foundation

@main
struct RecentFilesSmoke {
    @MainActor
    static func main() throws {
        let suite = "markup-recents-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("markup-recents-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func url(_ name: String) -> URL { root.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath() }
        let first = url("First.md"), second = url("笔记.MD")
        let bytes = Data("# Original\n".utf8)
        try bytes.write(to: first)
        try bytes.write(to: second)
        let files = RecentFiles(defaults: defaults)
        precondition(files.recent.isEmpty && files.pinned.isEmpty)
        files.recordAccess(first)
        files.recordAccess(second)
        files.recordAccess(first)
        precondition(files.recent == [second, first], "Reopening a listed file must keep its position")
        let alias = root.appendingPathComponent("Alias.md")
        try fm.createSymbolicLink(at: alias, withDestinationURL: first)
        files.recordAccess(alias)
        precondition(files.recent == [second, first], "Canonical paths must not duplicate a file")
        files.recordAccess(url("ignored.txt"))
        files.recordAccess(URL(string: "https://example.com/remote.md")!)
        precondition(files.recent == [second, first])
        files.togglePin(second)
        files.togglePin(first)
        files.recordAccess(first)
        precondition(files.pinned == [second, first] && files.recent.isEmpty, "Pins must stay ordered and not repeat in Recents")
        for index in 0..<60 { files.recordAccess(url("\(index).md")) }
        precondition(files.recent.count == RecentFiles.limit && files.recent.first == url("59.md"))
        precondition(files.pinned == [second, first], "Recent history limits must not evict pins")
        let a = url("20.md"), b = url("21.md")
        files.move(a, toPinned: false, at: 0)
        precondition(files.recent.first == a, "Reordering moves within Recents")
        files.move(a, toPinned: false, at: 3)
        precondition(Array(files.recent.prefix(3)) == [url("59.md"), url("58.md"), a], "Index counts rows before removal")
        files.move(b, toPinned: true, at: 1)
        precondition(files.pinned == [second, b, first] && !files.recent.contains(b), "Dragging into Pinned pins at the drop point")
        files.move(second, toPinned: true, at: 3)
        precondition(files.pinned == [b, first, second], "Pins reorder")
        files.move(b, toPinned: false, at: 0)
        precondition(files.pinned == [first, second] && files.recent.first == b, "Dragging out of Pinned unpins")
        files.move(url("missing.md"), toPinned: true, at: 0)
        precondition(files.pinned == [first, second], "Unlisted files are ignored")
        let moved = RecentFiles(defaults: defaults)
        precondition(moved.pinned == files.pinned && moved.recent == files.recent, "Moves persist")
        files.move(first, toPinned: true, at: 0); files.move(second, toPinned: true, at: 1)
        let restored = RecentFiles(defaults: defaults)
        precondition(restored.pinned == files.pinned && restored.recent == files.recent)
        restored.togglePin(second)
        precondition(restored.pinned == [first] && restored.recent.first == second)
        restored.remove(first)
        precondition(restored.pinned.isEmpty && !restored.recent.contains(first))
        restored.remove(second)
        precondition(!restored.recent.contains(second))
        let firstAfterRemoval = try Data(contentsOf: first)
        let secondAfterRemoval = try Data(contentsOf: second)
        precondition(firstAfterRemoval == bytes && secondAfterRemoval == bytes, "Removing history must never modify files")
        restored.recordAccess(first)
        try fm.removeItem(at: first)
        let afterDeletion = RecentFiles(defaults: defaults)
        precondition(afterDeletion.recent.first == first, "Missing files remain removable without silently losing history")
        afterDeletion.remove(first)
        precondition(!RecentFiles(defaults: defaults).recent.contains(first))
        print("PASS: new files first, stable positions on reopen, deduplication, Unicode paths, .md filtering, pin/unpin, stable pins, history limit, persistence, missing files, nondestructive removal, drag reordering and pin moves")
    }
}
