import SwiftUI

/// 写日记的那张纸。
///
/// 纸色上有细细的纤维颗粒（Metal 着色器，Paper.metal）和一排排斜着印的淡淡厂标（App 自己的图形）。
/// 纸放在一张深一点的桌面上，边缘有一道细细的高光和一点投影，看得出是一张纸，不是一块底色。
/// 照片不再隔着纸透出来：纸是竖的、照片多是横的，透出来的只会是一张被拉成竖条的影子。照片放在纸的最上面，按原比例。
struct PhotoPaper: View {
    @Environment(\.colorScheme) private var scheme

    /// 纸到屏幕边缘。
    static let margin: CGFloat = 14
    /// 纸内的文字边距。
    static let inset: CGFloat = 22
    static let radius: CGFloat = 6

    /// 桌面：比纸深一层的暖灰；深色模式是黑。
    static let desk = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 1)
        : UIColor(red: 0.875, green: 0.865, blue: 0.845, alpha: 1) })

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack {
            // 深色模式下纸是深灰，不是和桌面一样的黑。
            (scheme == .dark ? Color(white: 0.11) : Color(.systemBackground))
                .colorEffect(ShaderLibrary.paperGrain(.float(scheme == .dark ? 0.03 : 0.035)))
            PaperWatermark()
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.75), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.14), radius: 18, y: 8)
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// 相纸背面一排排斜印的淡淡厂标：这里是 App 自己的拍立得图形，隔行错开，很淡。
private struct PaperWatermark: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let cell: CGFloat = 76
            let width: CGFloat = 12
            let height = width * MarkGeometry.aspect
            var path = Path()
            var row = 0
            var y: CGFloat = -cell
            while y < size.height + cell {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell / 2
                while x < size.width + cell {
                    let rect = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
                    let spin = CGAffineTransform(translationX: x, y: y).rotated(by: -0.32).translatedBy(x: -x, y: -y)
                    path.addPath(MarkPart.frame.path(in: rect).applying(spin))
                    path.addPath(MarkPart.photo.path(in: rect).applying(spin))
                    x += cell
                }
                y += cell
                row += 1
            }
            context.fill(path, with: .color(.primary.opacity(0.04)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}
