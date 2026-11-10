import Foundation

/// 一年回顾：从某一年的日记里挑出来的几样东西。只由日记决定，不读照片库，可以直接测。
///
/// 一篇日记算在照片日期那一年（和日记列表、月份分组一致）。
nonisolated struct YearInReview: Hashable, Identifiable, Sendable {
    /// 标签、地点：名字、篇数、封面（最近一篇的照片）。
    struct Ranked: Hashable, Sendable {
        var name: String
        var count: Int
        var cover: String
    }

    let year: Int
    /// 这一年的日记篇数。
    let count: Int
    /// 每个月的篇数，下标 0 是 1 月。
    let monthCounts: [Int]
    /// 写得最多的月份（1…12）；并列时取早的。
    let busiestMonth: Int
    /// 写过的月份数。
    var activeMonths: Int { monthCounts.filter { $0 > 0 }.count }
    /// 用得最多的标签，最多 5 个。
    let tags: [Ranked]
    /// 去得最多的地方，最多 5 个。
    let places: [Ranked]
    /// 挑出来的几篇，按日期排。
    let highlights: [DiaryEntry]
    /// 封面照片。
    let cover: String
    /// 分享图里的照片：9、4 或 1 张。
    let mosaic: [String]

    var id: Int { year }

    static let maxHighlights = 5
    static let maxRanked = 5

    /// 这一年没有日记时返回 nil。entries 的顺序不影响结果。
    static func make(entries: [DiaryEntry], year: Int) -> YearInReview? {
        let inYear = entries.filter { $0.day.year == year }
            // 新的在前；同一时刻按 id，结果不随输入顺序变。
            .sorted { ($0.sortDate, $1.id) > ($1.sortDate, $0.id) }
        guard !inYear.isEmpty else { return nil }

        var months = Array(repeating: 0, count: 12)
        for entry in inYear { months[entry.day.month - 1] += 1 }
        let busiest = months.indices.max { (months[$0], $1) < (months[$1], $0) }! + 1

        let ranked = rankedByScore(inYear)
        let highlights = pickHighlights(ranked)
        let mosaicCount = inYear.count >= 9 ? 9 : inYear.count >= 4 ? 4 : 1
        var mosaic: [String] = []
        for entry in highlights + ranked where !mosaic.contains(entry.id) {
            mosaic.append(entry.id)
            if mosaic.count == mosaicCount { break }
        }

        return YearInReview(
            year: year,
            count: inYear.count,
            monthCounts: months,
            busiestMonth: busiest,
            tags: rank(inYear) { $0.tags },
            places: rank(inYear) { $0.placeName.map { [$0] } ?? [] },
            highlights: highlights.sorted { ($0.sortDate, $0.id) < ($1.sortDate, $1.id) },
            // 挑出来的第一篇；一篇都挑不出来（全是只有标签、没有正文的说明）时用这一年的第一篇，不能去取空数组的第一个。
            cover: (highlights.first ?? inYear[0]).id,
            mosaic: mosaic)
    }

    /// 回顾页列出的年份，新的在前：往年只要有日记就列；今年要到 12 月，
    /// 或者刚写满一年（第一次写日记的那天过了一周年，30 天内）才列。
    static func years(in entries: [DiaryEntry], today: DayStamp) -> [Int] {
        var years = Set(entries.lazy.map(\.day.year).filter { $0 < today.year })
        if entries.contains(where: { $0.day.year == today.year }),
           today.month == 12 || isFirstAnniversary(entries: entries, today: today) {
            years.insert(today.year)
        }
        return years.sorted(by: >)
    }

    /// 所有可以打开的回顾，新的在前。
    static func all(entries: [DiaryEntry], today: DayStamp) -> [YearInReview] {
        years(in: entries, today: today).compactMap { make(entries: entries, year: $0) }
    }

    private static func isFirstAnniversary(entries: [DiaryEntry], today: DayStamp) -> Bool {
        guard let first = entries.lazy.flatMap(\.writingDays).min(),
              let anniversary = DayStamp(year: first.year + 1, month: first.month, day: first.day)
                ?? DayStamp(year: first.year + 1, month: first.month, day: 28)
        else { return false }
        let days = anniversary.days(to: today)
        return (0..<30).contains(days)
    }

    // MARK: 挑日记

    /// 写得越多越靠前：正文字数（封顶 400）、后来又追加过的、带标签和地点的加分。
    private static func score(_ entry: DiaryEntry) -> Int {
        let text = entry.displaySegments.reduce(0) { $0 + $1.text.count }
        return min(text, 400)
            + 150 * max(entry.displaySegments.count - 1, 0)
            + (entry.tags.isEmpty ? 0 : 30)
            + (entry.placeName == nil ? 0 : 20)
    }

    private static func rankedByScore(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        // 先算好每篇的分数，排序时不再一遍遍重算。
        let scored = entries.filter { !$0.title.isEmpty }.map { (entry: $0, score: score($0)) }
        return scored.sorted { ($0.score, $1.entry.id) > ($1.score, $0.entry.id) }.map(\.entry)
            .nonEmpty ?? entries
    }

    /// 尽量每个月挑一篇（分数高的月份先挑），不够再按分数补。
    private static func pickHighlights(_ ranked: [DiaryEntry]) -> [DiaryEntry] {
        var picked: [DiaryEntry] = []
        var months = Set<Int>()
        for entry in ranked where picked.count < maxHighlights && months.insert(entry.day.month).inserted {
            picked.append(entry)
        }
        for entry in ranked where picked.count < maxHighlights && !picked.contains(where: { $0.id == entry.id }) {
            picked.append(entry)
        }
        return picked
    }

    /// 按篇数排，并列时按名字；封面是最近一篇（entries 已按新到旧排好）。
    private static func rank(_ entries: [DiaryEntry], names: (DiaryEntry) -> [String]) -> [Ranked] {
        var result: [String: Ranked] = [:]
        for entry in entries {
            for name in Set(names(entry)) {
                result[name, default: Ranked(name: name, count: 0, cover: entry.id)].count += 1
            }
        }
        return result.values.sorted { ($0.count, $1.name) > ($1.count, $0.name) }.prefix(maxRanked).map { $0 }
    }
}

private extension Array {
    nonisolated var nonEmpty: Self? { isEmpty ? nil : self }
}
