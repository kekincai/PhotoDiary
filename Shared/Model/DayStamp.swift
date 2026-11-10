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

/// 一周从哪天开始。默认周一；设置里可改，Watch 跟随 iPhone 的快照。
nonisolated enum WeekStart: Int, CaseIterable, Identifiable, Sendable {
    case monday = 2
    case sunday = 1

    static let storageKey = "weekStart"
    static let `default` = WeekStart.monday

    var id: Int { rawValue }

    /// 应用里当前生效的设定（UserDefaults 里没有就是周一）。
    static var stored: WeekStart {
        WeekStart(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .default
    }
}

nonisolated extension Calendar {
    /// 日记用的公历；一周从哪天开始由 `diaryFirstWeekday` 决定（启动时和设置改动时写入）。
    static var diary: Calendar {
        var c = base
        c.firstWeekday = diaryFirstWeekday
        return c
    }

    /// 1 = 周日，2 = 周一。只在主线程改，各处读；写入后要重算按周归并的数据（DiaryStore.weekStartChanged）。
    nonisolated(unsafe) static var diaryFirstWeekday = WeekStart.default.rawValue

    /// 时区跟着系统走（autoupdating）：App 留在后台时坐飞机换了时区，“今天”和写进说明的日期也跟着换。
    private static let base: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    /// 月份第一天前面要空出的格子数（按本日历的一周起始日）。
    func leadingBlanks(before firstDay: Date) -> Int {
        (component(.weekday, from: firstDay) - firstWeekday + 7) % 7
    }
}
