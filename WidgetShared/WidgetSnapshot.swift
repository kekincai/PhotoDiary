import Foundation

// MARK: App → 小组件的快照
//
// 小组件扩展不读照片库：App 在日记变化时把要显示的东西写进 App Group 的共享容器（快照 JSON + 缩小的照片），
// 再让 WidgetKit 重新取时间线。快照覆盖从今天起的一周，App 几天不开，小组件每天零点也能换到当天的那年今日。

nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    static let version = 1
    static let appGroup = "group.com.kejincai.photodiary"
    /// 从今天起算几天的那年今日。
    static let days = 7
    /// 每天最多几篇（小组件一天里轮流显示）。
    static let perDay = 3
    /// 缩略图最长边（像素）。大尺寸小组件在 3 倍屏上约 1000 像素宽。
    static let thumbnailPixels: CGFloat = 900

    var version = WidgetSnapshot.version
    var generated: Date
    /// 快照按 App 上的哪一天算的。
    var today: DayStamp
    /// 界面语言（zh-Hans / ja / en），小组件按它取文字。
    var language: String
    /// 今天写过日记没有（按说明里的写作日期）。只对 today 这一天有效。
    var wroteToday: Bool
    /// 从 today 起 days 天里每天的那年今日，按日期、再按年份从近到远。
    var memories: [WidgetMemory]

    init(generated: Date, today: DayStamp, language: String, wroteToday: Bool, memories: [WidgetMemory]) {
        self.generated = generated
        self.today = today
        self.language = language
        self.wroteToday = wroteToday
        self.memories = memories
    }

    /// 从日记（按照片日期倒序，即 DiaryStore.diaries）挑出一周里每天的那年今日。
    static func make(diaries: [DiaryEntry], today: DayStamp, language: String, generated: Date = .now) -> WidgetSnapshot {
        let days = upcomingDays(from: today)
        var memories: [WidgetMemory] = []
        for day in days {
            let picked = diaries
                .filter { $0.day.month == day.month && $0.day.day == day.day && $0.day.year < day.year }
                .prefix(perDay)
                .map { WidgetMemory(entry: $0) }
            memories += picked
        }
        let wrote = diaries.contains { $0.writingDays.contains(today) }
        return WidgetSnapshot(generated: generated, today: today, language: language, wroteToday: wrote, memories: memories)
    }

    static func upcomingDays(from today: DayStamp) -> [DayStamp] {
        (0..<days).map { offset in
            DayStamp(Calendar.diary.date(byAdding: .day, value: offset, to: today.date) ?? today.date)
        }
    }

    /// 某一天的那年今日（往年同月同日）。
    func memories(on day: DayStamp) -> [WidgetMemory] {
        memories.filter { $0.day.month == day.month && $0.day.day == day.day && $0.day.year < day.year }
    }

    /// 那天写过没有：快照只知道 today 那天的，之后的日子都当作还没写。
    func wrote(on day: DayStamp) -> Bool { day == today && wroteToday }

    /// 时间线：从 now 所在的那天起，每天零点换一次；一天有几篇就把这一天平分，轮流显示。
    /// 快照覆盖不到的日子不排（App 一周没开过，小组件就回到空的样子）。
    func timeline(from now: Date) -> [(date: Date, memory: WidgetMemory?)] {
        let calendar = Calendar.diary
        let start = calendar.startOfDay(for: now)
        var out: [(date: Date, memory: WidgetMemory?)] = []
        for offset in 0..<Self.days {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = DayStamp(dayStart)
            guard day >= today, today.days(to: day) < Self.days else { continue }
            let list = memories(on: day)
            if list.isEmpty {
                out.append((dayStart, nil))
                continue
            }
            let slot = 24 * 3600 / Double(list.count)
            for (index, memory) in list.enumerated() {
                out.append((dayStart.addingTimeInterval(slot * Double(index)), memory))
            }
        }
        // 已经过去的只留最近一项，从现在开始显示。
        if let current = out.lastIndex(where: { $0.date <= now }) {
            out = [(now, out[current].memory)] + out[(current + 1)...]
        }
        return out
    }

    // MARK: 共享容器

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Widgets", directoryHint: .isDirectory)
    }

    static var fileURL: URL? { directory?.appending(path: "snapshot.json") }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == version else { return nil }
        return snapshot
    }

    /// 照片的缩略图文件名（localIdentifier 带斜杠）。
    static func thumbnailName(for id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_") + ".jpg"
    }

    static func thumbnailURL(for id: String) -> URL? {
        directory?.appending(path: thumbnailName(for: id))
    }
}

/// 小组件上一篇那年今日要的东西：照片日期、标题（第一行）、预览。
nonisolated struct WidgetMemory: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var day: DayStamp
    var title: String
    var preview: String
    var placeName: String?

    init(id: String, day: DayStamp, title: String, preview: String, placeName: String? = nil) {
        self.id = id
        self.day = day
        self.title = title
        self.preview = preview
        self.placeName = placeName
    }

    init(entry: DiaryEntry) {
        self.init(id: entry.id, day: entry.day, title: entry.title, preview: entry.preview, placeName: entry.placeName)
    }
}
