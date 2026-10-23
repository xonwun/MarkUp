# Testing

Run all commands from the project root.

## Editor tests

```sh
npm ci
npm test
```

The JavaScript suite covers exact Unicode, BOM, CRLF, and trailing-newline round trips; multiline paste; undo and redo; formatting; language switching; composition guards; heading extraction; outline navigation; and table and Mermaid block rendering. Chinese text is intentional test data for Unicode and input handling.

## Real WebKit smoke test

Build the offline editor resources first:

```sh
npm run build
swift -swift-version 6 Tests/Native/webkit-smoke.swift "$PWD/Sources/MarkUp/Resources/Web/index.html"
```

This exercises loading, source mode, search, formatting, undo, outline extraction, heading navigation, table rendering and alignment, real Mermaid SVG rendering, and exact snapshots in WKWebView.

## Recent files smoke test

```sh
swiftc -parse-as-library Sources/MarkUp/RecentFiles.swift Tests/Native/sidebar-files-smoke.swift -o /tmp/markup-files-smoke
/tmp/markup-files-smoke
```

This checks that new files are added first and listed files keep their position, canonical path deduplication, Unicode filenames, `.md` filtering, pin/unpin behavior, stable pin ordering, history limits, drag reordering and moves between Pinned and Recents, persistence, missing files, and removal without touching file content. Tests use an isolated preferences suite and temporary files, both removed afterward.

## Application build

```sh
./scripts/build-app.sh
codesign --verify --deep --strict dist/MarkUp.app
```

## Manual acceptance checks

- Use the system Pinyin input method to compose, select candidates, delete, and move the cursor in ordinary text, lists, code blocks, and bold spans.
- Save and reopen a document; cancel closing a modified document; cancel Save As; test an external file conflict.
- Open a Markdown file from Finder with MarkUp fully quit, then while it is running, hidden, or minimized. Confirm that the document window appears without a Dock click.
- Check filenames containing Unicode and spaces, and both supported extensions.
- Jump to headings, hide the sidebar, and undo an edit. Switch files with unsaved changes and cancel the prompt.
- Drag the sidebar edge narrower and wider, including at minimum window width; double-click it to reset. Drag files to reorder, pin, and unpin, and cancel a drag with Escape.
- Click table rows and diagrams to edit them, and arrow up and down through them.
- Check icon-tab tooltips, recent-file ordering, all four context actions, current-file highlighting, and pin persistence after restart. Confirm failed/canceled opens do not enter Recents, and removing the current file leaves its content intact.
- Switch Compact/Reading while editing, in source mode, and after using undo. Restart and verify the selected layout is restored.
- Check both interface languages and system light and dark appearances.
- Quit MarkUp and confirm that its Dock icon remains correct.

Synthetic composition events do not replace testing with a real input method. Native dialogs and window activation also require interactive validation.
