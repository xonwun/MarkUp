// Recolors the teal "M↑" emblem of the app icon to blue, so a development build is easy to tell from the release.
// Usage: swift scripts/make-dev-icon.swift Assets/MarkUp-icon.png Assets/MarkUp-icon-dev.png
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("usage: make-dev-icon <in.png> <out.png>\n".utf8)); exit(1)
}

let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue
pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}

/// Teal sits near 175°; blue near 215°. Only saturated pixels move, so the ivory tile and paper stay put.
let tealRange: ClosedRange<Double> = 140...205
let hueShift = 38.0

for i in stride(from: 0, to: pixels.count, by: 4) {
    let a = Double(pixels[i + 3]) / 255
    guard a > 0 else { continue }
    // Unpremultiply, convert to HSV.
    let r = min(1, Double(pixels[i]) / 255 / a), g = min(1, Double(pixels[i + 1]) / 255 / a), b = min(1, Double(pixels[i + 2]) / 255 / a)
    let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
    guard delta > 0 else { continue }
    var h: Double
    if maxC == r { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
    else if maxC == g { h = 60 * ((b - r) / delta + 2) }
    else { h = 60 * ((r - g) / delta + 4) }
    if h < 0 { h += 360 }
    var s = delta / maxC, v = maxC
    guard tealRange.contains(h), s > 0.1 else { continue }
    // Weight by saturation so anti-aliased edges blend instead of fringing.
    let weight = min(1, (s - 0.1) / 0.3)
    h += hueShift * weight
    s = min(0.9, s * (1 + 0.5 * weight))
    v = min(1, v * (1 + 0.85 * weight))
    // HSV back to RGB.
    let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
    let (r1, g1, b1): (Double, Double, Double)
    switch h {
    case ..<60: (r1, g1, b1) = (c, x, 0)
    case ..<120: (r1, g1, b1) = (x, c, 0)
    case ..<180: (r1, g1, b1) = (0, c, x)
    case ..<240: (r1, g1, b1) = (0, x, c)
    case ..<300: (r1, g1, b1) = (x, 0, c)
    default: (r1, g1, b1) = (c, 0, x)
    }
    pixels[i] = UInt8(((r1 + m) * a * 255).rounded())
    pixels[i + 1] = UInt8(((g1 + m) * a * 255).rounded())
    pixels[i + 2] = UInt8(((b1 + m) * a * 255).rounded())
}

let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
    CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!.makeImage()
}
guard let output,
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("Wrote \(args[2])")
