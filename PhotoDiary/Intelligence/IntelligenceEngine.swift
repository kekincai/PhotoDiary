import Foundation

/// 设备上的语言模型能做的三件事。真实现走 Foundation Models；测试用假的，规则固定。
/// 都在后台跑，调用方自己防抖、自己丢掉过期的结果。
nonisolated protocol IntelligenceEngine: Sendable {
    /// 把一句自然语言拆成筛选条件；什么都没拆出来返回 nil。
    func interpret(_ query: String, context: SearchContext) async -> SearchIntent?
    /// 给一段日记建议标签（已经过后处理：合规、去重、最多三个）。
    func suggestTags(for text: String, existing: [String]) async -> [String]
    /// 本周回顾，逐段流出累计的全文。
    func weeklyReview(_ input: WeeklyReviewInput) -> AsyncThrowingStream<String, Error>
}

/// 解析搜索时给模型看的背景：今天、已有的标签和地点。
nonisolated struct SearchContext: Sendable, Hashable {
    var today: DayStamp
    var tags: [String]
    var places: [String]

    static let maxTags = 60
    static let maxPlaces = 30

    init(today: DayStamp, tags: [String], places: [String]) {
        self.today = today
        self.tags = Array(tags.prefix(Self.maxTags))
        self.places = Array(places.prefix(Self.maxPlaces))
    }
}

/// 本周回顾的输入：每篇一行“写作日期 · 地点 · 正文”，总量封顶，模型的上下文窗口有限。
nonisolated struct WeeklyReviewInput: Sendable, Hashable {
    struct Item: Sendable, Hashable {
        /// 这一段的写作日期（给旧照片追加的感想，是追加那天，不是拍照那天）。
        var date: DayStamp
        var place: String?
        var text: String
    }

    var items: [Item]
    var language: String
    static let maxCharacters = 2000
    /// 每篇至少留这么多字；篇数多到连这个都放不下时，只取前面几篇。
    static let minPerItem = 40

    /// `week` 是这周的日子：一篇日记只取这周写的那几段（标题句也在里面，行尾标签去掉）；没给就取全文。
    init(entries: [DiaryEntry], week: Set<DayStamp>? = nil, language: String, limit: Int = WeeklyReviewInput.maxCharacters) {
        self.language = language
        var items: [Item] = entries.compactMap { entry in
            var segments = entry.displaySegments
            if let week {
                let inWeek = segments.filter { $0.date.map(week.contains) == true }
                if !inWeek.isEmpty { segments = inWeek }
            }
            let text = segments.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            let date = segments.compactMap(\.date).max() ?? entry.day
            return Item(date: date, place: entry.placeName, text: text)
        }
        // 放不下就按篇数平分；篇数太多时先少放几篇，保证总量不超。
        let total = items.reduce(0) { $0 + $1.text.count }
        if total > limit, !items.isEmpty {
            let fit = max(1, limit / Self.minPerItem)
            if items.count > fit { items = Array(items.prefix(fit)) }
            let each = max(Self.minPerItem, limit / items.count) - 1
            for i in items.indices where items[i].text.count > each {
                items[i].text = String(items[i].text.prefix(each)) + "…"
            }
        }
        self.items = items
    }
}

/// 测试用：规则固定，结果可预期。
nonisolated struct FakeIntelligenceEngine: IntelligenceEngine {
    func interpret(_ query: String, context: SearchContext) async -> SearchIntent? {
        var intent = SearchIntent(keywords: [], tags: [], place: nil, from: nil, to: nil)
        for word in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word == "去年" {
                intent.from = "\(context.today.year - 1)-01-01"
                intent.to = "\(context.today.year - 1)-12-31"
            } else if word == "今年" {
                intent.from = "\(context.today.year)-01-01"
                intent.to = "\(context.today.year)-12-31"
            } else if context.tags.contains(word) {
                intent.tags.append(word)
            } else if context.places.contains(word) {
                intent.place = word
            } else {
                intent.keywords.append(word)
            }
        }
        return intent
    }

    func suggestTags(for text: String, existing: [String]) async -> [String] {
        let known = ["散步", "旅行", "咖啡", "京都"]
        let found = TagSuggestions.refine(known.filter { text.contains($0) }, text: text, existing: existing)
        return found.isEmpty ? TagSuggestions.refine(["随笔"], text: text, existing: existing) : found
    }

    func weeklyReview(_ input: WeeklyReviewInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("这一周写了 \(input.items.count) 篇。")
            continuation.finish()
        }
    }
}
