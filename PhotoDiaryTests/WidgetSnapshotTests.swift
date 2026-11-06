import Testing
import Foundation
@testable import PhotoDiary

/// 小组件的快照：挑哪几篇、编码来回一致、时间线每天换到对的那年今日。
struct WidgetSnapshotTests {
    private func entry(_ id: String, _ y: Int, _ m: Int, _ d: Int, caption: String? = nil, wrote: DayStamp? = nil) -> DiaryEntry {
        var text = caption ?? "\(id) 的标题。后面的话"
        if let wrote { text += "\n— \(wrote.captionString)" }
        return DiaryEntry(id: id, caption: text, keywords: [], creationDate: date(y, m, d), latitude: nil, longitude: nil,
                          mediaKind: .photo, isCloudShared: false, pixelWidth: 0, pixelHeight: 0, placeName: "京都")
    }

    private let today = DayStamp(year: 2026, month: 10, day: 31)!

    @Test func picksOnThisDayForTheComingWeek() {
        let diaries = [
            entry("今年今天", 2026, 10, 31),          // 今年的不算
            entry("去年今天", 2025, 10, 31),
            entry("三年前今天", 2023, 10, 31),
            entry("去年明天", 2025, 11, 1),
            entry("去年第七天", 2025, 11, 6),
            entry("去年第八天", 2025, 11, 7),          // 超出一周
            entry("别的日子", 2024, 5, 3),
        ]
        let snapshot = WidgetSnapshot.make(diaries: diaries, today: today, language: "zh-Hans")
        #expect(snapshot.memories.map(\.id) == ["去年今天", "三年前今天", "去年明天", "去年第七天"])
        #expect(snapshot.memories(on: today).map(\.id) == ["去年今天", "三年前今天"])
        #expect(snapshot.memories(on: DayStamp(year: 2026, month: 11, day: 1)!).map(\.id) == ["去年明天"])
        #expect(snapshot.memories.first?.title == "去年今天 的标题。")
        #expect(snapshot.memories.first?.placeName == "京都")
    }

    @Test func atMostThreePerDay() {
        let diaries = (2018...2025).reversed().map { entry("y\($0)", $0, 10, 31) }
        let snapshot = WidgetSnapshot.make(diaries: diaries, today: today, language: "en")
        #expect(snapshot.memories.map(\.id) == ["y2025", "y2024", "y2023"])
    }

    @Test func wroteTodayOnlyCountsForThatDay() {
        let diaries = [entry("写于今天", 2026, 10, 20, wrote: today)]
        let snapshot = WidgetSnapshot.make(diaries: diaries, today: today, language: "ja")
        #expect(snapshot.wroteToday)
        #expect(snapshot.wrote(on: today))
        #expect(!snapshot.wrote(on: DayStamp(year: 2026, month: 11, day: 1)!))
        let none = WidgetSnapshot.make(diaries: [entry("写于别天", 2026, 10, 20, wrote: DayStamp(year: 2026, month: 10, day: 20)!)],
                                       today: today, language: "ja")
        #expect(!none.wroteToday)
    }

    @Test func roundTripsAndStaysSmall() throws {
        let diaries = (2010...2025).flatMap { y in (0..<7).map { entry("\(y)-\($0)", y, $0 == 0 ? 10 : 11, $0 == 0 ? 31 : $0) } }
        let snapshot = WidgetSnapshot.make(diaries: diaries, today: today, language: "zh-Hans", generated: fixedNow)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data) == snapshot)
        #expect(snapshot.memories.count == 7 * WidgetSnapshot.perDay)
        #expect(data.count < 8000)
    }

    @Test func timelineRotatesWithinDayAndChangesAtMidnight() {
        let diaries = [entry("a", 2025, 10, 31), entry("b", 2024, 10, 31), entry("c", 2025, 11, 2)]
        let snapshot = WidgetSnapshot.make(diaries: diaries, today: today, language: "zh-Hans")
        let cal = Calendar.diary
        // 今天下午两点：第二篇（12 点起）正在显示。
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))!
        let timeline = snapshot.timeline(from: now)
        #expect(timeline.first?.date == now)
        #expect(timeline.first?.memory?.id == "b")
        let nov1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let nov2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        #expect(timeline.contains { $0.date == nov1 && $0.memory == nil })
        #expect(timeline.contains { $0.date == nov2 && $0.memory?.id == "c" })
        // 一周（10.31–11.6）排完就停。
        #expect(timeline.last.map { DayStamp($0.date) } == DayStamp(year: 2026, month: 11, day: 6))
    }

    @Test func staleSnapshotHasNothingLeft() {
        let snapshot = WidgetSnapshot.make(diaries: [entry("a", 2025, 10, 31)], today: today, language: "zh-Hans")
        let later = Calendar.diary.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        #expect(snapshot.timeline(from: later).isEmpty)
    }

    @Test func thumbnailNamesHaveNoSlashes() {
        #expect(WidgetSnapshot.thumbnailName(for: "9F1A-22/L0/001") == "9F1A-22_L0_001.jpg")
    }
}
