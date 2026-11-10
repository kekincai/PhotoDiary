import Testing
import Foundation
@testable import PhotoDiary

/// photodiary:// 链接：解析、来回一致，打开后到对的地方。
@Suite(.serialized)
struct DeepLinkTests {
    @Test func parsesEveryLink() {
        #expect(DeepLink(url: URL(string: "photodiary://write/latest")!) == .writeLatest)
        #expect(DeepLink(url: URL(string: "photodiary://write")!) == .writeLatest)
        #expect(DeepLink(url: URL(string: "photodiary://today")!) == .today)
        #expect(DeepLink(url: URL(string: "photodiary://onthisday")!) == .onThisDay)
        #expect(DeepLink(url: URL(string: "PhotoDiary://OnThisDay")!) == .onThisDay)
        #expect(DeepLink(url: URL(string: "photodiary://entry/9F1A-22/L0/001")!) == .entry("9F1A-22/L0/001"))
        #expect(DeepLink(url: URL(string: "photodiary://search?q=%E4%BA%AC%E9%83%BD")!) == .search("京都"))
        #expect(DeepLink(url: URL(string: "photodiary://search")!) == .search(""))
    }

    @Test func rejectsOtherLinks() {
        #expect(DeepLink(url: URL(string: "https://example.com/write/latest")!) == nil)
        #expect(DeepLink(url: URL(string: "photodiary://")!) == nil)
        #expect(DeepLink(url: URL(string: "photodiary://entry")!) == nil)
        #expect(DeepLink(url: URL(string: "photodiary://write/oldest")!) == nil)
        #expect(DeepLink(url: URL(string: "photodiary://settings")!) == nil)
    }

    @Test(arguments: [DeepLink.writeLatest, .today, .onThisDay, .entry("A1B2-C3/L0/001"), .entry("有 空格/L0/001"),
                      .search("#旅行# 京都"), .search("")])
    func roundTrips(_ link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
        #expect(link.url.scheme == "photodiary")
    }

    /// 快捷指令、控制中心按钮执行后，链接交到收件箱里（App 能读照片库时由 Router 打开）。
    @Test @MainActor func intentsLeaveLinkInInbox() async throws {
        let inbox = DeepLinkInbox.shared
        _ = try await WriteLatestPhotoIntent().perform()
        #expect(inbox.take() == .writeLatest)
        _ = try await OpenTodayIntent().perform()
        #expect(inbox.take() == .today)
        _ = try await OpenOnThisDayIntent().perform()
        #expect(inbox.take() == .onThisDay)
        let search = SearchDiaryIntent()
        search.text = "京都"
        _ = try await search.perform()
        #expect(inbox.take() == .search("京都"))
    }

    @Test @MainActor func inboxHandsOutOnce() {
        let inbox = DeepLinkInbox.shared
        inbox.open(.today)
        #expect(inbox.pending == .today)
        #expect(inbox.take() == .today)
        #expect(inbox.take() == nil)
    }
}

@MainActor
struct DeepLinkRoutingTests {
    @Test func writeLatestOpensEditorForNewPhoto() {
        let router = Router()
        router.open(.writeLatest, latestPhoto: .init(id: "P/L0/001", hasDiary: false))
        #expect(router.editor?.assetID == "P/L0/001")
        #expect(router.editor?.mode == .new)
    }

    @Test func writeLatestAppendsWhenPhotoHasDiary() {
        let router = Router()
        router.open(.writeLatest, latestPhoto: .init(id: "P/L0/001", hasDiary: true))
        #expect(router.editor?.mode == .append)
    }

    @Test func writeLatestWithoutPhotosDoesNothing() {
        let router = Router()
        router.open(.writeLatest, latestPhoto: nil)
        #expect(router.editor == nil)
        // 开着的编辑器也不动。
        let open = EditorRequest(assetID: "x", mode: .append)
        router.editor = open
        router.open(.writeLatest, latestPhoto: nil)
        #expect(router.editor == open)
    }

    @Test func writeLatestClosesOtherSheetsFirst() async throws {
        let router = Router()
        router.showAddFromPhotos = true
        router.open(.writeLatest, latestPhoto: .init(id: "P/L0/001", hasDiary: false))
        #expect(!router.showAddFromPhotos)
        #expect(router.editor == nil)
        #expect(await eventually(timeout: .seconds(3)) { router.editor?.assetID == "P/L0/001" })
    }

    @Test func todayOpensTodaysPage() {
        let router = Router()
        router.tab = .search
        router.open(.today)
        #expect(router.tab == .journal)
        #expect(router.journalPath == [.day(.today)])
    }

    @Test func onThisDayOpensReview() {
        let router = Router()
        router.reviewPath = [.tags]
        router.showSettings = true
        router.open(.onThisDay)
        #expect(router.tab == .review)
        #expect(router.reviewPath.isEmpty)
        #expect(!router.showSettings)
    }

    /// 编辑器开着但没写字：直接收起，去链接指的地方。
    @Test func entryOpensDetail() {
        let router = Router()
        router.journalPath = [.tags, .tag("旅行")]
        router.editor = EditorRequest(assetID: "x", mode: .edit)
        router.open(.entry("A/L0/001"))
        #expect(router.tab == .journal)
        #expect(router.journalPath == [.entry("A/L0/001")])
        #expect(router.editor == nil)
    }

    /// 编辑器里有没保存的字：链接（小组件、快捷指令）不顶掉编辑器，字不丢；编辑器关掉后再去链接指的地方。
    @Test func linkWaitsWhileEditorHasUnsavedText() async {
        let router = Router()
        let editing = EditorRequest(assetID: "x", mode: .append)
        router.editor = editing
        router.editorIsDirty = true
        for link in [DeepLink.today, .onThisDay, .entry("A/L0/001"), .search("京都")] {
            router.open(link)
            #expect(router.editor == editing)
            #expect(router.tab == .journal && router.journalPath.isEmpty)
        }
        router.open(.writeLatest, latestPhoto: .init(id: "P/L0/001", hasDiary: false))
        #expect(router.editor == editing)

        // 保存或放弃后：编辑器收起，最后一个链接接着打开。
        router.editor = nil
        router.editorIsDirty = false
        #expect(await eventually(timeout: .seconds(3)) { router.editor?.assetID == "P/L0/001" })
    }

    /// 没保存就被手势收起的编辑器：字留成草稿，再打开同一张照片的同一种编辑器时放回去，只放一次。
    @Test func draftsAreKeptPerPhotoAndMode() {
        let router = Router()
        router.saveDraft("写了一半", for: "x", mode: .append)
        #expect(router.takeDraft(for: "x", mode: .new) == nil)
        #expect(router.takeDraft(for: "y", mode: .append) == nil)
        #expect(router.takeDraft(for: "x", mode: .append) == "写了一半")
        #expect(router.takeDraft(for: "x", mode: .append) == nil)
    }

    @Test func searchCarriesText() {
        let router = Router()
        router.searchPath = [.entry("x")]
        router.open(.search("京都"))
        #expect(router.tab == .search)
        #expect(router.searchPath.isEmpty)
        #expect(router.searchRequest == "京都")
    }
}
