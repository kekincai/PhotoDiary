import SwiftUI

// MARK: 品牌图形：一张正在显影的拍立得，白边上写着一行字（“日记写在照片上”）
//
// 和 App 图标同一个图形（Tools/AppIcon/make-icon.swift），坐标是 1024 画布上的。
// iPhone 的开屏、首次读取的进度卡片、权限页和 Apple Watch 都用它。
// 图形有两个“进度”：照片显影（0 = 一片乳白，1 = 完整的画面）和白边上的字写到哪里（0…1）。

nonisolated enum MarkGeometry {
    static let canvas: CGFloat = 1024
    /// 整张拍立得微微左倾。
    static let tilt: Angle = .degrees(-6)

    /// 白框（未旋转）。
    static let frame = CGRect(x: 272, y: 213, width: 480, height: 598)
    static let frameRadius: CGFloat = 28
    static var aspect: CGFloat { frame.height / frame.width }

    /// 照片区域：正方形，上下左右留 32 的白边，下面的白边更宽，是写字的地方。
    static let photo = CGRect(x: 304, y: 245, width: 416, height: 416)
    static let photoRadius: CGFloat = 14

    static let sunCenter = CGPoint(x: 596, y: 378)
    static let sunRadius: CGFloat = 46
    /// 太阳中心在白框里的位置（缩放锚点）。
    static var sunAnchor: UnitPoint {
        UnitPoint(x: (sunCenter.x - frame.minX) / frame.width, y: (sunCenter.y - frame.minY) / frame.height)
    }
    /// 照片区域中心在白框里的位置（退场时放大的锚点）。
    static var photoAnchor: UnitPoint {
        UnitPoint(x: (photo.midX - frame.minX) / frame.width, y: (photo.midY - frame.minY) / frame.height)
    }

    /// 两重山，沿照片下沿铺开。
    static let backMountains: [CGPoint] = [
        CGPoint(x: 304, y: 661), CGPoint(x: 304, y: 575), CGPoint(x: 380, y: 494), CGPoint(x: 452, y: 556),
        CGPoint(x: 536, y: 470), CGPoint(x: 630, y: 566), CGPoint(x: 720, y: 520), CGPoint(x: 720, y: 661),
    ]
    static let frontMountains: [CGPoint] = [
        CGPoint(x: 304, y: 661), CGPoint(x: 304, y: 620), CGPoint(x: 410, y: 548), CGPoint(x: 500, y: 612),
        CGPoint(x: 574, y: 574), CGPoint(x: 660, y: 640), CGPoint(x: 720, y: 612), CGPoint(x: 720, y: 661),
    ]

    /// 白边上的两笔：一长一短，微微上弧，像随手写的一行。
    struct Stroke {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint
    }
    static let strokes: [Stroke] = [
        Stroke(start: CGPoint(x: 342, y: 722), control: CGPoint(x: 460, y: 706), end: CGPoint(x: 586, y: 720)),
        Stroke(start: CGPoint(x: 342, y: 770), control: CGPoint(x: 410, y: 758), end: CGPoint(x: 478, y: 768)),
    ]
    static let strokeWidth: CGFloat = 17

    /// 把 1024 画布上白框内的坐标映射到给定矩形。
    static func transform(to rect: CGRect) -> CGAffineTransform {
        let s = rect.width / frame.width
        return CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -frame.minX, y: -frame.minY)
    }
}

/// 图形的各个部分，都以白框为外接矩形。
nonisolated enum MarkPart: Shape {
    case frame, photo, sun, backMountains, frontMountains, strokes

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let g = MarkGeometry.self
        switch self {
        case .frame:
            p.addRoundedRect(in: g.frame, cornerSize: CGSize(width: g.frameRadius, height: g.frameRadius), style: .continuous)
        case .photo:
            p.addRoundedRect(in: g.photo, cornerSize: CGSize(width: g.photoRadius, height: g.photoRadius), style: .continuous)
        case .sun:
            p.addEllipse(in: CGRect(x: g.sunCenter.x - g.sunRadius, y: g.sunCenter.y - g.sunRadius,
                                    width: g.sunRadius * 2, height: g.sunRadius * 2))
        case .backMountains:
            p.addLines(g.backMountains)
            p.closeSubpath()
        case .frontMountains:
            p.addLines(g.frontMountains)
            p.closeSubpath()
        case .strokes:
            for stroke in g.strokes {
                p.move(to: stroke.start)
                p.addQuadCurve(to: stroke.end, control: stroke.control)
            }
        }
        return p.applying(g.transform(to: rect))
    }
}

/// 图形的配色：浅色背景上是蓝底白框，深色背景上白框略暗。
struct MarkPalette {
    let background: Color
    let frame: Color
    /// 还没显影的照片：乳白。
    let undeveloped: Color
    let skyTop: Color
    let skyBottom: Color
    let sun: Color
    let backMountain: Color
    let frontMountain: Color
    let ink: Color

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let light = MarkPalette(
        background: rgb(0x2F6690),
        frame: .white,
        undeveloped: rgb(0xE9E3D6),
        skyTop: rgb(0xFFE0B2),
        skyBottom: rgb(0xF4A867),
        sun: rgb(0xFFC65C),
        backMountain: rgb(0x5AA98F),
        frontMountain: rgb(0x2F7A68),
        ink: rgb(0x2F6690))
    static let dark = MarkPalette(
        background: rgb(0x0E151C),
        frame: rgb(0xE6EBF0),
        undeveloped: rgb(0xD6D1C6),
        skyTop: rgb(0xF6CF9A),
        skyBottom: rgb(0xE48F52),
        sun: rgb(0xF2B85B),
        backMountain: rgb(0x4F9C86),
        frontMountain: rgb(0x2D6457),
        ink: rgb(0x2F6690))
}

/// 完整的拍立得。给定宽度，高度按比例；`developed` 是显影进度，`written` 是写字进度。
struct BrandMark: View {
    var width: CGFloat = 88
    var palette: MarkPalette = .light
    var developed: Double = 1
    var written: Double = 1
    var tilted = true
    var shadow = true

    var body: some View {
        ZStack {
            MarkPart.frame
                .fill(palette.frame)
                .shadow(color: .black.opacity(shadow ? 0.22 : 0), radius: width * 0.1, y: width * 0.06)
            ZStack {
                LinearGradient(colors: [palette.skyTop, palette.skyBottom], startPoint: .top, endPoint: .bottom)
                MarkPart.sun.fill(palette.sun)
                MarkPart.backMountains.fill(palette.backMountain)
                MarkPart.frontMountains.fill(palette.frontMountain)
                // 显影：乳白一层慢慢褪掉（用视图的 opacity，才能做动画）。
                Rectangle().fill(palette.undeveloped).opacity(1 - developed)
            }
            .clipShape(MarkPart.photo)
            MarkPart.strokes
                .trim(from: 0, to: written)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: width * MarkGeometry.strokeWidth / MarkGeometry.frame.width,
                                                        lineCap: .round))
        }
        .frame(width: width, height: width * MarkGeometry.aspect)
        .rotationEffect(tilted ? MarkGeometry.tilt : .zero)
        .accessibilityHidden(true)
    }
}
