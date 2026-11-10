import Testing
import Foundation
@testable import PhotoDiary

/// 增量同步、写入说明、关键词和地名：DiaryStore 和照片库之间的往返。
struct LibraryWriteTests {
    // MARK: 增量

    @Test func incrementalAppliesUpdatesClearsAndDeletes() async {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        library.seed("b", caption: "二", date: date(2026, 10, 2))
        library.seed("c", caption: "三", date: date(2026, 10, 3))
        let store = await startedStore(library)

        library.externalEdit("a", caption: "一（改）", notify: false)
        library.externalEdit("b", caption: "", notify: false)      // 在照片 App 里清空了说明
        library.externalEdit("c", caption: nil, notify: false)     // 删除了照片
        library.externalEdit("d", caption: "新的一篇")               // 新照片；这一次通知触发增量

        #expect(await eventually { store.entry("d") != nil })
        #expect(store.entry("a")?.caption == "一（改）")
        #expect(store.entry("b") == nil)
        #expect(store.entry("c") == nil)
        #expect(store.diaries.map(\.id).sorted() == ["a", "d"])
        #expect(library.fullScans == 1)
    }

    @Test func placeNameSurvivesCaptionEditButNotMove() async {
        let places = FakePlaceNamer()
        places.set("横滨", latitude: 35.44, longitude: 139.64)
        places.set("东京", latitude: 35.68, longitude: 139.77)
        let library = FakeLibrary()
        library.seed("a", caption: "港口", date: date(2026, 10, 1), latitude: 35.44, longitude: 139.64)
        let store = await startedStore(library, places: places)
        #expect(await eventually { store.entry("a")?.placeName == "横滨" })

        library.externalEdit("a", caption: "港口，傍晚")
        #expect(await eventually { store.entry("a")?.caption == "港口，傍晚" })
        #expect(store.entry("a")?.placeName == "横滨")
        #expect(places.lookups == 1)

        library.externalUpdate("a") { $0.latitude = 35.68; $0.longitude = 139.77 }
        #expect(await eventually { store.entry("a")?.placeName == "东京" })
        #expect(places.lookups == 2)
    }

    // MARK: 写入

    @Test func appendAddsSegmentAfterBlankLine() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一\n— 2026.10.20", date: date(2026, 10, 1))
        let store = await startedStore(library)

        try await store.save(text: "又看了一遍", mode: .append, for: "a")
        #expect(library.caption(of: "a") == "一\n— 2026.10.20\n\n又看了一遍\n— 2026.10.31")
        #expect(store.entry("a")?.segments.count == 2)
    }

    /// App 没开时在 Mac 上改了说明、增量同步还没回来：追加感想、补标签都以照片库里现在的说明为准，不拿索引里的旧说明盖掉。
    @Test func appendAndAddTagStartFromLibraryNotStaleIndex() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "旧的\n— 2026.10.01", date: date(2026, 10, 1))
        let store = await startedStore(library)
        library.externalEdit("a", caption: "在 Mac 上改过\n— 2026.10.01", notify: false)
        #expect(store.entry("a")?.caption == "旧的\n— 2026.10.01")

        try await store.save(text: "表上说的", mode: .append, for: "a")
        #expect(library.caption(of: "a") == "在 Mac 上改过\n— 2026.10.01\n\n表上说的\n— 2026.10.31")

        library.externalEdit("a", caption: "又改过\n— 2026.10.01", notify: false)
        try await store.addTag("秋天", to: "a")
        #expect(library.caption(of: "a") == "又改过 #秋天#\n— 2026.10.01")
    }

    /// 照片已经删了（或不在有限访问的范围里）：写入报错，不当作写进去了。
    @Test func writingToMissingPhotoThrows() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "在", date: date(2026, 10, 1))
        let store = await startedStore(library)
        await #expect(throws: LibraryScanner.WriteError.missing(["没了"])) {
            try await store.save(text: "写不进去", mode: .new, for: "没了")
        }
        #expect(library.writes.isEmpty)
    }

    /// 标签改名时有一张共享相簿里别人的照片改不了：跳过它，其余照改。
    @Test func renameSkipsLockedPhotos() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一 #旧#", date: date(2026, 10, 1))
        library.seed("b", caption: "二 #旧#", date: date(2026, 10, 2))
        library.lock("b")
        let store = await startedStore(library)
        try await store.renameTags(["旧"], to: "新")
        #expect(library.caption(of: "a") == "一 #新#")
        #expect(library.caption(of: "b") == "二 #旧#")
        #expect(store.entry("a")?.tags == ["新"])
    }

    @Test func editKeepsTextAndAddsMissingDateLine() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "Sunset at Kamakura", date: date(2026, 10, 1))
        let store = await startedStore(library)

        try await store.save(text: "镰仓的日落 #旅行#", mode: .edit, for: "a")
        #expect(library.caption(of: "a") == "镰仓的日落 #旅行#\n— 2026.10.31")
        #expect(store.entry("a")?.tags == ["旅行"])
        #expect(store.entry("a")?.writtenInApp == true)
    }

    @Test func editToEmptyClearsCaption() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一\n— 2026.10.20", date: date(2026, 10, 1))
        let store = await startedStore(library)

        try await store.save(text: "  \n", mode: .edit, for: "a")
        #expect(library.caption(of: "a") == "")
        #expect(store.entry("a") == nil)
        #expect(store.diaries.isEmpty)
    }

    @Test func renameAndMergeTagsIsOneBatchWrite() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一 #旅行#", date: date(2026, 10, 1))
        library.seed("b", caption: "二 #出差# #旅行#", date: date(2026, 10, 2))
        library.seed("c", caption: "三 #出差#", date: date(2026, 10, 3))
        library.seed("d", caption: "四 #日常#", date: date(2026, 10, 4))
        let store = await startedStore(library)

        try await store.renameTags(["旅行", "出差"], to: "旅途")
        #expect(library.writes.count == 1)
        #expect(Set(library.writes[0].keys) == ["a", "b", "c"])
        #expect(library.caption(of: "b") == "二 #旅途#")
        #expect(library.keywords(of: "b") == ["旅途"])
        #expect(store.tagCounts.map(\.name) == ["旅途", "日常"])
        #expect(store.entries(tagged: "旅途").count == 3)
    }

    @Test func deleteRemovesPhotoAndEntry() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let store = await startedStore(library)

        try await store.delete(id: "a")
        #expect(library.deletions == [["a"]])
        #expect(store.entry("a") == nil)
    }

    // MARK: 关键词

    @Test func keywordsFollowTagsButImportedKeywordsAreKept() async {
        let library = FakeLibrary()
        library.seed("tagged", caption: "一 #旅行#", keywords: ["旧标签"], date: date(2026, 10, 1))
        library.seed("matching", caption: "二 #日常#", keywords: ["日常"], date: date(2026, 10, 2))
        library.seed("imported", caption: "Lightroom 导入的说明", keywords: ["Fujifilm", "Kanagawa"], date: date(2026, 10, 3))
        _ = await startedStore(library)

        #expect(await eventually { !library.reconciled.isEmpty })
        #expect(library.reconciled == [["tagged"]])
        #expect(library.keywords(of: "tagged") == ["旅行"])
        #expect(library.keywords(of: "imported") == ["Fujifilm", "Kanagawa"])
    }

    /// 照片库把关键词改成了别的写法（例如规范化大小写）：同一组标签只改一次，不来回改个没完。
    @Test func keywordReconcileDoesNotLoop() async {
        let library = FakeLibrary()
        library.seed("a", caption: "猫 #Cat#", keywords: ["dog"], date: date(2026, 10, 1))
        let store = await startedStore(library)
        #expect(await eventually { library.reconciled.count == 1 })
        library.externalUpdate("a") { $0.keywords = ["cat"] }
        #expect(await eventually { store.entry("a")?.keywords == ["cat"] })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(library.reconciled.count == 1)
        // 标签真的变了，照样改。
        library.externalEdit("a", caption: "猫 #Cat# #宠物#")
        #expect(await eventually { library.reconciled.count == 2 })
    }

    @Test func keywordChangeIsMinimal() {
        let change = LibraryScanner.keywordChange(tags: ["旅行", "镜头", "旅行"], current: ["镜头", "旧"])
        #expect(change.remove == ["旧"])
        #expect(change.add == ["旅行"])
        #expect(LibraryScanner.keywordChange(tags: ["a"], current: ["a"]) == ([], []))
        #expect(LibraryScanner.keywordChange(tags: [], current: ["a", "b"]) == (["a", "b"], []))
    }

    // MARK: 地名

    @Test func failedPlaceLookupIsNotRetriedInSameRun() async {
        let places = FakePlaceNamer() // 什么都查不到
        let library = FakeLibrary()
        library.seed("a", caption: "某处", date: date(2026, 10, 1), latitude: 10, longitude: 10)
        let store = await startedStore(library, places: places)
        #expect(await eventually { places.lookups == 1 })

        library.externalEdit("a", caption: "某处，改过")
        #expect(await eventually { store.entry("a")?.caption == "某处，改过" })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(places.lookups == 1)
        #expect(store.entry("a")?.placeName == nil)
    }

    @Test func placeTimeZoneDecidesPhotoDay() async {
        // UTC 10:00 在基里巴斯（UTC+14）已经是第二天 0 点，不管模拟器在哪个时区。
        let shot = ISO8601DateFormatter().date(from: "2026-10-31T10:00:00Z")!
        let places = FakePlaceNamer()
        places.set("圣诞岛", timeZone: "Pacific/Kiritimati", latitude: 1.87, longitude: -157.4)
        let library = FakeLibrary()
        library.seed("a", caption: "跨日线", date: shot, latitude: 1.87, longitude: -157.4)
        let store = await startedStore(library, places: places)

        #expect(await eventually { store.entry("a")?.timeZoneID == "Pacific/Kiritimati" })
        #expect(store.entry("a")?.day == DayStamp(year: 2026, month: 11, day: 1))
        #expect(store.entries(on: DayStamp(year: 2026, month: 11, day: 1)!).map(\.id) == ["a"])
    }
}
