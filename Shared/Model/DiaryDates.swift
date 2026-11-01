import Foundation

// MARK: 日期文案（iPhone 和 Apple Watch 共用）

extension DateFormatter {
    private static var localizedCache: [String: DateFormatter] = [:]

    /// 按界面语言排列的格式（模板，如 "MMMd"）。
    static func localized(_ template: String) -> DateFormatter {
        if let f = localizedCache[template] { return f }
        let f = DateFormatter()
        f.locale = DiaryDates.locale
        f.calendar = .diary
        f.setLocalizedDateFormatFromTemplate(template)
        localizedCache[template] = f
        return f
    }

    static func resetLocalized() { localizedCache.removeAll() }
}

enum DiaryDates {
    /// 界面语言对应的地区。设置里切换语言时由 AppLanguage 改写；Watch 用系统当前的。
    static var locale: Locale = .autoupdatingCurrent {
        didSet { DateFormatter.resetLocalized() }
    }

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
    /// 日期范围，重复的部分只写一次：10月3日至12日 / Oct 3 – 12；不在今年才写年份。
    static func range(_ from: DayStamp, _ to: DayStamp) -> String {
        let thisYear = from.year == DayStamp.today.year && to.year == DayStamp.today.year
        if from == to { return thisYear ? short(from) : full(from) }
        let f = DateIntervalFormatter()
        f.locale = locale
        f.calendar = .diary
        f.dateTemplate = thisYear ? "MMMd" : "yMMMd"
        return f.string(from: from.date, to: to.date)
    }
    /// 月份标题：10月 / October
    static func monthName(_ date: Date) -> String {
        locale.language.languageCode == .english ? format("LLLL", date) : format("MMM", date)
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
        case ..<1: relative = String(localized: "同一天", bundle: .app, locale: .app)
        case 1: relative = String(localized: "第二天", bundle: .app, locale: .app)
        case 2: relative = String(localized: "两天后", bundle: .app, locale: .app)
        case 3..<30: relative = String(localized: "\(n) 天后", bundle: .app, locale: .app)
        case 30..<365: relative = String(localized: "\(n / 30) 个月后", bundle: .app, locale: .app)
        default: relative = String(localized: "\(n / 365) 年后", bundle: .app, locale: .app)
        }
        return (relative, dated(day, relativeTo: previous))
    }

    /// 同一年只写月日，跨年才带年份。
    private static func dated(_ day: DayStamp, relativeTo other: DayStamp?) -> String {
        day.year == (other?.year ?? DayStamp.today.year) ? short(day) : full(day)
    }

    static func yearsAgo(_ day: DayStamp) -> String {
        String(localized: "\(DayStamp.today.year - day.year) 年前", bundle: .app, locale: .app)
    }

    /// “3 年前的今天”
    static func onThisDay(_ day: DayStamp) -> String {
        String(localized: "\(DayStamp.today.year - day.year) 年前的今天", bundle: .app, locale: .app)
    }
}
