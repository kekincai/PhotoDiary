import SwiftUI

// MARK: 主题色

/// 设置里的预设主题色，按色相排成两行；另有一个调色板可以自选。只用在标签、“+”按钮、追加感想、选中态和今天的日期圆上；颜色交给照片。
/// 存储的是十六进制字符串（`@AppStorage(BrandColor.storageKey)`），预设的 rawValue 就是它的颜色，自选的颜色也存成同样的格式。
enum BrandColor: String, CaseIterable, Identifiable {
    case lake = "#2F6690"
    case dusk = "#4B4A7A"
    case rouge = "#A04A63"
    case ochre = "#8A4B3C"
    case amber = "#A8742A"
    case moss = "#687A35"
    case pine = "#3D6B4F"
    case celadon = "#3E7C78"
    case graphite = "#4F5660"

    static let storageKey = "brand"
    /// 最近一次在调色板里选的颜色，自选格子显示它。
    static let customKey = "brandCustom"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }
    var name: String {
        switch self {
        case .lake: String(localized: "湖蓝", bundle: .app, locale: .app)
        case .dusk: String(localized: "暮紫", bundle: .app, locale: .app)
        case .rouge: String(localized: "胭脂", bundle: .app, locale: .app)
        case .ochre: String(localized: "赭石", bundle: .app, locale: .app)
        case .amber: String(localized: "琥珀", bundle: .app, locale: .app)
        case .moss: String(localized: "苔绿", bundle: .app, locale: .app)
        case .pine: String(localized: "松绿", bundle: .app, locale: .app)
        case .celadon: String(localized: "青瓷", bundle: .app, locale: .app)
        case .graphite: String(localized: "石墨", bundle: .app, locale: .app)
        }
    }
}

extension EnvironmentValues {
    @Entry var brand: Color = BrandColor.lake.color
}

// MARK: 外观：跟随系统，或固定浅色 / 深色

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: String(localized: "自动", bundle: .app, locale: .app)
        case .light: String(localized: "浅色", bundle: .app, locale: .app)
        case .dark: String(localized: "深色", bundle: .app, locale: .app)
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// 直接改窗口的 overrideUserInterfaceStyle：弹出的表单、提醒和 UIKit 视图都跟着变，切回“自动”也立即生效。
    func apply() {
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

// MARK: 一周起始日

extension WeekStart {
    var name: String {
        switch self {
        case .monday: String(localized: "周一", bundle: .app, locale: .app)
        case .sunday: String(localized: "周日", bundle: .app, locale: .app)
        }
    }
}

// MARK: 语义色

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// 界面用的主题色：深色模式下往白色混三成，深色底上的文字和图标才看得清。设置里的色块仍用原色。
    /// 打开“增强对比度”时再拉开一截：浅色模式压暗两成，深色模式往白色混一半。
    static func brand(hex: String) -> Color {
        let base = Color(hex: hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(base).getRed(&r, green: &g, blue: &b, alpha: &a)
        func toward(_ target: CGFloat, _ amount: CGFloat) -> UIColor {
            UIColor(red: r + (target - r) * amount, green: g + (target - g) * amount, blue: b + (target - b) * amount, alpha: 1)
        }
        let light = toward(0, 0), lightHigh = toward(0, 0.2)
        let dark = toward(1, 0.3), darkHigh = toward(1, 0.5)
        // SwiftUI 可能在渲染线程上解析动态颜色：闭包不能带主线程隔离。
        return Color(UIColor { @Sendable trait in
            let high = trait.accessibilityContrast == .high
            return trait.userInterfaceStyle == .dark ? (high ? darkHigh : dark) : (high ? lightHigh : light)
        })
    }

    /// "#RRGGBB"，存主题色用。
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// 标签胶囊等浅色底：主题色 10%；“增强对比度”时 18%，胶囊的边界才看得出。
    func soft() -> Color {
        let base = UIColor(self)
        return Color(UIColor { @Sendable trait in
            base.resolvedColor(with: trait).withAlphaComponent(trait.accessibilityContrast == .high ? 0.18 : 0.1)
        })
    }

    /// 正文。
    static let ink = Color(.label)
    /// 正文的次要层：预览、追加的段落。比系统 secondaryLabel 深一点，宋体小字才够清楚；“增强对比度”时再深（浅）一层。
    static let inkSecondary = Color(UIColor { @Sendable trait in
        let high = trait.accessibilityContrast == .high
        return trait.userInterfaceStyle == .dark
            ? UIColor(white: high ? 0.9 : 0.78, alpha: 1)
            : UIColor(red: high ? 0.2 : 0.33, green: high ? 0.2 : 0.33, blue: high ? 0.22 : 0.35, alpha: 1)
    })
    /// 元信息：日期、地点、篇数。
    static let meta = Color(.secondaryLabel)
    /// 分隔细线；“增强对比度”时加深，和系统分隔线一样。
    static let hairline = Color(UIColor { @Sendable trait in
        let high = trait.accessibilityContrast == .high
        return trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: high ? 0.3 : 0.12)
            : (high ? UIColor(white: 0.72, alpha: 1) : UIColor(red: 0.925, green: 0.925, blue: 0.937, alpha: 1))
    })
    /// 白底上的灰色块：那年今日横幅、本周写作、胶囊。
    static let tile = Color(.secondarySystemBackground)
}
