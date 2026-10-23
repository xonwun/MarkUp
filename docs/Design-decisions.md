# Design decisions

## Editor layouts

Chosen from the editor-layout prototype: offer both Compact and Reading, and remember the selection. The switch lives in the toolbar (see Toolbar). Compact is the initial default.

- Compact: 15px body, 1.6 line spacing, 24px padding, 900px maximum container width, left aligned. Headings: 26 / 21 / 18px.
- Reading: 16px body, 1.65 line spacing, 32px padding, 760px maximum container width, column centered in the window; all text, tables, and source inside it stay left-aligned. Rejected: center-aligned prose, which made headings, paragraphs, and lists hard to scan. Headings: 28 / 23 / 19px.
- Remove the document-wide focus rectangle; retain the editing caret and native focus indicators on controls.
- Rejected: the original 17px body, 1.85 spacing, 52px desktop padding, and enclosing focus stroke felt oversized and distracting.
- Layout changes only update CSS. They do not recreate the editor, change source mode, or reset content, selection, or undo history.

## Window: glass and floating card

From the Figma draft (MarkUp, page 1: sidebar open and closed, light and dark).

- The glass is the window background, not a pane: one `NSVisualEffectView` (sidebar material) behind everything. The sidebar has no fill of its own and sits directly on it.
- The main area is a card floating on the glass: 6pt from the top, bottom, and right window edges, and from the left edge too while the sidebar is hidden. Chosen by comparing 6pt and 8pt in the app: 6pt keeps the float while giving the page more of the window. Rejected: 8pt (the system's floating-panel inset), which read as a thick band of glass around the card.
- Card corners are concentric with the window: window radius minus inset (`InterfaceMetrics.cardCornerRadius`). The window corner is 16pt from macOS 26 (measured), so the card gets 10pt. Before macOS 26 the window corner is 10pt and the card is clamped to 6pt. Rejected: a fixed radius that ignores the inset (the first pass's 10pt with an 8pt gap), which widened the glass margin at the corners.
- Depth comes from shadows and a ring, not a border (`floatingCard()`):
  - Light: a 1pt ring just outside the edge at 6% black, a crisp contact shadow (1pt blur, 1pt down, 5%), and a soft lift (8pt blur, 4pt down, 8%).
  - Dark: the edge is a 1pt rim just inside the card, white at 11% at the top fading to 5% at the bottom, as if lit from above. The rim carries the lift; the shadows are light (contact 24%, lift 20% black). The card is darker than the glass, so a deeper lift (the first pass's 36%) merged into the card's edge as a dark smudge.
  - The ring and rim ignore clicks.
- The card is filled with the editor's paper color (`Color.paper`, matching `--paper` in `style.css`), so the toolbar and status rows read as one surface with the page.
- In dark mode the card (#222220) sits darker than the glass (about #444345): the rim and contact shadow separate it, not a lighter fill. Rejected: raising the dark palette to about #2a2c2c and tinting the glass 35% black so the card read lighter; the dark paper was kept as is.
- With the sidebar open, the sidebar's trailing edge is the card's leading edge; the resize handle sits there. With it closed, the traffic lights float over the card's top-left corner and the toolbar starts 8pt after them.
- The traffic lights are centered on the toolbar row (center 26pt from the top and from the left edge). The sidebar keeps that row clear and starts with the Files/Outline tabs below it.
- No dividers inside the card or under the sidebar tabs; spacing separates the toolbar, find bar, page, and status row. The Pinned/Recents separator stays.
- Rejected: Liquid Glass (`glassEffect`), which needs macOS 26; MarkUp supports macOS 14.

## Motion

Motion only where it explains a change of layout; everything else applies at once. All of it is dropped under Reduce Motion (`Animation.interface` in Swift, `prefers-reduced-motion` in CSS).

- Sidebar show/hide: 250ms, ease-in-out (`cubic-bezier(0.45, 0, 0.2, 1)`), because the card is already on screen and moves. The sidebar keeps its full width and is revealed from its trailing edge, so it slides in rather than reflowing its rows. Animated from the toolbar button and ⌃⌘S alike, as macOS sidebars are.
- Find bar: fades in over 180ms ease-out while the page eases down; closes in 120ms ease-in. Without it the page jumped 38pt with no cause on screen.
- Find field focus ring: 120ms fade.
- Diagrams: the first render fades in over 200ms. Cached diagrams, redrawn as the cursor leaves their source, appear at once so they don't flash.
- Kept: 0.96 press scale on custom buttons (120ms) and the 120ms fade of sidebar drop markers.
- Not animated: Files/Outline and Compact/Reading switches, the outline's active heading and its scrolling, hover tints, the saved/unsaved status, source mode, and scrolling to a heading or search match. They are frequent or keyboard-driven, and motion there would only slow them down.

## Editor palette

Chosen from the neutral-palette prototype (Paper-led / Warm mirror / Current hues): **Warm mirror**.

- Every neutral (paper, ink, muted, code, border, focus) uses one hue, warm 90°, in both appearances. Dark is the light scale with its lightness flipped, not a separately picked set. Values are OKLCH in `style.css`.
- Light is unchanged in practice: paper stays #fdfcf9, and the other neutrals keep their lightness and chroma. Only their hue moves.
- Dark paper keeps its lightness (L 0.25) and near-zero chroma; its hue moves from cool 197° to warm 90° (#202222 → #222220). `Color.paper` in `WindowChrome.swift` matches it.
- Dark muted text rises from L 0.713 to 0.79, so quotes, list markers, and Markdown syntax reach APCA Lc 60 on the paper and on code backgrounds (it was about 50).
- The accent stays teal (light `oklch(0.491 0.06 183.2)`, dark `oklch(0.789 0.054 175)`): a small amount of ink on warm paper.
- Rejected: **Current hues**: the neutrals drifted across 90–230°: warm paper, green-tinted muted, border and focus, blue-grey ink. That's no single family, and the tint was too uneven to read as an echo of the teal accent. **Paper-led** (light warm 91°, dark cool 197°, both papers untouched): consistent within each appearance, but dark became a different material from light rather than the same paper at night.

## Toolbar

Chosen from the toolbar prototype (Current / Native / Bare): **Bare**, now placed on the card.

- A plain 40pt row at the top of the card: no background, divider, or containers. There is no `NSToolbar`; the window title bar is transparent.
- The two clusters are drawn with the sidebar's own styles: icon buttons use `SidebarButtonStyle` (8pt continuous hover/selected tint, 32×28pt), and Compact/Reading uses `segmentTrack()` with 6pt inset segments, matching the Files/Outline tabs. Its segments are icons (`text.justify.left` for Compact, `book` for Reading), with the names in tooltips and accessibility labels.
- Order: sidebar and open on the left; document title centered; Compact/Reading, the Formatted/Source switch, then find on the right. Save has no button; it stays on ⌘S and the File menu. The bottom bar keeps only status and counts.
- Toggles show state: the sidebar, find, and source buttons take the selected tint while their mode is on.
- Rejected: **Current** (unified, 52pt, layout switch in the bottom bar) felt tall for a single-document editor. **Native** (compact with system segmented control) kept three heavy glass capsules side by side and pushed the title off-center.
- Trade-off accepted: icon buttons are 32×28pt, under the 40pt desktop hit-area guideline, in line with compact native toolbar buttons.

## Corner geometry

- One radius: 8pt, drawn continuous (`InterfaceMetrics.controlCornerRadius`, `RoundedRectangle.control`) for sidebar rows, icon tabs, toolbar buttons, find buttons, the find field, and the layout switch. These are all custom so they match; native windows and menus keep macOS shapes.
- Nested shapes are concentric: segmented choices (the sidebar's Files/Outline tabs and the Compact/Reading switch) share one style, with 6pt segments sitting 2pt inside an 8pt track.
- Editor blocks (code blocks, tables, diagrams) use the same 8px (`--radius-block`). Code blocks round only the start and end of the whole block; internal lines meet flush. Mermaid node boxes use 6px.
- Inline code uses 4px, repeated at wrapped fragments.
- WebKit does not support CSS `corner-shape` yet, so web corners are circular arcs. A `@supports` rule switches them to superellipse corners once it does.
- The main card is concentric with the window corner (`InterfaceMetrics.cardCornerRadius`, window radius minus the 6pt inset): 10pt from macOS 26.

## First-run onboarding

Chosen from the onboarding prototype (Welcome document / Welcome sheet / In-place hints): **In-place hints**, with a welcome screen added in front.

- Welcome screen, shown once (`welcomeSeen`): glass over the whole window with three things on it: "Welcome" in New York (the system serif, 104pt regular, −2 tracking), "A quiet place to write Markdown", and a Start Writing button (Return or Esc also start). The word sharpens in from a 12pt blur over 550ms, and the line and button follow 260ms and 350ms later. Start Writing clears the glass over 700ms on `cubic-bezier(0.23, 1, 0.32, 1)`, and the card settles from 98.5% to full size. With Reduce Motion on, every part becomes a plain fade.
- Hints: native popovers on the sidebar toggle, the Outline tab, Compact/Reading, Formatted/Source, and Find, in that order, shown one at a time. Each appears 900ms after the previous one closes, and only once its feature is reachable (Outline waits for the sidebar). Using a feature spends its hint. A click elsewhere dismisses it, and Turn Off Tips stops them all (`hintsSeen`, `hintsOff`).
- After the welcome screen, MarkUp.md opens the `Welcome.md` guide (unless it was launched to open a file). The guide is copied once to Application Support, so it's a real file the user owns: edits save normally, and it appears in Recents.
- Rejected: **Welcome document alone** (open `Welcome.md` on first launch, no other UI) never pointed at the toolbar. It survives as the step after the welcome screen. **Welcome sheet** (three paged cards) blocked the first sentence and described controls without showing where they are.
- Dropped from the prototype's welcome screen: Open a File and the shortcut line. One way forward keeps the moment quiet.

## Name

The app is called **MarkUp.md** (`CFBundleName` and `CFBundleDisplayName`; the bundle is `MarkUp.md.app`). The executable, the bundle identifier (`local.markup.editor`), saved preferences, and the repository keep `MarkUp`, so existing settings carry over.
