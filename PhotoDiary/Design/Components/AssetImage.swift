import SwiftUI
import Photos

/// 照片库里的一张图。只请求需要的像素尺寸（最长边封顶 1024）；已解码过的第一帧就画出来，否则加载完成时淡入。
struct AssetImage: View {
    let id: String
    var contentMode: ContentMode = .fill
    var allowNetwork = false
    /// 不传则按视图实际大小请求。
    var pointSize: CGSize? = nil

    @State private var image: UIImage?
    @State private var size: CGSize = .zero
    @Environment(\.displayScale) private var scale

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                if let image = image ?? cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
            .task(id: TaskKey(id: id, size: pointSize ?? size)) {
                let pts = pointSize ?? size
                guard pts.width > 0, pts.height > 0 else { return }
                let px = AssetImages.pixelSize(points: pts, scale: scale)
                let mode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit
                for await img in AssetImages.shared.images(for: id, pixelSize: px, contentMode: mode, allowNetwork: allowNetwork) {
                    image = img
                }
            }
            .accessibilityHidden(true)
    }

    /// 解码缓存里已有的图，不用等 task 跑起来。
    private var cachedImage: UIImage? {
        let pts = pointSize ?? size
        guard pts.width > 0, pts.height > 0 else { return nil }
        return AssetImages.shared.cached(id, pixelSize: AssetImages.pixelSize(points: pts, scale: scale))
    }

    private struct TaskKey: Equatable {
        var id: String
        var size: CGSize
    }
}

/// zoom 转场的起点：有命名空间时把视图登记为转场源。
struct TransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    var cornerRadius: CGFloat = Metrics.Radius.tile
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous)) }
        } else {
            content
        }
    }
}
