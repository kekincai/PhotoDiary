import SwiftUI

/// 相纸背面。写日记的那张纸。
///
/// 照片左右镜像铺满，稍微虚一点、褪一点色，再盖一层近乎不透明的纸色——像把一张照片翻过来对着光，
/// 正面的影子隐约透过来。纸上有细细的纤维颗粒，和相纸背面那种一排排斜着印的淡淡厂标（这里用 App 自己的图形）。
/// 纸放在一张深一点的桌面上，边缘有一道细细的高光和一点投影，看得出是一张纸，不是一块底色。
struct PhotoPaper: View {
    let assetID: String
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
            // 先把照片压成中间调：暗的照片透过纸也该是淡淡一层灰影，而不是把整张纸染灰。
            AssetImage(id: assetID, pointSize: CGSize(width: 360, height: 720))
                .scaleEffect(x: -1, y: 1)
                .saturation(0.6)
                .contrast(0.7)
                .brightness(scheme == .dark ? -0.05 : 0.25)
                .blur(radius: 2.5, opaque: true)
            // 深色模式下纸是深灰，不是和桌面一样的黑。
            (scheme == .dark ? Color(white: 0.11) : Color(.systemBackground)).opacity(scheme == .dark ? 0.86 : 0.85)
            PaperWatermark()
            PaperGrain()
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

/// 纸的颗粒：一小块随机灰噪点平铺，用叠加混合，只让纸面不那么平。
private struct PaperGrain: View {
    nonisolated static let tile: UIImage = {
        let side = 128
        var bytes = [UInt8](repeating: 128, count: side * side)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = UInt8.random(in: 92...164, using: &rng) }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }()

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(0.5)
            .blendMode(.overlay)
            .allowsHitTesting(false)
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
