// Draws the installer window background from the Figma "dmg installer" frame: on paper, a card with a teal rim
// inset 24pt from the window edge, a stage where Finder shows the app and the Applications folder with an arrow
// between, then the instruction and the first-open note.
// Writes background.png (660×464) and background@2x.png (1320×928) into the given folder.
// Usage: swift scripts/make-dmg-background.swift <output folder>
import AppKit

// Drawn at half the Figma size (1320×927 at 2x): a 24pt margin around a 612×416 card.
let size = NSSize(width: 660, height: 464)
let card = NSRect(x: 24, y: 24, width: 612, height: 416)
/// Icon centers, in window coordinates (origin top-left). package.sh positions the Finder icons at the same points.
let appCenter = CGPoint(x: 194, y: 187)
let folderCenter = CGPoint(x: 466, y: 187)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
let paper = color(0xfcfcf9), teal = color(0x3f5958)

func serif(_ pointSize: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: .regular)
    return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? base
}

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size   // points, so the 2x image carries 144 dpi
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    let cg = context.cgContext
    // Draw with a top-left origin, like Finder's window coordinates.
    cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    paper.setFill(); NSRect(origin: .zero, size: size).fill()
    // Rim: 3pt, with the paper inset by it and its corner concentric (20pt outer, 17pt inner).
    teal.setFill(); NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20).fill()
    let inner = card.insetBy(dx: 3, dy: 3)
    paper.setFill(); NSBezierPath(roundedRect: inner, xRadius: 17, yRadius: 17).fill()

    // Arrow from the app to the folder: a round-capped line with an open chevron head, in the rim color.
    let y = appCenter.y - 4
    let from = (appCenter.x + folderCenter.x) / 2 - 42, to = from + 84
    teal.setStroke()
    for points in [[NSPoint(x: from, y: y), NSPoint(x: to, y: y)], [NSPoint(x: to - 15, y: y - 15), NSPoint(x: to, y: y), NSPoint(x: to - 15, y: y + 15)]] {
        let path = NSBezierPath(); path.lineWidth = 5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }; path.stroke()
    }

    // Stage (320pt), then the 2pt divider in the rim color.
    let stageBottom = inner.minY + 320
    teal.setFill(); NSRect(x: inner.minX, y: stageBottom, width: inner.width, height: 2).fill()

    // Title, in the welcome screen's serif rather than the card's SF Pro.
    let title = NSAttributedString(string: "Drag MarkUp.md to Applications", attributes: [.font: serif(23), .foregroundColor: teal])
    title.draw(at: NSPoint(x: inner.minX + 31, y: stageBottom + 2 + 10))

    // Hairline rule, then the first-open note.
    let ruleY = stageBottom + 2 + 46.5
    color(0x000000, 0.15).setFill(); NSRect(x: inner.minX, y: ruleY, width: inner.width, height: 0.5).fill()
    // 11.5pt semibold in the card; stepped down until it fits between the side margins.
    let noteText = "First time opening? macOS asks for approval: System Settings → Privacy & Security → Open Anyway."
    var noteSize: CGFloat = 11.5
    var note: NSAttributedString
    repeat {
        note = NSAttributedString(string: noteText, attributes: [.font: NSFont.systemFont(ofSize: noteSize, weight: .semibold), .foregroundColor: teal])
        noteSize -= 0.25
    } while note.size().width > inner.width - 62 && noteSize > 9
    note.draw(at: NSPoint(x: inner.minX + 31, y: ruleY + 12))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background <output folder>\n".utf8)); exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try render(scale: 1).write(to: folder.appendingPathComponent("background.png"))
try render(scale: 2).write(to: folder.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png in \(folder.path)")
