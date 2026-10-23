# Changelog

## 0.4.0 — Tables, diagrams, and sidebar control

- Rendered top-level pipe tables (with column alignment) and Mermaid diagrams in place. Their source returns while the cursor is inside; clicking a table row or diagram, or arrowing into it, moves the cursor there. Saved text is unchanged.
- Mermaid loads from a separate local bundle only when a document contains a diagram, keeping editor start-up unchanged. The editor CSP now allows inline styles, which Mermaid's SVG output needs; scripts are still limited to bundled files.
- Recents no longer moves a file to the top when it is opened or saved. New files are added at the top; after that, the order is yours to arrange by dragging.
- Made the sidebar resizable (200–420pt, remembered across launches). The default is now the 200pt minimum, and double-clicking the edge restores it.
- Restyled the Files/Outline tabs as a segmented track matching the Compact/Reading switch (shared `segmentTrack()` style, 6pt inset segments). If the window has no room left, dragging the edge widens it.
- Added drag-and-drop in the Files sidebar: reorder Pinned or Recents, or drag between them to pin or unpin. An accent line shows where the file will land. Drags stay inside MarkUp.
- Reading now left-aligns all text and tables inside its centered 760px column, instead of center-aligning prose.
- Redesigned the toolbar, chosen from a three-way prototype: compact style (40pt, was 52pt), no glass containers, and buttons drawn with the sidebar's styles. Compact/Reading moved from the bottom bar into the toolbar as an icon switch (lines for Compact, a book for Reading). The sidebar, find, and source buttons show when their mode is on.
- Unified corners on one 8pt continuous radius: code blocks (was 10px), tables, diagrams, the find field, and the Compact/Reading switch, which are now custom controls. Inset segments use 6pt so nested corners stay concentric; inline code keeps 4px.

Validation: 21 editor tests, the WebKit smoke test (tables, Mermaid rendering), the recent-files smoke test (including moves), release build, and signature verification passed. Checked in the running app: table/diagram rendering and click-to-edit, sidebar resize with window growth, pinning, unpinning, and reordering by drag, and the find and layout controls.

## 0.3.2 — Corner consistency

- Applied continuous 8pt corners to custom sidebar and search buttons.
- Rounded complete code blocks at 10px, keeping internal lines flush; retained 4px inline-code corners across wrapping.
- Preserved native macOS window and control geometry.
- Center-aligned Reading prose while preserving left alignment for lists, code, and source mode.

## 0.3.2 — Reading alignment

- Fixed a circular CSS variable that prevented the Reading column from centering in wide windows.

## 0.3.1 — Writing layouts

- Added persistent Compact and Reading tabs in the bottom bar.
- Reduced text and heading sizes, line spacing, and margins; removed the document focus rectangle.
- Layout changes preserve document content, selection, source mode, and undo history.

## 0.3.0 — Pinned and recent files

- Replaced folder browsing with recent `.md` files and a persistent Pinned section.
- Added Open, Show in Finder, Remove from Recents, and Pin/Unpin context actions.
- Replaced Files and Outline text tabs with icons, localized tooltips, and accessibility labels.
- Kept recent history updates behind successful opens and saves, preserving unsaved-change protection.
- Positioned the sidebar/open toolbar group on the left and centered the document title.

Validation: all 17 editor tests, the recent-file storage smoke test, release build, and signature verification passed. Native UI checks covered pin persistence across relaunch, context-menu opening, Finder reveal, removal without closing the current document, and outline navigation.

## 0.2.1 — Interface polish

- Expanded sidebar and search button hit areas and added subtle hover and press feedback, respecting Reduce Motion.
- Grouped empty-state guidance with its action; added Clear Filter and New Document recovery actions.
- Kept filename space stable when the unsaved indicator appears and exposed selected rows to accessibility tools.
- Remembered file tree/list preference and reserved space for dynamic status values.
- Fixed initial search-field focus and restored editor focus when closing Find; cleared stale search failures when the query changes.
- Improved text smoothing, secondary-text contrast, neutral focus indicators, and section-jump spacing.


## 0.2.0 — File and outline sidebar

- Added a hideable sidebar with file tree and flat-list views, filename and relative-path filtering, and Finder reveal actions.
- Added a live H1–H6 outline with section navigation and current-section highlighting.
- Preserved unsaved-change prompts when switching files and editor state when hiding the sidebar.
- Normalized filesystem paths for consistent selection and relative-path display.
- Added English and Simplified Chinese sidebar labels.

Validation: 17 JavaScript tests, real WKWebView checks, and Swift file scanning checks passed. Native UI checks covered heading navigation, undo after hiding the sidebar, Unicode filenames, file filtering, relative paths, current-file highlighting, and canceling unsaved-change prompts.

## 0.1.3 — Cold-start window lifecycle and persistent icon

Replaced lazy SwiftUI window creation with an AppDelegate-owned NSWindowController. The document model now exists before views appear, avoiding a startup dependency between file events and view creation. File requests still wait for WebKit readiness.

Bundled the icon through `CFBundleIconFile = AppIcon.icns`, removed runtime icon replacement, and refreshed the application directory modification time during packaging.

The 0.1.2 activation check had not reliably excluded the inspection tool itself causing window creation. The revised check opened a file from Finder after a full quit, then confirmed an active process and visible normal window using read-only system interfaces before inspecting MarkUp through UI tools. Icon Services returned the custom icon after the process exited. All 13 editor tests and signature validation passed.

## 0.1.2 — Window activation and app icon

Added explicit activation and restoration of hidden or minimized windows on Finder file-open events. Introduced the approved M-with-upward-arrow icon. The initial runtime Dock icon synchronization was replaced by bundle-based delivery in 0.1.3.

## 0.1.1 — System file opening

Added AppKit open-document event handling and a queue that waits for editor readiness. Reopening the current document preserves unsaved edits. Declared the Markdown UTI for `.md` and `.markdown` files.

Finder checks covered cold and warm opens, Unicode and spaced filenames, both extensions, and cancellation when opening another file with unsaved changes.
