// Places each README screenshot on the light desktop wallpaper from the Figma file (Desktop — Sidebar open):
// a warm grey with blurred rose, lilac and blue washes. Reads docs/images/captures/<name>.png, writes docs/images/<name>.png.
// Usage: swift scripts/make-readme-images.swift
import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let captures = root.appendingPathComponent("docs/images/captures")
let output = root.appendingPathComponent("docs/images")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
/// The Figma desktop is 1440×960; washes are given in its coordinates (top-left origin) with a 90pt Gaussian blur.
let design = CGSize(width: 1440, height: 960)
let base = color(0xefecef)
let washes: [(rect: CGRect, color: CGColor)] = [
    (CGRect(x: 40, y: 280, width: 720, height: 560), color(0xf5c7d1, 0.75)),
    (CGRect(x: 820, y: 60, width: 560, height: 460), color(0xd1ccf2, 0.6)),
    (CGRect(x: 620, y: 600, width: 760, height: 420), color(0xa8c2eb, 0.6)),
]

func wallpaper(_ size: CGSize) -> CGImage {
    let scale = max(size.width / design.width, size.height / design.height)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Centered crop of the scaled design, flipped to its top-left origin.
    ctx.translateBy(x: (size.width - design.width * scale) / 2, y: size.height - (size.height - design.height * scale) / 2)
    ctx.scaleBy(x: scale, y: -scale)
    for wash in washes { ctx.setFillColor(wash.color); ctx.fillEllipse(in: wash.rect) }
    let shapes = CIImage(cgImage: ctx.makeImage()!)
    let blurred = shapes.clampedToExtent().applyingGaussianBlur(sigma: 90 * scale).cropped(to: shapes.extent)
    let ci = CIContext(options: [.workingColorSpace: space])
    let final = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    final.setFillColor(base); final.fill(CGRect(origin: .zero, size: size))
    final.draw(ci.createCGImage(blurred, from: shapes.extent)!, in: CGRect(origin: .zero, size: size))
    return final.makeImage()!
}

for name in ["screenshot", "welcome"] {
    let source = captures.appendingPathComponent("\(name).png")
    guard let window = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("missing \(source.path)\n".utf8)); exit(1)
    }
    // Room around the window for the wallpaper to read and its shadow to fall, in capture pixels (2x).
    let margin: CGFloat = 120
    let size = CGSize(width: CGFloat(window.width) + margin * 2, height: CGFloat(window.height) + margin * 2)
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(wallpaper(size), in: CGRect(origin: .zero, size: size))
    let frame = CGRect(x: margin, y: margin, width: CGFloat(window.width), height: CGFloat(window.height))
    // A macOS-like window shadow: wide and soft, plus a tight contact shadow.
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: color(0x000000, 0.22)); ctx.draw(window, in: frame); ctx.restoreGState()
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: color(0x000000, 0.12)); ctx.draw(window, in: frame); ctx.restoreGState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
    print("Wrote docs/images/\(name).png")
}
