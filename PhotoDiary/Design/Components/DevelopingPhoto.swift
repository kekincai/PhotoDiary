import SwiftUI
import Photos

/// 一张正在显影的照片，和开屏的拍立得是同一套语言：先是一片乳白，暗部先浮出来、颜色是淡的，
/// 亮部最后褪去乳白，色彩和反差一起到位。
///
/// `active` 第一次为真、并且照片已经取到时开始显影；显影过的不再重来。
/// 动画只是这张照片自己的，翻页、点按都不等它。“减少动态效果”时照片直接出现（淡入）。
///
/// 没用 Metal 着色器：工程里没有 .metal 文件，命令行构建机也没装 Metal 工具链。
/// 这里用 SwiftUI 自带的饱和度、对比度和“亮度转透明度”遮罩，按显影进度逐帧算。
struct DevelopingPhoto: View {
    let id: String
    var active = true
    var pointSize: CGSize
    var duration: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var developed: Double = 0

    var body: some View {
        MarkPalette.light.undeveloped
            .overlay {
                if let image {
                    DevelopingLayer(image: image, progress: developed)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .clipped()
            .task(id: id) {
                let px = AssetImages.pixelSize(points: pointSize, scale: scale)
                for await img in AssetImages.shared.images(for: id, pixelSize: px, contentMode: .aspectFill, allowNetwork: true) {
                    image = img
                    develop()
                }
            }
            .onChange(of: active) { develop() }
            .accessibilityHidden(true)
    }

    private func develop() {
        guard active, image != nil, developed == 0 else { return }
        if reduceMotion {
            developed = 1
        } else {
            withAnimation(.timingCurve(0.3, 0, 0.25, 1, duration: duration)) { developed = 1 }
        }
    }
}

/// 按进度画一帧：Animatable，动画的每一帧都用插值后的进度重算各层，才能分出先后。
private struct DevelopingLayer: View, Animatable {
    let image: UIImage
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let milk = MarkPalette.light.undeveloped

    var body: some View {
        let photo = Image(uiImage: image).resizable().scaledToFill()
        if progress >= 1 {
            photo
        } else {
            let p = progress
            photo
                .saturation(0.1 + 0.9 * Self.ramp(p, 0.35, 1))
                .contrast(0.55 + 0.45 * Self.ramp(p, 0.2, 0.95))
                // 刚浮出来时偏暖、偏青灰，像拍立得刚吐出来的样子。
                .colorMultiply(Color(red: 1, green: 0.95 + 0.05 * p, blue: 0.86 + 0.14 * p))
                // 整体的乳白先褪一半……
                .overlay { Self.milk.opacity(1 - Self.ramp(p, 0, 0.6)) }
                // ……亮部的乳白留得久：暗的地方先显出来。
                .overlay {
                    Self.milk.opacity(0.9 * (1 - Self.ramp(p, 0.3, 1)))
                        .mask { photo.luminanceToAlpha() }
                }
        }
    }

    /// 在 [from, to] 之间从 0 平滑地升到 1。
    private static func ramp(_ p: Double, _ from: Double, _ to: Double) -> Double {
        let t = min(max((p - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
