import Foundation

/// 一个不带时区的日历日，用于说明里的写作时间行（— YYYY.MM.DD）。
nonisolated struct DayStamp: Hashable, Comparable, Codable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard (1...12).contains(month), (1...31).contains(day),
              components.isValidDate(in: Calendar.diary) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .diary) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year ?? 1970
        month = c.month ?? 1
        day = c.day ?? 1
    }

    static var today: DayStamp { DayStamp(.now) }

    var date: Date {
        Calendar.diary.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// 写入说明时使用的格式，定死不改：2026.10.31
    var captionString: String {
        String(format: "%04d.%02d.%02d", year, month, day)
    }

    func days(to other: DayStamp) -> Int {
        Calendar.diary.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

nonisolated extension Calendar {
    /// 以周日为一周第一天的公历，与设计稿“日 一 二 … 六”一致。
    static let diary: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 1
        c.timeZone = .current
        return c
    }()
}
