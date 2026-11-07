import SwiftUI
import Photos

/// 全屏看图：UIScrollView 原生的缩放、回弹和惯性。
/// 下拉关闭交给系统的 zoom 转场（详情页用 navigationTransition(.zoom) 呈现）：照片全程跟手、缩小，
/// 松手按速度决定收回详情页原位还是弹回来，中途可以抓回。自己不再加下拉手势，免得和系统的抢。
struct PhotoViewer: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.assistiveTechnology) private var assistive
    @State private var image: UIImage?
    @State private var chromeVisible = true
    /// VoiceOver、切换控制下关闭按钮一直在：点一下藏起来的手势他们用不了。
    private var showsChrome: Bool { chromeVisible || assistive.isRunning }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image, onSingleTap: { withAnimation(.snappy) { chromeVisible.toggle() } })
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel(Text("照片"))
                    .accessibilityAddTraits(.isImage)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsChrome {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(16)
                .accessibilityLabel("关闭")
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showsChrome)
        // VoiceOver 的“返回”手势（两指画 Z）关闭。
        .accessibilityAction(.escape) { dismiss() }
        .task {
            // 点开大图时允许从 iCloud 临时下载。
            let px = CGSize(width: 3000, height: 3000)
            for await img in AssetImages.shared.images(for: id, pixelSize: px, contentMode: .aspectFit, allowNetwork: true) {
                image = img
            }
        }
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 4
        scroll.minimumZoomScale = 1
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage
        weak var imageView: UIImageView?

        init(_ parent: ZoomableImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                // 以手指位置为中心放大
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }

        @objc func singleTap() { parent.onSingleTap() }
    }
}
