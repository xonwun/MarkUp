# Architecture

## Native application

`AppDelegate` owns a single `NSWindowController` and creates it on launch or when a file-open event arrives. The document model exists before any view appears. SwiftUI hosts the editing layout. The AppKit toolbar (compact style) holds the centered title and two borderless items whose views are SwiftUI (`ToolbarCluster` in `EditorToolbar.swift`): sidebar and open on the left; the Compact/Reading switch, find, source, and save on the right.

Finder open-document events are queued until WebKit is ready. Reopening the current file preserves unsaved edits. The app declares the Markdown UTI for `.md` and `.markdown` files.

## Editing and storage

ProseMirror stores the original text as lines. Markdown-it identifies block structure, and decorations provide the formatted editing view. The editor does not convert HTML back to Markdown, preserving whitespace, unknown syntax, line endings, and trailing newlines.

Top-level tables and Mermaid fences form line groups. While the cursor is outside a group, its lines are hidden and a widget decoration shows the rendered block (markdown-it table HTML, or an SVG from Mermaid with `securityLevel: 'strict'`). The underlying lines never change. Mermaid's prebuilt bundle is copied to `Web/mermaid.js` and injected on first use; diagrams are cached by source and appearance.

Input transactions do not recreate the document. During input-method composition, formatting and mode changes are blocked; saving asks the user to finish the current input first.

Files are stored directly on disk. Saves use atomic writes and check for external modifications. There is no autosave or crash-recovery database; users should save explicitly.

## Sidebar

`RecentFiles` stores canonical local `.md` paths in UserDefaults, with separate ordered arrays for pinned files and up to 50 recent files. A successful open or save adds a file that is not yet listed to the top of Recents; listed files keep their position, so the order is the user's. Canceled and failed operations do not record anything. Pins stay ordered independently of recency. Removing an entry changes preferences only. No folder scanning or document database is involved. The heading outline comes from the Markdown parser, rather than a line-based hash search.

`RecentFiles.move` handles drag reordering and moves between sections. Sidebar drags use the `local.markup.sidebar-file` type with own-process visibility, so other apps never receive them. Sidebar width is stored in UserDefaults; the window's minimum width is the editor minimum (540pt) plus the sidebar.

The editor view remains mounted while the sidebar is hidden, preserving its selection, content, and undo history.

## Resources and packaging

`npm run build` bundles the editor and copies its HTML and CSS into `Sources/MarkUp/Resources/Web/`. These are generated resources; make changes in `Editor/`.

The application icon is bundled as `AppIcon.icns` and declared through `CFBundleIconFile`. It is not replaced dynamically at runtime. The icon build script stores intermediate PNG sizes in `.build/AppIcon.iconset/`.

## Limitations

The formatted view is an editing presentation, not a complete CommonMark renderer. Complex nested inline syntax and multiline emphasis may remain visible as source. Source mode exposes all original text.

Visual table editing, image rendering, mathematical notation, multiple tabs, and cloud synchronization are not implemented. Image and HTML source is preserved, but external resources are not loaded and HTML is not executed.
