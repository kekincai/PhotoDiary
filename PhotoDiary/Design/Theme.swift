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

extension Color {
    /// 标签胶囊等浅色底：主题色 10%。
    func soft() -> Color { opacity(0.1) }
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
    /// 白底上的灰色块：那年今日横幅、编辑器的照片卡片、胶囊。
    static let tile = Color(.secondarySystemBackground)
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

    /// 宋体下载完成前的系统衬线体。每段正文每次刷新都要用，按字号缓存。
    @ObservationIgnored private var fallbackCache: [String: Font] = [:]

    func fallbackFont(size: CGFloat, bold: Bool, style: Font.TextStyle) -> Font {
        let key = "\(size)|\(bold)|\(style)"
        if let font = fallbackCache[key] { return font }
        let font = Font(uiFont(size: size, bold: bold, textStyle: style.uiKit))
        fallbackCache[key] = font
        return font
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
        return DiaryFonts.shared.fallbackFont(size: size, bold: bold, style: style)
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
    private static var localizedCache: [String: DateFormatter] = [:]

    /// 固定中文格式，只给导出等不随界面语言变化的地方用。
    static func zh(_ format: String) -> DateFormatter {
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = .diary
        f.dateFormat = format
        cache[format] = f
        return f
    }

    /// 按界面语言排列的格式（模板，如 "MMMd"）。
    static func localized(_ template: String) -> DateFormatter {
        if let f = localizedCache[template] { return f }
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.calendar = .diary
        f.setLocalizedDateFormatFromTemplate(template)
        localizedCache[template] = f
        return f
    }

    static func resetLocalized() { localizedCache.removeAll() }
}

enum DiaryDates {
    private static func format(_ template: String, _ date: Date) -> String {
        DateFormatter.localized(template).string(from: date)
    }

    /// 10月20日 周二 / 10月20日(火) / Tue, Oct 20
    static func dayTitle(_ date: Date) -> String { format("MMMdEEE", date) }
    /// 2023年10月31日 周二
    static func fullWithWeekday(_ date: Date) -> String { format("yMMMdEEE", date) }
    static func weekday(_ date: Date) -> String { format("EEE", date) }
    static func short(_ day: DayStamp) -> String { format("MMMd", day.date) }
    static func full(_ day: DayStamp) -> String { format("yMMMd", day.date) }
    /// 月份标题：10月 / October
    static func monthName(_ date: Date) -> String {
        AppLanguage.current == .english ? format("LLLL", date) : format("MMM", date)
    }
    static func yearMonth(_ date: Date) -> String { format("yMMMM", date) }
    /// 只写数字：2026
    static func year(_ date: Date) -> String { String(Calendar.diary.component(.year, from: date)) }

    /// 日历、本周写作的星期行，从周日开始：日 一 … / 日 月 … / S M …
    static var weekdaySymbols: [String] {
        DateFormatter.localized("EEEEE").veryShortStandaloneWeekdaySymbols
    }

    /// 段落之间的分隔：（“两天后”，“10月22日”）。
    static func gap(from previous: DayStamp?, to day: DayStamp) -> (relative: String, date: String) {
        guard let previous else { return (dated(day, relativeTo: nil), "") }
        let n = previous.days(to: day)
        let relative: String
        switch n {
        case ..<1: relative = String(localized: "同一天")
        case 1: relative = String(localized: "第二天")
        case 2: relative = String(localized: "两天后")
        case 3..<30: relative = String(localized: "\(n) 天后")
        case 30..<365: relative = String(localized: "\(n / 30) 个月后")
        default: relative = String(localized: "\(n / 365) 年后")
        }
        return (relative, dated(day, relativeTo: previous))
    }

    /// 同一年只写月日，跨年才带年份。
    private static func dated(_ day: DayStamp, relativeTo other: DayStamp?) -> String {
        day.year == (other?.year ?? DayStamp.today.year) ? short(day) : full(day)
    }

    static func yearsAgo(_ day: DayStamp) -> String {
        String(localized: "\(DayStamp.today.year - day.year) 年前")
    }

    /// “3 年前的今天”
    static func onThisDay(_ day: DayStamp) -> String {
        String(localized: "\(DayStamp.today.year - day.year) 年前的今天")
    }
}
