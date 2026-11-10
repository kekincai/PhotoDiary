import SwiftUI

/// 尺寸的唯一来源。圆角按“同心”原则：内层圆角 = 外层圆角 − 内边距，照片卡片、缩略图、胶囊都从这里取。
enum Metrics {
    // MARK: 边距

    /// 卡片、网格等成块内容到屏幕边缘。
    static let page: CGFloat = 16
    /// 标题和说明文字到屏幕边缘，比卡片再进 4pt，视觉上对齐卡片里的内容。
    static let text: CGFloat = 20
    /// 详情页正文的阅读边距。
    static let reading: CGFloat = 24

    // MARK: 间距

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: 圆角

    enum Radius {
        /// 日历格子、小缩略图。
        static let thumb: CGFloat = 8
        /// 行里的 78pt 缩略图。
        static let tile: CGFloat = 12
        /// 灰底卡片、封面。
        static let card: CGFloat = 16
        /// 首页的大照片卡片。
        static let hero: CGFloat = 24
    }

    // MARK: 控件

    /// 浮动玻璃控件的高度。
    static let control: CGFloat = 52
    /// 主题色“+”按钮。
    static let primaryAction: CGFloat = 62
    /// 底部浮动标签栏占用的高度，滚动内容要留出来。
    static let bottomBarInset: CGFloat = 170
    /// 底部只有一个浮动分段控件（“从照片添加”）时要留出来的高度。
    static let bottomControlInset: CGFloat = 110
    /// 列表里行的缩略图边长。
    static let rowThumb: CGFloat = 78
}
