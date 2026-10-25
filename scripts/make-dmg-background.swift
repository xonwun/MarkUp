// Draws the installer window background from the Figma "Resource card": a paper card with a teal rim, an open
// stage where Finder shows the app and the Applications folder, then the instruction and the first-open note.
// Writes background.png (612×416) and background@2x.png (1224×832) into the given folder.
// Usage: swift scripts/make-dmg-background.swift <output folder>
import AppKit

// The card is drawn at half its Figma size (1224×831 at 2x).
let size = NSSize(width: 612, height: 416)
/// Icon centers, in window coordinates (origin top-left). package.sh positions the Finder icons at the same points.
let appCenter = CGPoint(x: 170, y: 160)
let folderCenter = CGPoint(x: 442, y: 160)

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

    // Behind the card's rounded corners, the window's own corners show the rim color.
    teal.setFill(); NSRect(origin: .zero, size: size).fill()
    // Rim: 3pt, with the paper inset by it and its corner concentric (20pt outer, 17pt inner).
    let inner = NSRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
    paper.setFill(); NSBezierPath(roundedRect: inner, xRadius: 17, yRadius: 17).fill()

    // Stage (320pt), then the 2pt divider in the rim color.
    let stageBottom: CGFloat = 3 + 320
    teal.setFill(); NSRect(x: 3, y: stageBottom, width: inner.width, height: 2).fill()

    // Title, in the welcome screen's serif rather than the card's SF Pro.
    let title = NSAttributedString(string: "Drag MarkUp.md to Applications", attributes: [.font: serif(23), .foregroundColor: teal])
    title.draw(at: NSPoint(x: 3 + 31, y: stageBottom + 2 + 10))

    // Hairline rule, then the first-open note.
    let ruleY = stageBottom + 2 + 46.5
    color(0x000000, 0.15).setFill(); NSRect(x: 3, y: ruleY, width: inner.width, height: 0.5).fill()
    // 11.5pt semibold in the card; stepped down until it fits between the side margins.
    let noteText = "First time opening? macOS asks for approval: System Settings → Privacy & Security → Open Anyway."
    var noteSize: CGFloat = 11.5
    var note: NSAttributedString
    repeat {
        note = NSAttributedString(string: noteText, attributes: [.font: NSFont.systemFont(ofSize: noteSize, weight: .semibold), .foregroundColor: teal])
        noteSize -= 0.25
    } while note.size().width > inner.width - 62 && noteSize > 9
    note.draw(at: NSPoint(x: 3 + 31, y: ruleY + 12))

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
