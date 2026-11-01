import SwiftUI

// MARK: 主题色

/// 设置里可选的四种主题色。只用在标签、“+”按钮、追加感想、选中态和今天的日期圆上；颜色交给照片。
enum BrandColor: String, CaseIterable, Identifiable {
    case lake = "#2F6690"
    case pine = "#3D6B4F"
    case ochre = "#8A4B3C"
    case dusk = "#4B4A7A"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }
    var name: String {
        switch self {
        case .lake: String(localized: "湖蓝")
        case .pine: String(localized: "松绿")
        case .ochre: String(localized: "赭石")
        case .dusk: String(localized: "暮紫")
        }
    }
}

extension EnvironmentValues {
    @Entry var brand: Color = BrandColor.lake.color
}

// MARK: 语义色

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// 标签胶囊等浅色底：主题色 10%。
    func soft() -> Color { opacity(0.1) }

    /// 正文。
    static let ink = Color(.label)
    /// 正文的次要层：预览、追加的段落。比系统 secondaryLabel 深一点，宋体小字才够清楚。
    static let inkSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.78, alpha: 1) : UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1) })
    /// 元信息：日期、地点、篇数。
    static let meta = Color(.secondaryLabel)
    /// 分隔细线。
    static let hairline = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(red: 0.925, green: 0.925, blue: 0.937, alpha: 1) })
    static let card = Color(.secondarySystemGroupedBackground)
    /// 白底上的灰色块：那年今日横幅、编辑器的照片卡片、胶囊。
    static let tile = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
}
