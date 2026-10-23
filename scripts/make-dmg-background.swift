// Draws the installer window background: two raised pads (the app, the Applications folder) with an arrow between
// them. Writes background.png (660×400) and background@2x.png (1320×800) into the given folder.
// Usage: swift scripts/make-dmg-background.swift <output folder>
import AppKit

let size = NSSize(width: 660, height: 400)
/// Icon centers, in window coordinates (origin top-left). package.sh positions the Finder icons at the same points.
let appCenter = CGPoint(x: 170, y: 196)
let folderCenter = CGPoint(x: 490, y: 196)

// The editor's neutrals (Editor/style.css, light): one warm hue, with the accent teal for the arrow.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
let paper = color(0xfdfcf9), pad = color(0xf7f5f0), ink = color(0x2f2e2c), muted = color(0x75726c), accent = color(0x3b6b66)

func serif(_ pointSize: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: .regular)
    return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? base
}

func text(_ string: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: string, attributes: attributes)
    let w = s.size().width
    s.draw(at: NSPoint(x: centerX - w / 2, y: top))
}

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size   // points, so the 2x image carries 144 dpi
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    // Draw with a top-left origin, like Finder's window coordinates.
    cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped

    paper.setFill(); NSRect(origin: .zero, size: size).fill()

    // Pads: a ring in place of a border, and a soft lift, with the card's concentric corner logic (24pt outer).
    for center in [appCenter, folderCenter] {
        let rect = CGRect(x: center.x - 100, y: center.y - 104, width: 200, height: 208)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.06).cgColor)
        pad.setFill(); shape.fill()
        cg.restoreGState()
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -1), blur: 1.5, color: NSColor.black.withAlphaComponent(0.05).cgColor)
        pad.setFill(); shape.fill()
        cg.restoreGState()
        NSColor.black.withAlphaComponent(0.06).setStroke()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 24.5, yRadius: 24.5)
        ring.lineWidth = 1; ring.stroke()
    }

    // Arrow: a round-capped line with an open chevron head, in the accent.
    let y = appCenter.y - 4
    let from: CGFloat = 288, to: CGFloat = 372
    accent.setStroke()
    let line = NSBezierPath(); line.lineWidth = 5; line.lineCapStyle = .round; line.lineJoinStyle = .round
    line.move(to: NSPoint(x: from, y: y)); line.line(to: NSPoint(x: to, y: y)); line.stroke()
    let head = NSBezierPath(); head.lineWidth = 5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.move(to: NSPoint(x: to - 15, y: y - 15)); head.line(to: NSPoint(x: to, y: y)); head.line(to: NSPoint(x: to - 15, y: y + 15)); head.stroke()

    text("Drag MarkUp.md to Applications", font: serif(26), color: ink, centerX: size.width / 2, top: 34)
    text("First time opening? macOS asks for approval: System Settings → Privacy & Security → Open Anyway.", font: .systemFont(ofSize: 12), color: muted, centerX: size.width / 2, top: 356)

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
