import SwiftUI

extension View {
    /// 一段字像墨水渗进纸里（Ink.metal）。progress 0 → 1；到 1 时就是原样，不再走着色器。
    /// “减少动态效果”时只淡入。
    func inkIn(_ progress: Double, lineHeight: CGFloat) -> some View {
        modifier(InkInEffect(progress: progress, lineHeight: lineHeight))
    }
}

private struct InkInEffect: ViewModifier, Animatable {
    var progress: Double
    let lineHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(progress)
        } else {
            let p = Float(progress)
            let line = Float(lineHeight)
            content.visualEffect { view, proxy in
                view.layerEffect(ShaderLibrary.inkIn(.float(p), .float2(proxy.size), .float(line)),
                                 maxSampleOffset: CGSize(width: 2, height: 2),
                                 isEnabled: p < 1)
            }
        }
    }
}
