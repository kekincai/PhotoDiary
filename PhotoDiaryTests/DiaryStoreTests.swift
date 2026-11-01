import Testing
import Foundation
@testable import PhotoDiary

/// DiaryStore 和假照片库一起跑，确认依赖注入可用。更细的同步、派生数据测试见计划阶段 2。
struct DiaryStoreTests {
    @Test func firstLaunchReadsWholeLibraryAndSavesIndex() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "海边 #旅行#\n— 2026.10.30", date: date(2026, 10, 30))
        library.seed("b", caption: "OLYMPUS DIGITAL CAMERA", date: date(2026, 10, 29))
        library.seed("c", caption: "  ", date: date(2026, 10, 28))
        library.seed("d", caption: nil, date: date(2026, 10, 27))
        let dir = temporaryDirectory()
        let store = makeStore(library: library, directory: dir)

        await store.start()
        #expect(await eventually { store.hasSynced })

        #expect(store.diaries.map(\.id) == ["a"])
        #expect(store.tagCounts == [.init(name: "旅行", count: 1)])
        #expect(library.fullScans == 1)

        #expect(await eventually { store.lastSaveStats != nil })
        let index = await loadIndex(dir)
        #expect(index.entries.map(\.id) == ["a"])
        #expect(index.changeToken != nil)
    }

    @Test func relaunchShowsIndexFirstThenSyncsIncrementally() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "第一篇\n— 2026.10.30", date: date(2026, 10, 30))
        let dir = temporaryDirectory()
        let first = makeStore(library: library, directory: dir)
        await first.start()
        #expect(await eventually { first.hasSynced })
        await first.saveNow()

        // App 关闭期间在照片 App 里多写了一篇（关闭时收不到通知）。
        library.externalEdit("b", caption: "第二篇", notify: false)

        let second = makeStore(library: library, directory: dir)
        await second.start()
        // 增量结果回来之前，先显示索引里的内容。
        #expect(second.diaries.map(\.id) == ["a"])
        #expect(await eventually { second.diaries.count == 2 })
        #expect(library.fullScans == 1)
        #expect(library.incrementals == 1)
    }

    @Test func expiredTokenFallsBackToFullScan() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一\n— 2026.10.30", date: date(2026, 10, 30))
        let dir = temporaryDirectory()
        let first = makeStore(library: library, directory: dir)
        await first.start()
        #expect(await eventually { first.hasSynced })
        await first.saveNow()

        library.expireTokens()
        let second = makeStore(library: library, directory: dir)
        await second.start()
        #expect(await eventually { library.fullScans == 2 })
        #expect(await eventually { second.hasSynced })
        #expect(second.diaries.map(\.id) == ["a"])
    }

    @Test func externalEditArrivesThroughObserver() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "原来的\n— 2026.10.30", date: date(2026, 10, 30))
        let store = makeStore(library: library)
        await store.start()
        #expect(await eventually { store.hasSynced })

        library.externalEdit("a", caption: "在照片 App 里改过")
        #expect(await eventually { store.entry("a")?.caption == "在照片 App 里改过" })

        library.externalEdit("a", caption: nil)
        #expect(await eventually { store.entry("a") == nil })
    }

    @Test func savingUsesInjectedClockForDateLine() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: nil, date: date(2026, 10, 1))
        let store = makeStore(library: library)
        await store.start()
        #expect(await eventually { store.hasSynced })

        try await store.save(text: "夕阳 ＃旅行＃", mode: .new, for: "a")
        #expect(library.caption(of: "a") == "夕阳 #旅行#\n— 2026.10.31")
        #expect(library.keywords(of: "a") == ["旅行"])
        #expect(store.entry("a")?.writtenInApp == true)
    }

    @Test func captionFilterReadsInjectedDefaults() async throws {
        let defaults = isolatedDefaults()
        defaults.set(["0"], forKey: CaptionFilter.defaultsKey)
        let library = FakeLibrary()
        library.seed("a", caption: "0", date: date(2026, 10, 30))
        let store = makeStore(library: library, defaults: defaults)
        await store.start()
        #expect(await eventually { store.hasSynced })
        #expect(store.diaries.isEmpty)

        // 被过滤的说明在写日记时直接覆盖。
        try await store.save(text: "夕阳", mode: .new, for: "a")
        #expect(library.caption(of: "a") == "夕阳\n— 2026.10.31")
    }

    @Test func placeNamesComeFromInjectedNamer() async throws {
        let places = FakePlaceNamer()
        places.set("横滨", timeZone: "Asia/Tokyo", latitude: 35.44, longitude: 139.64)
        let library = FakeLibrary()
        library.seed("a", caption: "港口\n— 2026.10.30", date: date(2026, 10, 30), latitude: 35.443, longitude: 139.638)
        library.seed("b", caption: "同一个地方\n— 2026.10.30", date: date(2026, 10, 29), latitude: 35.441, longitude: 139.641)
        let store = makeStore(library: library, places: places)
        await store.start()

        #expect(await eventually { store.entry("a")?.placeName == "横滨" && store.entry("b")?.placeName == "横滨" })
        #expect(places.lookups == 1)
        #expect(store.places.map(\.name) == ["横滨"])
    }
}
