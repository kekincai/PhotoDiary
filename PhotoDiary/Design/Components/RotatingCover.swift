import SwiftUI
import Photos

/// 一组照片轮着做封面：每隔几秒淡入下一张，像相簿封面那样慢慢换。
/// 各块可以错开起步（stagger），不会一起跳；下一张先取到缓存里再切，不会闪一下灰底；
/// “减少动态效果”时停在第一张。
struct RotatingCover: View {
    let ids: [String]
    let pointSize: CGSize
    var period: Duration = .seconds(7)
    var stagger: Duration = .zero

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale

    private static let fade: Double = 1.4

    var body: some View {
        ZStack {
            if ids.indices.contains(index) {
                AssetImage(id: ids[index], pointSize: pointSize)
                    .id(ids[index])
                    // 新的一张淡入；旧的一张留在底下，等新的完全盖住再拿掉。
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .opacity.animation(.linear(duration: 0.01).delay(Self.fade))))
            }
        }
        .animation(.easeInOut(duration: Self.fade), value: index)
        .task(id: ids) {
            index = 0
            guard ids.count > 1, !reduceMotion else { return }
            try? await Task.sleep(for: stagger)
            while !Task.isCancelled {
                try? await Task.sleep(for: period)
                guard !Task.isCancelled else { return }
                let next = (index + 1) % ids.count
                await prefetch(ids[next])
                guard !Task.isCancelled else { return }
                index = next
            }
        }
    }

    /// 让缩略图先进缓存，切换时就不用等。
    private func prefetch(_ id: String) async {
        let px = AssetImages.pixelSize(points: pointSize, scale: scale)
        for await _ in AssetImages.shared.images(for: id, pixelSize: px, contentMode: .aspectFill) { break }
    }
}
