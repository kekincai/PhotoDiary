// 生成 App 图标：主题蓝底 + 白色书签，书签上镂空出山和太阳（“写在照片上的日记”）。
// 用法：swift Tools/AppIcon/make-icon.swift PhotoDiary/Assets.xcassets/AppIcon.appiconset [PhotoDiary/Assets.xcassets/LaunchMark.imageset]
// 给了第二个目录时，同时生成启动画面中间的书签（和图标同一个图形，透明底）。
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let N: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// 书签外形（左上角为原点）。
func bookmark() -> CGPath {
    let p = CGMutablePath()
    let left: CGFloat = 322, right: CGFloat = 702, top: CGFloat = 176, bottom: CGFloat = 848, notch: CGFloat = 132, r: CGFloat = 46
    p.move(to: CGPoint(x: left, y: top + r))
    p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
    p.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top + r), radius: r)
    p.addLine(to: CGPoint(x: right, y: bottom))
    p.addLine(to: CGPoint(x: (left + right) / 2, y: bottom - notch))
    p.addLine(to: CGPoint(x: left, y: bottom))
    p.closeSubpath()
    return p
}

/// 镂空：太阳 + 两座山（底边平直，像一张照片的下沿）。
func cutout() -> CGPath {
    let p = CGMutablePath()
    p.addEllipse(in: CGRect(x: 548, y: 286, width: 92, height: 92))
    p.move(to: CGPoint(x: 376, y: 590))
    p.addLine(to: CGPoint(x: 476, y: 432))
    p.addLine(to: CGPoint(x: 540, y: 520))
    p.addLine(to: CGPoint(x: 586, y: 466))
    p.addLine(to: CGPoint(x: 648, y: 590))
    p.closeSubpath()
    return p
}

enum Variant { case light, dark, tinted }

func render(_ variant: Variant, to file: String) {
    let ctx = CGContext(data: nil, width: Int(N), height: Int(N), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 翻转为左上角原点
    ctx.translateBy(x: 0, y: N)
    ctx.scaleBy(x: 1, y: -1)

    let background: CGGradient
    let glyph: CGColor
    switch variant {
    case .light:
        background = CGGradient(colorsSpace: space, colors: [rgb(0x3F86BD), rgb(0x2F6690)] as CFArray, locations: [0, 1])!
        glyph = rgb(0xFFFFFF)
    case .dark:
        background = CGGradient(colorsSpace: space, colors: [rgb(0x1C2A36), rgb(0x0E151C)] as CFArray, locations: [0, 1])!
        glyph = rgb(0x8EC0E6)
    case .tinted:
        background = CGGradient(colorsSpace: space, colors: [rgb(0x000000), rgb(0x000000)] as CFArray, locations: [0, 1])!
        glyph = rgb(0xFFFFFF)
    }

    ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: N), options: [])

    // 书签减去镂空（奇偶填充）
    let shape = CGMutablePath()
    shape.addPath(bookmark())
    shape.addPath(cutout())
    ctx.saveGState()
    if variant == .light {
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 36, color: rgb(0x0B2740, 0.35))
    }
    ctx.addPath(shape)
    ctx.setFillColor(glyph)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    let url = URL(fileURLWithPath: outDir).appending(path: file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

/// 启动画面的书签：只画图形本身，宽 64pt，背景色由 LaunchBackground 提供。
func renderMark(dark: Bool, scale: Int, to url: URL) {
    let bounds = bookmark().boundingBox
    let points: CGFloat = 64
    let s = points * CGFloat(scale) / bounds.width
    let w = Int((bounds.width * s).rounded()), h = Int((bounds.height * s).rounded())
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: s, y: -s)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    let shape = CGMutablePath()
    shape.addPath(bookmark())
    shape.addPath(cutout())
    ctx.addPath(shape)
    ctx.setFillColor(dark ? rgb(0x8EC0E6) : rgb(0xFFFFFF))
    ctx.fillPath(using: .evenOdd)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

render(.light, to: "icon.png")
render(.dark, to: "icon-dark.png")
render(.tinted, to: "icon-tinted.png")
print("icons written to \(outDir)")

if CommandLine.arguments.count > 2 {
    let markDir = URL(fileURLWithPath: CommandLine.arguments[2])
    for scale in 1...3 {
        renderMark(dark: false, scale: scale, to: markDir.appending(path: "mark@\(scale)x.png"))
        renderMark(dark: true, scale: scale, to: markDir.appending(path: "mark-dark@\(scale)x.png"))
    }
    print("launch mark written to \(markDir.path)")
}
