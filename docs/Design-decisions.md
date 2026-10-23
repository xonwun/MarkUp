# Design decisions

## Editor layouts

Chosen from the editor-layout prototype: offer both Compact and Reading, and remember the selection. The switch lives in the toolbar (see Toolbar). Compact is the initial default.

- Compact: 15px body, 1.6 line spacing, 24px padding, 900px maximum container width, left aligned. Headings: 26 / 21 / 18px.
- Reading: 16px body, 1.65 line spacing, 32px padding, 760px maximum container width, column centered in the window; all text, tables, and source inside it stay left-aligned. Rejected: center-aligned prose, which made headings, paragraphs, and lists hard to scan. Headings: 28 / 23 / 19px.
- Remove the document-wide focus rectangle; retain the editing caret and native focus indicators on controls.
- Rejected: the original 17px body, 1.85 spacing, 52px desktop padding, and enclosing focus stroke felt oversized and distracting.
- Layout changes only update CSS. They do not recreate the editor, change source mode, or reset content, selection, or undo history.

## Toolbar

Chosen from the toolbar prototype (Current / Native / Bare): **Bare**.

- Compact toolbar style (`.unifiedCompact`): 40pt instead of the unified style's 52pt.
- No system glass containers. The two clusters are custom views on borderless items (`isBordered = false`), drawn with the sidebar's own styles: icon buttons use `SidebarButtonStyle` (8pt continuous hover/selected tint, 32×28pt), and Compact/Reading uses `segmentTrack()` with 6pt inset segments, matching the Files/Outline tabs. Its segments are icons (`text.justify.left` for Compact, `book` for Reading), with the names in tooltips and accessibility labels.
- Order: sidebar and open on the left; document title centered; Compact/Reading, then find, source, and save on the right. The bottom bar keeps only status and counts.
- Toggles show state: the sidebar, find, and source buttons take the selected tint while their mode is on.
- Rejected: **Current** (unified, 52pt, layout switch in the bottom bar) felt tall for a single-document editor. **Native** (compact with system segmented control) kept three heavy glass capsules side by side and pushed the title off-center.
- Trade-off accepted: icon buttons are 32×28pt, under the 40pt desktop hit-area guideline, in line with compact native toolbar buttons.

## Corner geometry

- One radius: 8pt, drawn continuous (`InterfaceMetrics.controlCornerRadius`, `RoundedRectangle.control`) for sidebar rows, icon tabs, toolbar buttons, find buttons, the find field, and the layout switch. These are all custom so they match; native windows and menus keep macOS shapes.
- Nested shapes are concentric: segmented choices (the sidebar's Files/Outline tabs and the Compact/Reading switch) share one style, with 6pt segments sitting 2pt inside an 8pt track.
- Editor blocks (code blocks, tables, diagrams) use the same 8px (`--radius-block`). Code blocks round only the start and end of the whole block; internal lines meet flush. Mermaid node boxes use 6px.
- Inline code uses 4px, repeated at wrapped fragments.
- WebKit does not support CSS `corner-shape` yet, so web corners are circular arcs. A `@supports` rule switches them to superellipse corners once it does.
- Structural panes and dividers stay edge-to-edge; rounding each pane would introduce gaps between adjoining surfaces.
