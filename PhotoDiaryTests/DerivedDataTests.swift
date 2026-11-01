import Testing
import Foundation
@testable import PhotoDiary

/// 列表、日历、回顾、标签、地点、搜索、导出读的派生数据。“今天”固定为 2026-10-31（周六，本周从 10-25 周日起）。
struct DerivedDataTests {
    let library = FakeLibrary()
    let places = FakePlaceNamer()
    let defaults = isolatedDefaults()
    let clock = TestClock()

    init() {
        places.set("镰仓", latitude: 35.32, longitude: 139.55)
        places.set("京都", latitude: 35.01, longitude: 135.77)
        library.seed("a", caption: "海边 #旅行#\n— 2026.10.30", date: date(2026, 10, 30), latitude: 35.32, longitude: 139.55)
        library.seed("b", caption: "一年前\n— 2025.10.31\n\n再看\n— 2026.10.26", date: date(2025, 10, 31))
        library.seed("c", caption: "两年前 #旅行# #日常#", date: date(2024, 10, 31), latitude: 35.32, longitude: 139.55)
        library.seed("d", caption: "九月\n— 2026.09.15", date: date(2026, 9, 15), latitude: 35.01, longitude: 135.77)
        library.seed("e", caption: "导入", date: date(2026, 10, 5))
        defaults.set(["导入"], forKey: CaptionFilter.defaultsKey)
    }

    private func store() async -> DiaryStore {
        let store = await startedStore(library, places: places, defaults: defaults, clock: clock)
        _ = await eventually { store.places.count == 2 }
        return store
    }

    @Test func timelineAndMonthGroups() async {
        let store = await store()
        #expect(store.diaries.map(\.id) == ["a", "d", "b", "c"])
        #expect(store.months.map(\.id) == ["2026-10", "2026-9", "2025-10", "2024-10"])
        #expect(store.months.map { $0.entries.map(\.id) } == [["a"], ["d"], ["b"], ["c"]])
        #expect(store.calendarMonths == [date(2026, 10, 1), date(2026, 9, 1), date(2025, 10, 1), date(2024, 10, 1)]
            .map { Calendar.diary.dateInterval(of: .month, for: $0)!.start })
        #expect(store.entries(on: DayStamp(year: 2026, month: 10, day: 30)!).map(\.id) == ["a"])
    }

    @Test func calendarAlwaysIncludesThisMonth() async {
        clock.now = date(2026, 12, 3)
        let store = await store()
        #expect(store.calendarMonths.first == Calendar.diary.dateInterval(of: .month, for: date(2026, 12, 3))!.start)
        #expect(store.calendarMonths.count == 5)
    }

    @Test func reviewCounts() async {
        let store = await store()
        #expect(store.onThisDay.map(\.id) == ["b", "c"])
        // 一周默认从周一开始：2026-10-26（一）… 11-01（日）。
        #expect(store.weekWriting.map(\.day.day) == [26, 27, 28, 29, 30, 31, 1])
        #expect(store.weekWriting.filter(\.wrote).map(\.day.day) == [26, 30])
        #expect(store.writtenThisWeek == 2)
        #expect(store.writtenThisMonth == 2)
    }

    @Test func tagsAndPlaces() async {
        let store = await store()
        #expect(store.tagCounts == [.init(name: "旅行", count: 2), .init(name: "日常", count: 1)])
        #expect(store.allTags == ["旅行", "日常"])
        #expect(store.entries(tagged: "旅行").map(\.id) == ["a", "c"])
        #expect(store.places == [.init(name: "镰仓", count: 2, cover: "a"), .init(name: "京都", count: 1, cover: "d")])
        #expect(store.entries(at: "镰仓").map(\.id) == ["a", "c"])
    }

    @Test func captionFilterHidesAndCanBeLifted() async {
        let store = await store()
        #expect(store.entry("e") == nil)
        #expect(!store.diaries.contains { $0.id == "e" })

        defaults.set([String](), forKey: CaptionFilter.defaultsKey)
        store.captionFilterChanged()
        #expect(store.entry("e")?.caption == "导入")
        #expect(store.diaries.map(\.id) == ["a", "e", "d", "b", "c"])
    }

    @Test func newDayRecomputesOnForeground() async {
        let store = await store()
        #expect(!store.onThisDay.isEmpty)

        clock.now = date(2026, 11, 1)
        store.refreshAuthorization() // 回到前台时调用
        #expect(store.onThisDay.isEmpty)
        // 11 月 1 日是周日，仍属于 10 月 26 日开始的那一周。
        #expect(store.weekWriting.first?.day == DayStamp(year: 2026, month: 10, day: 26))
        #expect(store.writtenThisMonth == 0)
    }

    // MARK: 搜索

    @Test func searchByTextPlaceTagsAndRange() async {
        let store = await store()
        #expect(store.search(text: "海边", tags: [], range: nil).map(\.id) == ["a"])
        #expect(store.search(text: " 镰仓 ", tags: [], range: nil).map(\.id) == ["a", "c"])
        #expect(store.search(text: "", tags: ["旅行", "日常"], range: nil).map(\.id) == ["c"])
        #expect(store.search(text: "", tags: [], range: date(2026, 9, 1)...date(2026, 10, 31)).map(\.id) == ["a", "d"])
        #expect(store.search(text: "", tags: [], range: nil).count == 4)
        #expect(store.search(text: "导入", tags: [], range: nil).isEmpty) // 被隐藏的不出现
    }

    @Test func searchIgnoresCaseAndWidth() async {
        let library = FakeLibrary()
        library.seed("a", caption: "Sunset at Kamakura", date: date(2026, 10, 1))
        let store = await startedStore(library)
        #expect(store.search(text: "sunset", tags: [], range: nil).map(\.id) == ["a"])
        #expect(store.search(text: "ＫＡＭＡＫＵＲＡ", tags: [], range: nil).map(\.id) == ["a"])
    }

    // MARK: 设置里的建议与导出

    @Test func frequentShortCaptionsSuggestsRepeatedNonDiaryText() async {
        let library = FakeLibrary()
        for i in 0..<3 { library.seed("img\(i)", caption: "IMG", date: date(2026, 10, i + 1)) }
        library.seed("x1", caption: "导入", date: date(2026, 9, 1))
        library.seed("x2", caption: "导入", date: date(2026, 9, 2))
        library.seed("once", caption: "只有一次", date: date(2026, 9, 3))
        library.seed("dated1", caption: "好\n— 2026.09.04", date: date(2026, 9, 4))
        library.seed("dated2", caption: "好\n— 2026.09.04", date: date(2026, 9, 5))
        library.seed("long1", caption: String(repeating: "长", count: 13), date: date(2026, 9, 6))
        library.seed("long2", caption: String(repeating: "长", count: 13), date: date(2026, 9, 7))
        let store = await startedStore(library)

        let suggestions = store.frequentShortCaptions()
        #expect(suggestions.map(\.caption) == ["IMG", "导入"])
        #expect(suggestions.map(\.count) == [3, 2])
    }

    @Test func markdownExportIsOldestFirstWithPlace() async {
        let store = await store()
        let text = store.markdownExport()
        // 标题和日期跟随界面语言。
        let first = DiaryDates.fullWithWeekday(DayStamp(year: 2024, month: 10, day: 31)!.date)
        let last = DiaryDates.fullWithWeekday(DayStamp(year: 2026, month: 10, day: 30)!.date)
        #expect(text.hasPrefix("# \(String(localized: "照片日记"))\n\n## \(first) · 镰仓\n\n两年前 #旅行# #日常#\n\n"))
        #expect(text.hasSuffix("## \(last) · 镰仓\n\n海边 #旅行#\n— 2026.10.30\n\n"))
        #expect(!text.contains("导入"))
    }
}
