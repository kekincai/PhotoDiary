// 生成 App 图标：主题蓝底，一张微微左倾、正在显影的拍立得，白边上写着一行字（“日记写在照片上”）。
// 几何和 Shared/Design/Mark.swift 完全一致；改图形要两边一起改。
// 用法：swift Tools/AppIcon/make-icon.swift PhotoDiary/Assets.xcassets/AppIcon.appiconset [PhotoDiary/Assets.xcassets/LaunchMark.imageset] [PhotoDiaryWatch/Assets.xcassets/AppIcon.appiconset]
// 给了第二个目录时，同时生成启动画面中间的拍立得（显影前、还没写字的那一帧，透明底）；第三个目录是 Watch 图标。
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

// MARK: 几何（1024 画布，左上角为原点）

let tilt: CGFloat = -6 * .pi / 180
let frame = CGRect(x: 272, y: 213, width: 480, height: 598)
let frameRadius: CGFloat = 28
let photo = CGRect(x: 304, y: 245, width: 416, height: 416)
let photoRadius: CGFloat = 14
let sunCenter = CGPoint(x: 596, y: 378)
let sunRadius: CGFloat = 46
let backMountains = [
    CGPoint(x: 304, y: 661), CGPoint(x: 304, y: 575), CGPoint(x: 380, y: 494), CGPoint(x: 452, y: 556),
    CGPoint(x: 536, y: 470), CGPoint(x: 630, y: 566), CGPoint(x: 720, y: 520), CGPoint(x: 720, y: 661),
]
let frontMountains = [
    CGPoint(x: 304, y: 661), CGPoint(x: 304, y: 620), CGPoint(x: 410, y: 548), CGPoint(x: 500, y: 612),
    CGPoint(x: 574, y: 574), CGPoint(x: 660, y: 640), CGPoint(x: 720, y: 612), CGPoint(x: 720, y: 661),
]
let strokes: [(CGPoint, CGPoint, CGPoint)] = [
    (CGPoint(x: 342, y: 722), CGPoint(x: 460, y: 706), CGPoint(x: 586, y: 720)),
    (CGPoint(x: 342, y: 770), CGPoint(x: 410, y: 758), CGPoint(x: 478, y: 768)),
]
let strokeWidth: CGFloat = 17

struct Palette {
    var background: [CGColor]
    var frame: CGColor
    var undeveloped: CGColor
    var sky: [CGColor]
    var sun: CGColor
    var backMountain: CGColor
    var frontMountain: CGColor
    var ink: CGColor
    var shadow: Bool
}

let light = Palette(background: [rgb(0x3F86BD), rgb(0x2F6690)], frame: rgb(0xFFFFFF), undeveloped: rgb(0xE9E3D6),
                    sky: [rgb(0xFFE0B2), rgb(0xF4A867)], sun: rgb(0xFFC65C), backMountain: rgb(0x5AA98F),
                    frontMountain: rgb(0x2F7A68), ink: rgb(0x2F6690), shadow: true)
let dark = Palette(background: [rgb(0x1C2A36), rgb(0x0E151C)], frame: rgb(0xE6EBF0), undeveloped: rgb(0xD6D1C6),
                   sky: [rgb(0xF6CF9A), rgb(0xE48F52)], sun: rgb(0xF2B85B), backMountain: rgb(0x4F9C86),
                   frontMountain: rgb(0x2D6457), ink: rgb(0x2F6690), shadow: true)
// 着色图标：系统只用亮度，画成灰阶，白框亮、照片中灰、字和山更深。
let tinted = Palette(background: [rgb(0x000000), rgb(0x000000)], frame: rgb(0xFFFFFF), undeveloped: rgb(0xBEBEBE),
                     sky: [rgb(0xC9C9C9), rgb(0xA9A9A9)], sun: rgb(0xE6E6E6), backMountain: rgb(0x7A7A7A),
                     frontMountain: rgb(0x4E4E4E), ink: rgb(0x3A3A3A), shadow: false)

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: points)
    p.closeSubpath()
    return p
}

/// 画一张拍立得（在当前坐标系里，已经是左上角原点、1024 画布）。developed、written 是显影和写字的进度。
func drawMark(_ ctx: CGContext, _ p: Palette, developed: CGFloat = 1, written: CGFloat = 1) {
    ctx.saveGState()
    // 绕白框中心旋转。
    ctx.translateBy(x: frame.midX, y: frame.midY)
    ctx.rotate(by: tilt)
    ctx.translateBy(x: -frame.midX, y: -frame.midY)

    // 白框
    ctx.saveGState()
    if p.shadow { ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 44, color: rgb(0x0B2740, 0.38)) }
    ctx.addPath(roundedPath(frame, frameRadius))
    ctx.setFillColor(p.frame)
    ctx.fillPath()
    ctx.restoreGState()

    // 照片
    ctx.saveGState()
    ctx.addPath(roundedPath(photo, photoRadius))
    ctx.clip()
    let sky = CGGradient(colorsSpace: space, colors: p.sky as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: photo.minY), end: CGPoint(x: 0, y: photo.maxY), options: [])
    ctx.setFillColor(p.sun)
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))
    ctx.addPath(polygon(backMountains)); ctx.setFillColor(p.backMountain); ctx.fillPath()
    ctx.addPath(polygon(frontMountains)); ctx.setFillColor(p.frontMountain); ctx.fillPath()
    if developed < 1 {
        ctx.setFillColor(p.undeveloped.copy(alpha: 1 - developed)!)
        ctx.fill(photo)
    }
    ctx.restoreGState()

    // 白边上的字
    if written > 0 {
        ctx.setStrokeColor(p.ink)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)
        for (start, control, end) in strokes {
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            ctx.addPath(path)
        }
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func makeContext(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 翻转为左上角原点
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func write(_ ctx: CGContext, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func renderIcon(_ p: Palette, to file: String, directory: String = outDir) {
    let ctx = makeContext(width: Int(N), height: Int(N))
    let background = CGGradient(colorsSpace: space, colors: p.background as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: N), options: [])
    // 太阳背后一点暖光，让蓝底不那么平。
    if p.shadow {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFC65C, 0.22), rgb(0xFFC65C, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 300), startRadius: 0,
                               endCenter: CGPoint(x: 560, y: 300), endRadius: 520, options: [])
    }
    drawMark(ctx, p)
    write(ctx, to: URL(fileURLWithPath: directory).appending(path: file))
}

/// 系统生成启动画面快照时，把颜色分量当成 Display P3 用，画出来比原色艳。
/// 启动画面用的颜色先换成 P3 坐标再当 sRGB 存，快照里正好是原色。
/// 快照按版本号缓存：改了颜色要升 CURRENT_PROJECT_VERSION（模拟器上重启设备）才看得到。
/// LaunchBackground 颜色集也是这么算的：#2F6690 → (0.240, 0.395, 0.551)，#0E151C → (0.061, 0.082, 0.107)。
func launchCompensated(_ color: CGColor) -> CGColor {
    let p3 = color.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)!
    return CGColor(colorSpace: space, components: p3.components!)!
}

func compensated(_ p: Palette) -> Palette {
    var c = p
    c.frame = launchCompensated(p.frame)
    c.undeveloped = launchCompensated(p.undeveloped)
    c.sky = p.sky.map(launchCompensated)
    c.sun = launchCompensated(p.sun)
    c.backMountain = launchCompensated(p.backMountain)
    c.frontMountain = launchCompensated(p.frontMountain)
    c.ink = launchCompensated(p.ink)
    return c
}

/// 启动画面的拍立得：开场动画的第一帧（还没显影、还没写字），宽 88pt，透明底。
/// 画的是旋转后的外接矩形，中心就是白框中心，系统居中放时和动画里的位置一致。
func renderLaunchMark(_ p: Palette, scale: Int, to url: URL) {
    let points: CGFloat = 88
    let s = points * CGFloat(scale) / frame.width
    // 旋转后的外接矩形（再加阴影的余量）。
    let c = abs(cos(tilt)), sn = abs(sin(tilt))
    let rotatedW = frame.width * c + frame.height * sn, rotatedH = frame.width * sn + frame.height * c
    let margin: CGFloat = 140
    let w = Int(((rotatedW + margin) * s).rounded()), h = Int(((rotatedH + margin) * s).rounded())
    let ctx = makeContext(width: w, height: h)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: (rotatedW + margin) / 2 - frame.midX, y: (rotatedH + margin) / 2 - frame.midY)
    drawMark(ctx, compensated(p), developed: 0, written: 0)
    write(ctx, to: url)
}

renderIcon(light, to: "icon.png")
renderIcon(dark, to: "icon-dark.png")
renderIcon(tinted, to: "icon-tinted.png")
print("icons written to \(outDir)")

if CommandLine.arguments.count > 2 {
    let markDir = URL(fileURLWithPath: CommandLine.arguments[2])
    for scale in 1...3 {
        renderLaunchMark(light, scale: scale, to: markDir.appending(path: "mark@\(scale)x.png"))
        renderLaunchMark(dark, scale: scale, to: markDir.appending(path: "mark-dark@\(scale)x.png"))
    }
    print("launch mark written to \(markDir.path)")
}

if CommandLine.arguments.count > 3 {
    renderIcon(light, to: "icon.png", directory: CommandLine.arguments[3])
    print("watch icon written to \(CommandLine.arguments[3])")
}
