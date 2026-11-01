import SwiftUI

/// 底部浮动控件后面的渐隐，让下面的内容退后。
struct BottomFade: View {
    var height: CGFloat = 190

    var body: some View {
        let bg = Color(.systemBackground)
        LinearGradient(stops: [
            .init(color: bg.opacity(0), location: 0),
            .init(color: bg.opacity(0.75), location: 0.55),
            .init(color: bg.opacity(0.92), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 照片上压字时用的黑色渐变：顶部或底部。
struct PhotoScrim: View {
    enum Edge { case top, bottom }
    let edge: Edge
    var strength: Double = 0.55

    var body: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(strength), location: 0),
            .init(color: .black.opacity(strength * 0.5), location: 0.55),
            .init(color: .black.opacity(0), location: 1),
        ], startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 占位内容上从左到右扫过的高光；“减少动态效果”时不动。
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.65), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// 滚动视图里顶部的照片：下拉时跟着拉伸放大（照片、音乐 App 的做法），上滑时正常滚走。
/// 照片本身要铺满给定高度；拉伸发生在 ScrollView 坐标系里，所以只在 ScrollView 里有效。
struct StretchyHeader: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.visualEffect { [reduceMotion] content, geo in
            let minY = geo.frame(in: .scrollView(axis: .vertical)).minY
            let pull = reduceMotion ? 0 : max(0, minY)
            let height = geo.size.height
            // 顶边钉在屏幕顶上，照片向下长高，正好接上下面的正文。
            return content
                .scaleEffect(height > 0 ? 1 + pull / height : 1, anchor: .top)
                .offset(y: -pull)
        }
    }
}

extension View {
    func stretchyHeader() -> some View { modifier(StretchyHeader()) }
}
