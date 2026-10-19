// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
// 代替のアイコン「分割した 2 つの window」(app/macos/Resources/alternatives/split-windows/)を、CoreGraphics で描いて生成する。
// 既定のアイコンは、icon-from-image.swift が、元の画像(Resources/source/)から作る(docs/dev/release.md)。
// 使い方: swift app/macos/scripts/make-icon.swift [出力のディレクトリ]   (既定: app/macos/Resources/alternatives/split-windows)
//   → AppIcon.iconset/(各サイズの PNG)と AppIcon.icns を出力する。`iconutil` を使う(macOS 標準)。
// 意匠: 暗い角丸の板の上に、分割した 2 つの window(buffer)。左は文書(見出しと本文、選択した一節とカーソル)、
//       右は別の buffer(コードの断片)。各 window の下に、Emacs のようなモードライン。タブはない。
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app/macos/Resources/alternatives/split-windows"

// MARK: 色
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let accent: UInt32 = 0x3DDC97  // 選択・カーソル・見出し
let ink: UInt32 = 0x9AA4C8  // 本文の行
let paper: UInt32 = 0xF3F5FF  // window の地
let modeline: UInt32 = 0x1B2250

// MARK: 描画(1024 x 1024 の座標。上が y = 0)
func draw(_ ctx: CGContext) {
    func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    // 板(macOS の角丸。外側に 100 px の余白)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedRect(body, 184)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: rgb(0x000000, 0.35))
    fill(bodyPath, rgb(0x141A3A))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: space, colors: [rgb(0x2E3A8C), rgb(0x11163A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // 上端のうっすらとした光
    let sheen = CGGradient(
        colorsSpace: space, colors: [rgb(0xFFFFFF, 0.14), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
    ctx.restoreGState()

    // 1 つの window: 地・本文・モードライン
    func window(_ r: CGRect, content: (CGRect) -> Void) {
        let path = roundedRect(r, 30)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0x000000, 0.30))
        fill(path, rgb(paper))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        content(r)
        // モードライン(下)
        let bar = CGRect(x: r.minX, y: r.maxY - 46, width: r.width, height: 46)
        ctx.setFillColor(rgb(modeline))
        ctx.fill(bar)
        ctx.setFillColor(rgb(accent))
        ctx.fillEllipse(in: CGRect(x: bar.minX + 20, y: bar.midY - 7, width: 14, height: 14))
        fill(roundedRect(CGRect(x: bar.minX + 48, y: bar.midY - 5, width: min(120, r.width - 90), height: 10), 5), rgb(0x6C77B0))
        ctx.restoreGState()
    }
    func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, color: UInt32 = ink, alpha: CGFloat = 1, h: CGFloat = 16) {
        fill(roundedRect(CGRect(x: x, y: y, width: w, height: h), h / 2), rgb(color, alpha))
    }

    // 左の window: 文書(見出し・本文・選択・カーソル)
    window(CGRect(x: 196, y: 214, width: 360, height: 596)) { r in
        let x = r.minX + 36
        line(x, r.minY + 44, 190, color: accent, h: 30)  // 見出し
        for (i, w) in [270, 288, 244, 280].enumerated() { line(x, r.minY + 112 + CGFloat(i) * 38, CGFloat(w)) }
        line(x, r.minY + 292, 150, color: accent, h: 26)  // 小見出し
        // 選択した一節(ハイライト)と、カーソルのブロック
        let selection = CGRect(x: x - 10, y: r.minY + 350, width: 214, height: 34)
        fill(roundedRect(selection, 10), rgb(accent, 0.30))
        line(x, r.minY + 359, 196, color: 0x1B2250)
        fill(roundedRect(CGRect(x: x + 204, y: r.minY + 346, width: 22, height: 42), 4), rgb(accent))
        for (i, w) in [284, 232, 270].enumerated() { line(x, r.minY + 422 + CGFloat(i) * 38, CGFloat(w)) }
    }

    // 右の window: 別の buffer(コードの断片)
    window(CGRect(x: 584, y: 214, width: 244, height: 596)) { r in
        let x = r.minX + 28
        line(x, r.minY + 44, 120, color: accent, h: 28)
        for (i, w) in [170, 184, 140].enumerated() { line(x, r.minY + 108 + CGFloat(i) * 36, CGFloat(w)) }
        // コードブロック
        fill(roundedRect(CGRect(x: x - 8, y: r.minY + 236, width: r.width - 40, height: 176), 16), rgb(0x1B2250))
        let code: [(CGFloat, CGFloat, UInt32)] = [(0, 70, 0x3DDC97), (28, 110, 0x9AA4C8), (28, 84, 0xF2A65A), (0, 56, 0x3DDC97)]
        for (i, c) in code.enumerated() {
            line(x + 8 + c.0, r.minY + 262 + CGFloat(i) * 36, c.1, color: c.2, h: 14)
        }
        for (i, w) in [176, 150].enumerated() { line(x, r.minY + 446 + CGFloat(i) * 36, CGFloat(w)) }
    }
}

// MARK: 書き出し
func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)  // 上が y = 0
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
