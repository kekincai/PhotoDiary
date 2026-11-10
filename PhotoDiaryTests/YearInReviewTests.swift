import Testing
import Foundation
@testable import PhotoDiary

/// 一年回顾挑什么：篇数、月份、标签、地点、挑出来的几篇、分享图的照片，以及回顾页列哪几年。
struct YearInReviewTests {
    private func entry(_ id: String, _ caption: String, _ day: Date, place: String? = nil) -> DiaryEntry {
        DiaryEntry(id: id, caption: caption, keywords: [], creationDate: day, latitude: nil, longitude: nil,
                   mediaKind: .photo, isCloudShared: false, pixelWidth: 4, pixelHeight: 3, placeName: place)
    }

    private var sample: [DiaryEntry] {
        [
            entry("jan", "一月的雪 #日常#\n— 2025.01.10", date(2025, 1, 10), place: "东京"),
            entry("mar1", "三月\n— 2025.03.02", date(2025, 3, 2), place: "京都"),
            entry("mar2", "三月又一篇，写得很长很长很长很长很长很长很长很长很长很长 #旅行#\n— 2025.03.20", date(2025, 3, 20), place: "京都"),
            entry("mar3", "三月第三篇 #旅行# #日常#\n— 2025.03.28\n\n一年后再看\n— 2026.03.28", date(2025, 3, 28), place: "京都"),
            entry("oct", "十月 #旅行#\n— 2025.10.01", date(2025, 10, 1)),
            entry("old", "前一年\n— 2024.12.31", date(2024, 12, 31)),
            entry("new", "后一年\n— 2026.01.01", date(2026, 1, 1)),
        ]
    }

    @Test func noReviewForAnEmptyYear() {
        #expect(YearInReview.make(entries: sample, year: 2023) == nil)
    }

    @Test func countsAndMonths() throws {
        let review = try #require(YearInReview.make(entries: sample, year: 2025))
        #expect(review.count == 5)
        #expect(review.monthCounts == [1, 0, 3, 0, 0, 0, 0, 0, 0, 1, 0, 0])
        #expect(review.busiestMonth == 3)
        #expect(review.activeMonths == 3)
    }

    @Test func busiestMonthTieGoesToTheEarlierMonth() throws {
        let entries = [entry("a", "a", date(2025, 5, 1)), entry("b", "b", date(2025, 2, 1))]
        #expect(try #require(YearInReview.make(entries: entries, year: 2025)).busiestMonth == 2)
    }

    @Test func tagsAndPlacesRankedByCountWithLatestCover() throws {
        let review = try #require(YearInReview.make(entries: sample, year: 2025))
        #expect(review.tags.map(\.name) == ["旅行", "日常"])
        #expect(review.tags.map(\.count) == [3, 2])
        #expect(review.tags[0].cover == "oct")
        #expect(review.places.map(\.name) == ["京都", "东京"])
        #expect(review.places.map(\.count) == [3, 1])
        #expect(review.places[0].cover == "mar3")
    }

    @Test func highlightsSpreadOverMonthsAndAreChronological() throws {
        let review = try #require(YearInReview.make(entries: sample, year: 2025))
        let ids = review.highlights.map(\.id)
        #expect(ids.count == 5)
        #expect(ids == ["jan", "mar1", "mar2", "mar3", "oct"])
        // 每个月最好的一篇先入选：三月是追加过的那篇，它也是封面。
        #expect(review.cover == "mar3")
    }

    @Test func highlightsCappedAndOnePerMonthFirst() throws {
        var entries: [DiaryEntry] = []
        for month in 1...8 {
            entries.append(entry("m\(month)", "第 \(month) 个月", date(2025, month, 3)))
        }
        // 同一个月里一篇特别长的：只占一个名额。
        entries.append(entry("long", String(repeating: "长", count: 300), date(2025, 2, 20)))
        let review = try #require(YearInReview.make(entries: entries, year: 2025))
        #expect(review.highlights.count == YearInReview.maxHighlights)
        #expect(Set(review.highlights.map(\.day.month)).count == YearInReview.maxHighlights)
        #expect(review.highlights.contains { $0.id == "long" })
        #expect(!review.highlights.contains { $0.id == "m2" })
    }

    @Test func resultDoesNotDependOnInputOrder() {
        #expect(YearInReview.make(entries: sample, year: 2025) == YearInReview.make(entries: sample.reversed(), year: 2025))
    }

    @Test func mosaicHasNineFourOrOnePhotos() throws {
        func review(_ n: Int) throws -> YearInReview {
            try #require(YearInReview.make(entries: (1...n).map { entry("p\($0)", "第 \($0) 篇", date(2025, 1 + $0 % 12, 1 + $0 % 27)) },
                                           year: 2025))
        }
        #expect(try review(1).mosaic.count == 1)
        #expect(try review(3).mosaic.count == 1)
        #expect(try review(4).mosaic.count == 4)
        #expect(try review(8).mosaic.count == 4)
        #expect(try review(9).mosaic.count == 9)
        #expect(try review(30).mosaic.count == 9)
        let big = try review(30)
        #expect(Set(big.mosaic).count == 9)
        #expect(big.highlights.allSatisfy { big.mosaic.contains($0.id) })
    }

    // MARK: 回顾页列哪几年

    @Test func pastYearsAlwaysListedNewestFirst() {
        let today = DayStamp(year: 2026, month: 6, day: 1)!
        #expect(YearInReview.years(in: sample, today: today) == [2025, 2024])
    }

    @Test func thisYearListedInDecember() {
        let today = DayStamp(year: 2026, month: 12, day: 1)!
        #expect(YearInReview.years(in: sample, today: today) == [2026, 2025, 2024])
    }

    @Test func thisYearListedForThirtyDaysAfterTheFirstAnniversary() {
        // 12 月本来就列今年。
        #expect(YearInReview.years(in: sample, today: DayStamp(year: 2025, month: 12, day: 30)!) == [2025, 2024])
        let entries = [entry("a", "一\n— 2025.11.03", date(2025, 11, 3)), entry("b", "二\n— 2026.02.01", date(2026, 2, 1))]
        #expect(YearInReview.years(in: entries, today: DayStamp(year: 2026, month: 11, day: 2)!) == [2025])
        #expect(YearInReview.years(in: entries, today: DayStamp(year: 2026, month: 11, day: 3)!) == [2026, 2025])
        #expect(YearInReview.years(in: entries, today: DayStamp(year: 2026, month: 12, day: 2)!) == [2026, 2025])
        #expect(YearInReview.years(in: entries, today: DayStamp(year: 2027, month: 2, day: 1)!) == [2026, 2025])
        // 一周年过了 30 天、还没到 12 月：今年不列。
        let late = [entry("a", "一\n— 2025.03.01", date(2025, 3, 1)), entry("b", "二\n— 2026.05.01", date(2026, 5, 1))]
        #expect(YearInReview.years(in: late, today: DayStamp(year: 2026, month: 3, day: 15)!) == [2026, 2025])
        #expect(YearInReview.years(in: late, today: DayStamp(year: 2026, month: 5, day: 15)!) == [2025])
    }

    @Test func noYearsWithoutDiaries() {
        #expect(YearInReview.years(in: [], today: DayStamp(year: 2026, month: 12, day: 1)!).isEmpty)
        #expect(YearInReview.all(entries: [], today: .today).isEmpty)
    }

    @Test func cardsSkipEmptySections() throws {
        let one = try #require(YearInReview.make(entries: [entry("a", "只有一篇", date(2025, 4, 1))], year: 2025))
        #expect(YearCard.cards(for: one) == [.cover, .entry("a"), .share])
        let full = try #require(YearInReview.make(entries: sample, year: 2025))
        #expect(YearCard.cards(for: full) == [.cover, .months, .tags, .places,
                                              .entry("jan"), .entry("mar1"), .entry("mar2"), .entry("mar3"), .entry("oct"), .share])
    }

    /// 一年里全是只有标签、没有正文的说明：挑不出“写得多”的日记，也照样能出回顾，不闪退。
    @Test func yearWithOnlyTagCaptionsStillHasCover() {
        let entries = (1...3).map { i in
            DiaryEntry(id: "t\(i)", caption: "#旅行#", keywords: [], creationDate: date(2025, 3, i), latitude: nil, longitude: nil,
                       mediaKind: .photo, isCloudShared: false, pixelWidth: 0, pixelHeight: 0)
        }
        let review = YearInReview.all(entries: entries, today: DayStamp(year: 2026, month: 6, day: 1)!).first
        #expect(review?.year == 2025)
        #expect(review.map { ["t1", "t2", "t3"].contains($0.cover) } == true)
    }
}
