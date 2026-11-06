import Testing
import Foundation
import FoundationModels
@testable import PhotoDiary

/// 模型给的东西都要对回真实数据才用：搜索条件、标签建议、本周回顾的输入，以及开关。模型本身不在这里测。
struct IntelligenceTests {
    let context = SearchContext(today: DayStamp(year: 2026, month: 10, day: 31)!,
                                tags: ["旅行", "日常", "Coffee"], places: ["镰仓", "京都"], language: "Simplified Chinese")

    // MARK: 搜索条件

    @Test func intentResolvesAgainstRealTagsPlacesAndDates() {
        let intent = SearchIntent(keywords: [" 海边", "海边", "", "旅行"], tags: ["#旅行#", "ｃｏｆｆｅｅ", "不存在"],
                                  place: "京都", from: "2025-06-01", to: "2025-08-31")
        let filter = intent.resolved(in: context)
        #expect(filter?.keywords == ["海边"]) // 去空、去重、和标签重复的不算关键词
        #expect(filter?.tags == ["旅行", "Coffee"]) // 对回已有标签，不分大小写和全角
        #expect(filter?.place == "京都")
        #expect(filter?.days == DayStamp(year: 2025, month: 6, day: 1)!...DayStamp(year: 2025, month: 8, day: 31)!)
    }

    @Test func intentWithNothingUsableIsNil() {
        #expect(SearchIntent(keywords: [], tags: ["不存在"], place: "火星", from: "昨天", to: nil).resolved(in: context) == nil)
        #expect(SearchIntent(keywords: [], tags: [], place: nil, from: "", to: "").resolved(in: context) == nil)
    }

    @Test func intentDatesTolerateOrderAndOpenEnds() {
        let swapped = SearchIntent(keywords: [], tags: [], place: nil, from: "2025.12.31", to: "2025/01/01").resolved(in: context)
        #expect(swapped?.days?.lowerBound == DayStamp(year: 2025, month: 1, day: 1)!)
        let open = SearchIntent(keywords: [], tags: [], place: nil, from: "2026-10-01", to: nil).resolved(in: context)
        #expect(open?.days?.upperBound == context.today)
        #expect(SearchIntent(keywords: [], tags: [], place: nil, from: "2026-13-01", to: nil).resolved(in: context) == nil)
    }

    @Test func filterSearchOrsKeywordsAndAndsTags() async {
        let library = FakeLibrary()
        library.seed("a", caption: "海边 #旅行#\n— 2026.10.30", date: date(2026, 10, 30))
        library.seed("b", caption: "山里 #旅行# #日常#", date: date(2026, 10, 20))
        library.seed("c", caption: "家里", date: date(2025, 7, 1))
        let store = await startedStore(library)
        #expect(store.search(SearchFilter(keywords: ["海", "山"])).map(\.id) == ["a", "b"])
        #expect(store.search(SearchFilter(keywords: ["海", "山"], tags: ["日常"])).map(\.id) == ["b"])
        #expect(store.search(SearchFilter(tags: ["旅行", "日常"])).map(\.id) == ["b"])
        let summer = DayStamp(year: 2025, month: 6, day: 1)!...DayStamp(year: 2025, month: 8, day: 31)!
        #expect(store.search(SearchFilter(days: summer)).map(\.id) == ["c"])
        #expect(store.search(SearchFilter(keywords: ["海"], days: summer)).isEmpty)
    }

    // MARK: 标签建议

    @Test func tagSuggestionsAreCleanedAndCapped() {
        let text = "今天和朋友去海边 #旅行#"
        let refined = TagSuggestions.refine(["#海边#", "旅行", " 朋友 ", "ｃｏｆｆｅｅ", "朋友", "太长太长太长太长太长太长太长太长太长太长太", "日常", "多余"],
                                            text: text, existing: ["Coffee", "日常"])
        #expect(refined == ["海边", "朋友", "Coffee"]) // 文中已有的不建议；对回已有标签；最多三个
        #expect(TagSuggestions.refine([], text: text, existing: []).isEmpty)
        #expect(TagSuggestions.refine(["a\nb"], text: "", existing: []) == ["a b"])
    }

    @Test func fakeEngineFollowsItsRules() async {
        let engine = FakeIntelligenceEngine()
        let intent = await engine.interpret("去年 旅行 海边 京都", context: context)
        #expect(intent?.resolved(in: context) == SearchFilter(keywords: ["海边"], tags: ["旅行"], place: "京都",
                                                               days: DayStamp(year: 2025, month: 1, day: 1)!...DayStamp(year: 2025, month: 12, day: 31)!))
        #expect(await engine.suggestTags(for: "下午去散步", existing: []) == ["散步"])
        #expect(await engine.suggestTags(for: "下午去散步 #散步#", existing: []) == ["随笔"])
    }

    // MARK: 本周回顾的输入

    @Test func weeklyReviewInputIsCapped() {
        let entry = DiaryEntry(id: "a", caption: String(repeating: "很长的一段话。", count: 300), keywords: [], creationDate: date(2026, 10, 30),
                               latitude: nil, longitude: nil, mediaKind: .photo, isCloudShared: false, pixelWidth: 0, pixelHeight: 0, placeName: "镰仓")
        let input = WeeklyReviewInput(entries: [entry, entry, entry], language: "Simplified Chinese", limit: 300)
        #expect(input.items.count == 3)
        #expect(input.items.allSatisfy { $0.text.count <= 101 && $0.text.hasSuffix("…") })
        #expect(input.items[0].place == "镰仓")
        #expect(input.items[0].date == DayStamp(year: 2026, month: 10, day: 30)!)
    }

    // MARK: 开关

    @Test func enabledNeedsBothSwitchAndAvailability() {
        let defaults = isolatedDefaults()
        let on = Intelligence(engine: FakeIntelligenceEngine(), defaults: defaults, forcedAvailable: true)
        #expect(on.isEnabled && on.isEligible)
        on.enabled = false
        #expect(!on.isEnabled)
        #expect(defaults.bool(forKey: Intelligence.storageKey) == false)
        let remembered = Intelligence(engine: FakeIntelligenceEngine(), defaults: defaults, forcedAvailable: true)
        #expect(!remembered.enabled)
        let off = Intelligence(engine: FakeIntelligenceEngine(), defaults: isolatedDefaults(), forcedAvailable: false)
        #expect(off.enabled && !off.isEnabled && !off.isEligible)
    }
}

/// 真模型跑一遍，确认结构化输出能生成、不抛错。只在开了 Apple Intelligence 的机器上、显式要求时跑：
/// `TEST_RUNNER_PHOTODIARY_MODEL_TESTS=1`。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHOTODIARY_MODEL_TESTS"] == "1", "需要设备上的语言模型"))
struct FoundationModelsTests {
    @Test func realModelAnswersAllThreeRequests() async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            Issue.record("这台机器上模型不可用")
            return
        }
        let engine = FoundationModelsEngine()
        let context = SearchContext(today: .today, tags: ["旅行", "散步"], places: ["京都"], language: "Simplified Chinese")
        let intent = await engine.interpret("去年夏天在京都散步", context: context)?.resolved(in: context)
        #expect(intent != nil)
        let tags = await engine.suggestTags(for: "下午沿着鸭川走了很久，傍晚在河边喝了杯咖啡。", existing: ["散步"])
        #expect(!tags.isEmpty)
        var text = ""
        let entry = DiaryEntry(id: "a", caption: "下午沿着鸭川走了很久。\n— \(DayStamp.today.captionString)", keywords: [], creationDate: .now,
                               latitude: nil, longitude: nil, mediaKind: .photo, isCloudShared: false, pixelWidth: 0, pixelHeight: 0)
        for try await partial in engine.weeklyReview(WeeklyReviewInput(entries: [entry], language: "Simplified Chinese")) { text = partial }
        #expect(!text.isEmpty)
    }
}
