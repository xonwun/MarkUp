<p align="center">
  <img src="Assets/MarkUp-icon.png" width="128" height="128" alt="MarkUp app icon">
</p>

<h1 align="center">MarkUp</h1>

<p align="center">
  A calm, local Markdown editor for your Mac.<br>
  Write in plain text and watch it turn into clean formatting as you go.
</p>

<p align="center">
  <a href="https://github.com/xonwun/MarkUp/releases/latest"><strong>Download for macOS</strong></a>
  · macOS 14 or later · Apple silicon and Intel
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="760" alt="MarkUp showing a document with a heading, a formatted table, and a flow diagram, with the outline in the sidebar">
</p>

## Why MarkUp

Most Markdown apps make you choose between a raw text editor and a preview pane. MarkUp gives you one page: the line you're editing shows its Markdown, and everything else looks finished. Your files are ordinary `.md` files on your Mac, with no account, cloud service, or library to import into.

- **Formatting in place.** Headings, bold, lists, links and code look right as soon as you move off the line. Press ⇧⌘M any time to see the raw source.
- **Tables and diagrams.** Markdown tables and [Mermaid](https://mermaid.js.org) diagrams render right in the document. Click one to edit its source.
- **Your files, where you keep them.** Open any `.md` file from Finder. Recent files stay in the sidebar, and you can pin the ones you use most and drag to arrange them.
- **Two ways to write.** *Compact* for working notes, *Reading* for a centered, book-like column. Switch from the toolbar.
- **Find your place.** The Outline tab lists every heading so you can jump around long documents.
- **Careful with your work.** MarkUp reminds you about unsaved changes, saves safely, and warns you if another app changed the file.
- **Feels like a Mac app.** Light and dark mode, keyboard shortcuts, and English or Simplified Chinese.

## Install

1. Download **MarkUp-0.4.0.dmg** from the [latest release](https://github.com/xonwun/MarkUp/releases/latest).
2. Open it and drag **MarkUp** into **Applications**.
3. Open MarkUp.

**The first time you open it,** macOS may say it can't verify the developer. MarkUp is a free app that isn’t notarized by Apple yet. To open it anyway:

- Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the MarkUp message. You only need to do this once.

Prefer a zip? **MarkUp-0.4.0.zip** is on the same release page.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New / Open / Save | ⌘N / ⌘O / ⌘S |
| Save As | ⇧⌘S |
| Find | ⌘F |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Bold / Italic | ⌘B / ⌘I |
| Show or hide the sidebar | ⌃⌘S |
| Show Markdown source | ⇧⌘M |

## Good to know

- There's no autosave. Press ⌘S to save.
- Tables are edited as Markdown text; there's no spreadsheet-style table editor.
- Not included yet: images in the document, math, folders, multiple tabs, and sync.

## Build from source

Requires macOS 14+, Swift 6 (Xcode or the Command Line Tools), and Node.js 22+.

```sh
npm ci
./scripts/build-app.sh      # builds dist/MarkUp.app (universal)
./scripts/package.sh        # also makes dist/MarkUp-<version>.dmg and .zip
```

Local builds are ad-hoc signed and not notarized.

Built with SwiftUI, AppKit, WKWebView, ProseMirror, markdown-it, and Mermaid.

- `Sources/MarkUp/` — the native app: window, toolbar, sidebar
- `Editor/` — the editor (ProseMirror) and its styles
- `Assets/` — app icon
- `Tests/` — editor tests (`npm test`) and native smoke tests

More detail: [architecture](docs/Architecture.md), [design decisions](docs/Design-decisions.md), [testing](docs/Testing.md), and the [changelog](docs/CHANGELOG.md).
