// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
// From an existing icon image (.icns or .png; a dark rounded plate filling the whole image), builds a standard macOS
// icon (transparent outside the corners, about 10% margin around, with a shadow). The design itself is not changed.
// Usage: swift app/macos/scripts/icon-from-image.swift <input .icns / .png> <output directory>
//   → <output>/AppIcon.icns and <output>/AppIcon-1024.png
// Steps: from pixel brightness, find the bounding box of the dark plate and the corner radius. Cut out only the plate
// area,
//       clip with a slightly larger corner radius (so the outer background does not bleed in) and place it in the
// margin.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: icon-from-image.swift <input .icns|.png> <output dir>\n".utf8))
    exit(2)
}
let inputPath = args[1]
let outDir = args[2]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: Input (the largest image)
guard let image = NSImage(contentsOfFile: inputPath),
    let best = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
    let source = best.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("Cannot read the image: \(inputPath)\n".utf8))
    exit(1)
}
let width = source.width
let height = source.height

// MARK: Plate area and corner radius (from dark pixels)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let probe = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
probe.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
func luminance(_ x: Int, _ y: Int) -> Double {
    let i = (y * width + x) * 4
    return (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
}
let dark = 0.35  // brightness separating the plate (dark) from the outer background (light)
var minX = width, maxX = 0, minY = height, maxY = 0
for y in 0..<height {
    for x in 0..<width where luminance(x, y) < dark {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
    }
}
let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
// Corner radius: found from where dark pixels start on the 2nd row from the top (shifts inward with rounded corners)
var left = box.width
let rowY = Int(box.minY) + 2
for x in Int(box.minX)..<Int(box.maxX) where luminance(x, rowY) < dark {
    left = CGFloat(x) - box.minX
    break
}
var radius = (left * left + 2 * left * 2 + 0) / 1  // solved later (the search below)
// Solve r - sqrt(4r - 4) = left numerically
var solved: CGFloat = 8
for candidate in stride(from: CGFloat(8), through: box.width / 2, by: 0.5) {
    if candidate - (4 * candidate - 4).squareRoot() >= left {
        solved = candidate
        break
    }
}
radius = solved
// Cut with a slightly larger radius and a 1 px inward bite so the outer background does not bleed into the edge
let inset: CGFloat = 1.5
let clipRadius = radius * 1.06
print(String(format: "Plate bounds: %.0f,%.0f %.0fx%.0f / corner radius (estimated): %.0f", box.minX, box.minY, box.width, box.height, radius))
guard let cropped = source.cropping(to: box.insetBy(dx: inset, dy: inset)) else { exit(1) }

// MARK: Drawing (1024 coordinates; y = 0 at the top)
func draw(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(
        roundedRect: body, cornerWidth: clipRadius * 824 / box.width, cornerHeight: clipRadius * 824 / box.width,
        transform: nil)
    // Shadow (in the plate's shape)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.08, blue: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    // The plate image (the cut-out part, filling the whole plate area)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // The coordinate system is flipped vertically, so correct the image orientation when drawing
    ctx.translateBy(x: body.minX, y: body.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: body.width, height: body.height))
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
print("Generated \(outDir)/AppIcon.icns")
