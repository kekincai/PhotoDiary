import SwiftUI
import CoreText

// MARK: 主题色

enum BrandColor: String, CaseIterable, Identifiable {
    case lake = "#2F6690"
    case pine = "#3D6B4F"
    case ochre = "#8A4B3C"
    case dusk = "#4B4A7A"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }
    var name: String {
        switch self {
        case .lake: "湖蓝"
        case .pine: "松绿"
        case .ochre: "赭石"
        case .dusk: "暮紫"
        }
    }
}

extension EnvironmentValues {
    @Entry var brand: Color = BrandColor.lake.color
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// 设计稿里的语义色，深色模式下自动适配。
    static let ink = Color(.label)
    static let inkSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.78, alpha: 1) : UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1) })
    static let meta = Color(.secondaryLabel)
    static let hairline = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(red: 0.925, green: 0.925, blue: 0.937, alpha: 1) })
    static let card = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
}

// MARK: 字体：日记正文用衬线体，界面用系统字体

/// 宋体（Songti SC）是系统按需下载的字体；下载完成前先用系统衬线体。
@Observable
final class DiaryFonts {
    static let shared = DiaryFonts()

    static let regularName = "STSongti-SC-Regular"
    static let boldName = "STSongti-SC-Bold"

    private(set) var songtiReady: Bool = DiaryFonts.isInstalled(DiaryFonts.regularName)

    static func isInstalled(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    func prepare() {
        guard !songtiReady else { return }
        Self.download([Self.regularName, Self.boldName])
    }

    /// 进度回调在 CoreText 的后台队列上执行，不能继承主线程隔离。
    nonisolated private static func download(_ names: [String]) {
        let descriptors = names.map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } as CFArray
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { @Sendable state, _ in
            if state == .didFinish {
                Task { @MainActor in
                    DiaryFonts.shared.songtiReady = DiaryFonts.isInstalled(DiaryFonts.regularName)
                }
            }
            return true
        }
    }

    func uiFont(size: CGFloat, bold: Bool = false, textStyle: UIFont.TextStyle = .body) -> UIFont {
        let base: UIFont
        if songtiReady, let f = UIFont(name: bold ? Self.boldName : Self.regularName, size: size) {
            base = f
        } else {
            let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            base = UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

extension Font {
    /// 日记正文字体，随动态字体缩放。
    static func diary(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        if DiaryFonts.shared.songtiReady {
            return .custom(bold ? DiaryFonts.boldName : DiaryFonts.regularName, size: size, relativeTo: style)
        }
        return Font(DiaryFonts.shared.uiFont(size: size, bold: bold, textStyle: style.uiKit))
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

// MARK: 动效：默认临界阻尼弹簧；只有带动量的手势才加回弹

extension Animation {
    /// damping 1.0, response 0.4
    static let move = Animation.spring(response: 0.4, dampingFraction: 1)
    /// damping 1.0, response 0.3
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 1)
    /// damping 0.8, response 0.3 —— 抽屉、浮层
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
    static func row(radius: CGFloat = 0) -> PressStyle {
        PressStyle(scale: 1, highlight: Color(.systemGray6), cornerRadius: radius)
    }
}

// MARK: 日期文案

extension DateFormatter {
    private static var cache: [String: DateFormatter] = [:]

    static func zh(_ format: String) -> DateFormatter {
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = .diary
        f.dateFormat = format
        cache[format] = f
        return f
    }
}

enum DiaryDates {
    /// 10月20日 周二
    static func dayTitle(_ date: Date) -> String { DateFormatter.zh("M月d日 EEE").string(from: date) }
    /// 2026年 十月
    static func monthHeader(_ date: Date) -> String { DateFormatter.zh("yyyy年 LLLL").string(from: date) }
    static func weekday(_ date: Date) -> String { DateFormatter.zh("EEE").string(from: date) }
    static func short(_ day: DayStamp) -> String { "\(day.month)月\(day.day)日" }
    static func full(_ day: DayStamp) -> String { "\(day.year)年\(day.month)月\(day.day)日" }

    /// 段落之间的分隔：（“两天后”，“10月22日”）。
    static func gap(from previous: DayStamp?, to day: DayStamp) -> (relative: String, date: String) {
        let label = short(day)
        guard let previous else { return (year(prefix: day) + label, "") }
        let n = previous.days(to: day)
        let relative: String
        switch n {
        case ..<1: relative = "同一天"
        case 1: relative = "第二天"
        case 2: relative = "两天后"
        case 3..<30: relative = "\(n) 天后"
        case 30..<365: relative = "\(n / 30) 个月后"
        default: relative = "\(n / 365) 年后"
        }
        return (relative, year(prefix: day, relativeTo: previous) + short(day))
    }

    private static func year(prefix day: DayStamp, relativeTo other: DayStamp? = nil) -> String {
        let ref = other?.year ?? DayStamp.today.year
        return day.year == ref ? "" : "\(day.year)年"
    }

    static func yearsAgo(_ day: DayStamp) -> String {
        let n = DayStamp.today.year - day.year
        return n == 1 ? "1 年前" : "\(n) 年前"
    }
}
