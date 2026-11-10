import SwiftUI
import Photos

/// 一张正在显影的照片，和开屏的拍立得是同一套语言：先是一片乳白，暗部先浮出来、颜色是淡的，
/// 亮部最后褪去乳白，色彩和反差一起到位。
///
/// `active` 第一次为真、并且照片已经取到时开始显影；显影过的不再重来。
/// 动画只是这张照片自己的，翻页、点按都不等它。“减少动态效果”时照片直接出现（淡入）。
///
/// 每一帧用 Metal 着色器逐像素算（Developing.metal）：每个像素按自己的亮度决定什么时候显出来，
/// 药水的斑让整张有先后，刚出来时带颗粒。
struct DevelopingPhoto: View {
    let id: String
    var active = true
    var pointSize: CGSize
    private static let duration: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var developed: Double = 0

    var body: some View {
        MarkPalette.light.undeveloped
            .overlay {
                if let image {
                    DevelopingLayer(image: image, progress: developed, seed: Self.seed(for: id))
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .clipped()
            .task(id: id) {
                // 一年回顾里是整屏的卡片：放宽封顶，不然放大后发糊。
                let px = AssetImages.pixelSize(points: pointSize, scale: scale, cap: AssetImages.largePixels)
                for await img in AssetImages.shared.images(for: id, pixelSize: px, contentMode: .aspectFill, allowNetwork: true) {
                    image = img
                    develop()
                }
            }
            .onChange(of: active) { develop() }
            .accessibilityHidden(true)
    }

    /// 照片 id 的字节和，稳定（String 的 hashValue 每次启动都不同）。
    private static func seed(for id: String) -> Float {
        Float(id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 9973 }) / 97
    }

    private func develop() {
        guard active, image != nil, developed == 0 else { return }
        if reduceMotion {
            developed = 1
        } else {
            withAnimation(.timingCurve(0.3, 0, 0.25, 1, duration: Self.duration)) { developed = 1 }
        }
    }
}

/// 按进度画一帧：Animatable，动画的每一帧都把插值后的进度交给着色器。
private struct DevelopingLayer: View, Animatable {
    let image: UIImage
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let milk = MarkPalette.light.undeveloped

    /// 药水斑的种子：每张照片不一样，同一张每次一样。
    var seed: Float

    var body: some View {
        let photo = Image(uiImage: image).resizable().scaledToFill()
        if progress >= 1 {
            photo
        } else {
            let p = Float(progress)
            photo.visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.develop(
                    .float(p), .float2(proxy.size), .color(Self.milk), .float(seed)))
            }
        }
    }
}
