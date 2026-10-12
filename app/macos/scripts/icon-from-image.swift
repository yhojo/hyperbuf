// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
// 既存のアイコン画像(.icns または .png。暗い角丸の板が、画像いっぱいに広がったもの)から、macOS の標準の
// アイコン(角の外側は透明、周囲に約 10% の余白、影つき)を作る。デザインそのものは、変えない。
// 使い方: swift app/macos/scripts/icon-from-image.swift <入力の .icns / .png> <出力のディレクトリ>
//   → <出力>/AppIcon.icns と <出力>/AppIcon-1024.png
// 手順: 画像から、暗い板の範囲(bounding box)と、角の半径を、画素の明るさから求める。板の範囲だけを切り出し、
//       少し大きめの半径の角丸でクリップ(外側の地の色が、縁に混ざらない)して、余白の中に置く。
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

// MARK: 入力(最も大きな画像)
guard let image = NSImage(contentsOfFile: inputPath),
    let best = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
    let source = best.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("画像を読めません: \(inputPath)\n".utf8))
    exit(1)
}
let width = source.width
let height = source.height

// MARK: 板の範囲と角の半径(暗い画素から)
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
let dark = 0.35  // 板(暗い)と、外側の地(明るい)を分ける明るさ
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
// 角の半径: 上端から 2 行目で、暗い画素が始まる位置(角丸なら、半径に応じて内側にずれる)から求める
var left = box.width
let rowY = Int(box.minY) + 2
for x in Int(box.minX)..<Int(box.maxX) where luminance(x, rowY) < dark {
    left = CGFloat(x) - box.minX
    break
}
var radius = (left * left + 2 * left * 2 + 0) / 1  // 後で解く(下の探索)
// r - sqrt(4r - 4) = left を、数値で解く
var solved: CGFloat = 8
for candidate in stride(from: CGFloat(8), through: box.width / 2, by: 0.5) {
    if candidate - (4 * candidate - 4).squareRoot() >= left {
        solved = candidate
        break
    }
}
radius = solved
// 縁に、外側の地の色が混ざらないよう、少し大きめの半径と、1 px の内側への食い込みで切る
let inset: CGFloat = 1.5
let clipRadius = radius * 1.06
print(String(format: "板の範囲: %.0f,%.0f %.0fx%.0f / 角の半径(推定): %.0f", box.minX, box.minY, box.width, box.height, radius))
guard let cropped = source.cropping(to: box.insetBy(dx: inset, dy: inset)) else { exit(1) }

// MARK: 描画(1024 座標。上が y = 0)
func draw(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(
        roundedRect: body, cornerWidth: clipRadius * 824 / box.width, cornerHeight: clipRadius * 824 / box.width,
        transform: nil)
    // 影(板の形で)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.08, blue: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    // 板の絵(切り出した部分を、板の範囲いっぱいに)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // 座標系が上下反転しているので、画像の向きを直して描く
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
print("\(outDir)/AppIcon.icns を生成しました")
