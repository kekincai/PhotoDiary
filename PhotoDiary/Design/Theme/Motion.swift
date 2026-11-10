import SwiftUI

// MARK: 动效：默认临界阻尼弹簧；只有带动量的手势才加回弹

extension Animation {
    /// damping 1.0, response 0.4 —— 页面级移动、标签栏出入。
    static let move = Animation.spring(response: 0.4, dampingFraction: 1)
    /// damping 1.0, response 0.3 —— 选中态、小控件。
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 1)
    /// damping 0.8, response 0.3 —— 抽屉、浮层。
    static let drawer = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

/// 按下即时缩放反馈；“减少动态效果”时改为透明度。
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var highlight: Color? = nil
    var cornerRadius: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect(cornerRadius: cornerRadius))
            .background {
                if let highlight, configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(highlight)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.75 : 1)
            .animation(configuration.isPressed ? nil : .snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
    static var row: PressStyle { PressStyle(scale: 1, highlight: Color(.systemGray6)) }
}

extension View {
    /// 标成 zoom 转场的来源（没有命名空间时什么都不做）。圆角是来源本身的轮廓（胶囊、圆形按钮传高度的一半），转场时从这个形状长出来。
    @ViewBuilder func zoomSource(_ id: String, in namespace: Namespace.ID?, cornerRadius: CGFloat = Metrics.Radius.tile) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous)) }
        } else {
            self
        }
    }

    /// zoom 转场的目的地：有来源（id 和命名空间都在）时从来源放大出来，没有就是普通的推入、表单上滑。
    @ViewBuilder func zoomDestination(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
