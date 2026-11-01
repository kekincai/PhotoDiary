import SwiftUI

// MARK: 品牌图形：书签上镂空出太阳和山（“写在照片上的日记”）
// 和 App 图标同一个图形（Tools/AppIcon/make-icon.swift），坐标是 1024 画布上的。
// iPhone 的开屏、权限页和 Apple Watch 都用它。

nonisolated enum MarkGeometry {
    static let bounds = CGRect(x: 322, y: 176, width: 380, height: 672)
    static var aspect: CGFloat { bounds.height / bounds.width }
    static let sunRect = CGRect(x: 548, y: 286, width: 92, height: 92)
    static var sunRadius: CGFloat { sunRect.width / 2 }
    /// 太阳中心在书签框里的位置（缩放锚点）。
    static var sunAnchor: UnitPoint {
        UnitPoint(x: (sunRect.midX - bounds.minX) / bounds.width, y: (sunRect.midY - bounds.minY) / bounds.height)
    }
    /// 太阳中心相对书签中心的偏移。
    static var sunCenter: CGPoint { CGPoint(x: sunRect.midX - bounds.midX, y: sunRect.midY - bounds.midY) }
    static let mountains: [CGPoint] = [
        CGPoint(x: 376, y: 590), CGPoint(x: 476, y: 432), CGPoint(x: 540, y: 520),
        CGPoint(x: 586, y: 466), CGPoint(x: 648, y: 590),
    ]

    static func bookmark(_ p: inout Path) {
        let left: CGFloat = 322, right: CGFloat = 702, top: CGFloat = 176, bottom: CGFloat = 848, notch: CGFloat = 132, r: CGFloat = 46
        p.move(to: CGPoint(x: left, y: top + r))
        p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
        p.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: (left + right) / 2, y: bottom - notch))
        p.addLine(to: CGPoint(x: left, y: bottom))
        p.closeSubpath()
    }
}

nonisolated enum MarkPart: Shape {
    case glyph, sun, mountains

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch self {
        case .glyph:
            MarkGeometry.bookmark(&p)
            p.addEllipse(in: MarkGeometry.sunRect)
            p.addLines(MarkGeometry.mountains)
            p.closeSubpath()
        case .sun:
            p.addEllipse(in: MarkGeometry.sunRect)
        case .mountains:
            p.addLines(MarkGeometry.mountains)
            p.closeSubpath()
        }
        let b = MarkGeometry.bounds
        let s = rect.width / b.width
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -b.minX, y: -b.minY))
    }
}

/// 图形的配色：浅色背景上是蓝底白书签，深色背景上书签是淡蓝。
struct MarkPalette {
    let background: Color
    let glyph: Color
    let sun: Color
    let mountains: LinearGradient
    let mountainEdge: Color

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let light = MarkPalette(
        background: rgb(0x2F6690),
        glyph: .white,
        sun: rgb(0xFFC65C),
        mountains: LinearGradient(colors: [rgb(0x8FD3B6), rgb(0x3E8F78)], startPoint: .top, endPoint: .bottom),
        mountainEdge: rgb(0x5FAF95))
    static let dark = MarkPalette(
        background: rgb(0x0E151C),
        glyph: rgb(0x8EC0E6),
        sun: rgb(0xF2B85B),
        mountains: LinearGradient(colors: [rgb(0x4F9C86), rgb(0x2D6457)], startPoint: .top, endPoint: .bottom),
        mountainEdge: rgb(0x3F8070))
}

/// 完整的书签：镂空下面垫着太阳和山。给定宽度，高度按比例。
struct BrandMark: View {
    var width: CGFloat = 64
    var palette: MarkPalette = .light

    var body: some View {
        ZStack {
            MarkPart.sun.fill(palette.sun)
            MarkPart.mountains.fill(palette.mountains).stroke(palette.mountainEdge, lineWidth: 1)
            MarkPart.glyph.fill(palette.glyph, style: FillStyle(eoFill: true))
        }
        .frame(width: width, height: width * MarkGeometry.aspect)
        .accessibilityHidden(true)
    }
}
