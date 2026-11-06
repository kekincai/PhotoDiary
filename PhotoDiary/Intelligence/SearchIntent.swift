import Foundation
import FoundationModels

/// 模型从一句话里拆出来的筛选条件。字段都是字符串，对回索引里真实存在的标签、地点和日期后才用。
@Generable(description: "Search filters extracted from a natural-language query over a photo diary.")
nonisolated struct SearchIntent: Sendable, Hashable {
    @Guide(description: "Words to look for in the diary text, including close synonyms. Empty when the query is only about time, place or tags.")
    var keywords: [String]
    @Guide(description: "Tags mentioned in the query. Only tags from the provided list, spelled exactly.")
    var tags: [String]
    @Guide(description: "A place mentioned in the query, only if it is in the provided list, spelled exactly.")
    var place: String?
    @Guide(description: "Start of the date range as yyyy-MM-dd, when the query mentions a time. Otherwise empty.")
    var from: String?
    @Guide(description: "End of the date range as yyyy-MM-dd, when the query mentions a time. Otherwise empty.")
    var to: String?

    /// 对回真实数据：标签和地点不分大小写、全角半角；日期要能解析；全空就是没拆出东西。
    func resolved(in context: SearchContext) -> SearchFilter? {
        let tags = tags.compactMap { Self.match($0, in: context.tags) }.uniqued()
        let place = place.flatMap { Self.match($0, in: context.places) }
        let keywords = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { word in !tags.contains { Self.same($0, word) } }
            .uniqued()
        var range: ClosedRange<DayStamp>?
        if let a = Self.day(from), let b = Self.day(to) {
            range = a <= b ? a...b : b...a
        } else if let a = Self.day(from) {
            range = a...context.today
        } else if let b = Self.day(to) {
            range = DayStamp(Date.distantPast)...b
        }
        let filter = SearchFilter(keywords: keywords, tags: tags, place: place, days: range)
        return filter.isEmpty ? nil : filter
    }

    private static func match(_ name: String, in list: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "#＃ "))
        guard !trimmed.isEmpty else { return nil }
        return list.first { same($0, trimmed) }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }

    private static func day(_ text: String?) -> DayStamp? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "/" }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DayStamp(year: parts[0], month: parts[1], day: parts[2])
    }
}

/// 搜索的筛选条件：关键词之间是“或”，标签之间是“与”。
nonisolated struct SearchFilter: Sendable, Hashable {
    var keywords: [String] = []
    var tags: [String] = []
    var place: String?
    var days: ClosedRange<DayStamp>?

    var isEmpty: Bool { keywords.isEmpty && tags.isEmpty && place == nil && days == nil }

    /// 日期范围换成时刻：起始日的 0 点到结束日的最后一刻。
    var dateRange: ClosedRange<Date>? {
        guard let days else { return nil }
        let cal = Calendar.diary
        let start = cal.startOfDay(for: days.lowerBound.date)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: days.upperBound.date))?.addingTimeInterval(-1) ?? days.upperBound.date
        return start...end
    }
}

nonisolated extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
