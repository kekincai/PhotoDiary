import SwiftUI
import Photos

/// 全屏看图：UIScrollView 原生的缩放、回弹和惯性；跟手下拉关闭。
///
/// 下拉时照片跟着手指走、略微缩小，黑底随距离变淡；松手按速度推算落点，够远就关（zoom 转场把照片收回详情页），
/// 不够就带一点回弹回到原位。往回拉过了头不硬停，带阻尼跟手。
struct PhotoViewer: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.assistiveTechnology) private var assistive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var chromeVisible = true
    /// 下拉的位移（窗口坐标）；零表示没在拖。
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    /// VoiceOver、切换控制下关闭按钮一直在：点一下藏起来的手势他们用不了。
    private var showsChrome: Bool { (chromeVisible && !dragging) || assistive.isRunning }

    var body: some View {
        GeometryReader { geo in
            let progress = DragToDismiss.progress(drag.height, height: geo.size.height)
            ZStack {
                Color.black
                    .opacity(1 - progress)
                    .ignoresSafeArea()
                if let image {
                    ZoomableImage(image: image,
                                  onSingleTap: { withAnimation(.snappy) { chromeVisible.toggle() } },
                                  onDrag: { dragChanged($0) },
                                  onDragEnd: { dragEnded($0, velocity: $1, height: geo.size.height) })
                        .ignoresSafeArea()
                        // “减少动态效果”时照片不跟着缩，只淡出背景。
                        .scaleEffect(reduceMotion ? 1 : DragToDismiss.scale(progress))
                        .offset(reduceMotion ? .zero : drag)
                        .accessibilityElement()
                        .accessibilityLabel(Text("照片"))
                        .accessibilityAddTraits(.isImage)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        // 自己的跟手手势代替系统的下拉关闭，两个不抢。
        .interactiveDismissDisabled()
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
        .animation(.snappy, value: dragging)
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

    private func dragChanged(_ translation: CGSize) {
        dragging = true
        // 往上推过了起点：橡皮筋，越推越难。
        let y = translation.height >= 0 ? translation.height : -DragToDismiss.rubberBand(-translation.height)
        drag = CGSize(width: translation.width, height: y)
    }

    private func dragEnded(_ translation: CGSize, velocity: CGSize, height: CGFloat) {
        dragging = false
        if DragToDismiss.shouldDismiss(translation: translation.height, velocity: velocity.height, height: height) {
            // 照片从手指松开的地方回到详情页原位：位移和 zoom 转场一起收。
            withAnimation(.move) {
                drag = .zero
                dismiss()
            }
        } else {
            withAnimation(.drawer) { drag = .zero }
        }
    }
}

/// 下拉关闭的数学部分（单元测试直接测这里）。
enum DragToDismiss {
    /// 拖动距离 → 0…1 的进度；拖过屏幕一半算到头。
    static func progress(_ y: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        return min(max(y / (height * 0.5), 0), 1)
    }

    /// 照片跟着缩小，最小 0.8。
    static func scale(_ progress: CGFloat) -> CGFloat { 1 - 0.2 * progress }

    /// 按惯性会停在哪里（UIScrollView 正常减速率的投影）。
    static func project(_ velocity: CGFloat, decelerationRate: CGFloat = UIScrollView.DecelerationRate.normal.rawValue) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    /// 松手时：正在往回拉就不关；否则看落点有没有过阈值。
    static func shouldDismiss(translation: CGFloat, velocity: CGFloat, height: CGFloat) -> Bool {
        guard velocity > -50 else { return false }
        let landing = translation + project(velocity)
        return landing > min(height * 0.22, 180)
    }

    /// 超过边界后的阻尼位移。
    static func rubberBand(_ offset: CGFloat, dimension: CGFloat = 400, coefficient: CGFloat = 0.55) -> CGFloat {
        (1 - 1 / (offset * coefficient / dimension + 1)) * dimension
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void
    /// 下拉途中的位移（窗口坐标，照片自己跟着动也不影响）。
    let onDrag: (CGSize) -> Void
    /// 松手：位移和速度（点/秒）。
    let onDragEnd: (CGSize, CGSize) -> Void

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
        // 只在没放大、主要往下拉时开始；开始后全程跟手。
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        scroll.addGestureRecognizer(pan)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
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

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let scroll = pan.view as? UIScrollView else { return true }
            guard scroll.zoomScale <= scroll.minimumZoomScale + 0.01 else { return false }
            let v = pan.velocity(in: nil)
            return v.y > 0 && v.y > abs(v.x)
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            // 窗口坐标：照片跟着手动，用它自己的坐标会越拖越乱。
            let t = gesture.translation(in: nil)
            switch gesture.state {
            case .began, .changed:
                parent.onDrag(CGSize(width: t.x, height: t.y))
            case .ended:
                let v = gesture.velocity(in: nil)
                parent.onDragEnd(CGSize(width: t.x, height: t.y), CGSize(width: v.x, height: v.y))
            case .cancelled, .failed:
                parent.onDragEnd(.zero, .zero)
            default: break
            }
        }
    }
}
