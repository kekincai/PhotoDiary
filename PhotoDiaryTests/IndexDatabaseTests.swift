import Testing
import Foundation
import SwiftData
@testable import PhotoDiary

func sampleEntry(_ id: String, caption: String = "一\n— 2026.10.30", place: String? = nil) -> DiaryEntry {
    DiaryEntry(id: id, caption: caption, keywords: [], creationDate: date(2026, 10, 30), latitude: 35.4, longitude: 139.6,
               mediaKind: .livePhoto, isCloudShared: false, pixelWidth: 4, pixelHeight: 3, placeName: place)
}

/// 数据库本身：只写变化的行、解析结果缓存、损坏重建、不进备份。
struct IndexDatabaseTests {
    let dir = temporaryDirectory()

    @Test func roundTrip() async throws {
        let db = await IndexDatabase.open(directory: dir)
        var entry = sampleEntry("a", caption: "海边 #旅行#\n— 2026.10.30\n\n再看\n— 2026.10.31", place: "横滨")
        entry.timeZoneID = "Asia/Tokyo"
        entry.writtenInApp = true
        try await db.apply(.init(upserts: [entry], changeToken: Data("7".utf8),
                                 places: ["35.40,139.60": ("横滨", "Asia/Tokyo")]))

        let loaded = await loadIndex(dir)
        #expect(loaded.entries == [entry])
        #expect(loaded.entries.first?.title == "海边")
        #expect(loaded.changeToken == Data("7".utf8))
        #expect(loaded.places == PlaceCache(names: ["35.40,139.60": "横滨"], timeZones: ["35.40,139.60": "Asia/Tokyo"]))
    }

    @Test func applyTouchesOnlyGivenRows() async throws {
        let db = await IndexDatabase.open(directory: dir)
        try await db.apply(.init(upserts: [sampleEntry("a"), sampleEntry("b"), sampleEntry("c")]))
        let stats = try await db.apply(.init(upserts: [sampleEntry("b", caption: "二（改）")], deletions: ["c"], changeToken: Data("2".utf8)))
        #expect(stats == .init(upserted: 1, deleted: 1))

        let loaded = await db.load()
        #expect(Set(loaded.entries.map(\.id)) == ["a", "b"])
        #expect(loaded.entries.first { $0.id == "b" }?.caption == "二（改）")
        #expect(loaded.changeToken == Data("2".utf8))
    }

    @Test func storedParseResultIsUsedWhenParserVersionMatches() async throws {
        let db = await IndexDatabase.open(directory: dir)
        try await db.apply(.init(upserts: [sampleEntry("a", caption: "真正的标题。正文")]))
        // 改掉库里存的解析结果：读出来的是存着的那份，说明没有重新解析。
        try await db.tamperDisplay(id: "a", title: "库里存的标题", version: CaptionDisplay.version)
        #expect(await db.load().entries.first?.title == "库里存的标题")

        // 解析规则版本对不上就重新解析，并写回库里。
        try await db.tamperDisplay(id: "a", title: "旧规则的标题", version: CaptionDisplay.version - 1)
        #expect(await db.load().entries.first?.title == "真正的标题。")
        #expect(await loadIndex(dir).entries.first?.title == "真正的标题。")
    }

    @Test func corruptedEntriesStoreIsRebuiltAndPlacesSurvive() async throws {
        do {
            let db = await IndexDatabase.open(directory: dir)
            try await db.apply(.init(upserts: [sampleEntry("a")], changeToken: Data("1".utf8), places: ["1.00,1.00": ("某地", nil)]))
        }
        let store = indexFolder(dir).appending(path: IndexDatabase.entriesStoreName)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(filePath: store.path() + suffix)) }
        try Data("not a database".utf8).write(to: store)

        let db = await IndexDatabase.open(directory: dir)
        let loaded = await db.load()
        #expect(loaded.entries.isEmpty)
        #expect(loaded.changeToken == nil)
        #expect(loaded.places.names == ["1.00,1.00": "某地"])
        // 重建后照常能写。
        try await db.apply(.init(upserts: [sampleEntry("b")]))
        #expect(await db.load().entries.map(\.id) == ["b"])
    }

    @Test func indexFolderIsExcludedFromBackup() async throws {
        let db = await IndexDatabase.open(directory: dir)
        try await db.apply(.init(upserts: [sampleEntry("a")]))
        #expect(try indexFolder(dir).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}

/// DiaryStore 和数据库：只写变化的行、损坏重建、后台落盘。
struct IndexPersistenceTests {
    @Test func incrementalSyncWritesOnlyChangedRows() async {
        let library = FakeLibrary()
        for i in 0..<100 { library.seed("p\(i)", caption: "第 \(i) 篇", date: date(2026, 1, 1).addingTimeInterval(Double(i) * 86_400)) }
        let store = await startedStore(library)
        #expect(await eventually { store.lastSaveStats == .init(upserted: 100, deleted: 0) })

        library.externalEdit("p7", caption: "第 7 篇（改）")
        #expect(await eventually { store.lastSaveStats == .init(upserted: 1, deleted: 0) })
        library.externalEdit("p8", caption: nil)
        #expect(await eventually { store.lastSaveStats == .init(upserted: 0, deleted: 1) })
    }

    /// 全量重读（token 失效、手动重建）也只写和库里不一样的行。
    @Test func fullRescanWritesOnlyDifferences() async {
        let library = FakeLibrary()
        for i in 0..<50 { library.seed("p\(i)", caption: "第 \(i) 篇", date: date(2026, 1, 1).addingTimeInterval(Double(i) * 86_400)) }
        let store = await startedStore(library)
        #expect(await eventually { store.lastSaveStats?.upserted == 50 })

        library.externalEdit("p3", caption: "第 3 篇（改）", notify: false)
        library.externalEdit("p4", caption: nil, notify: false)
        store.rebuildIndex()
        #expect(await eventually { library.fullScans == 2 && store.syncState == .idle })
        #expect(await eventually { store.lastSaveStats == .init(upserted: 1, deleted: 1) })
    }

    @Test func placesSurviveCorruptedEntriesStore() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "港口", date: date(2026, 10, 1), latitude: 35.44, longitude: 139.64)
        do {
            let places = FakePlaceNamer()
            places.set("横滨", timeZone: "Asia/Tokyo", latitude: 35.44, longitude: 139.64)
            let first = await startedStore(library, places: places, directory: dir)
            #expect(await eventually { first.entry("a")?.placeName == "横滨" })
            await first.saveNow()
        }
        let store = indexFolder(dir).appending(path: IndexDatabase.entriesStoreName)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(filePath: store.path() + suffix)) }
        try Data("not a database".utf8).write(to: store)

        let namer = FakePlaceNamer()
        let second = await startedStore(library, places: namer, directory: dir)
        #expect(library.fullScans == 2)
        #expect(await eventually { second.entry("a")?.placeName == "横滨" })
        #expect(second.entry("a")?.timeZoneID == "Asia/Tokyo")
        #expect(namer.lookups == 0)
    }

    @Test func saveNowSkipsDebounce() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let store = makeStore(library: library, directory: dir, saveDelay: .seconds(60))
        await store.start()
        #expect(await eventually { store.hasSynced })
        #expect(store.lastSaveStats == nil)

        await store.saveNow()
        #expect(store.lastSaveStats == .init(upserted: 1, deleted: 0))
        #expect(await loadIndex(dir).entries.map(\.id) == ["a"])
    }

    @Test func unchangedIncrementalDoesNotWrite() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let first = await startedStore(library, directory: dir)
        await first.saveNow()

        let second = await startedStore(library, directory: dir)
        #expect(library.incrementals == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(second.lastSaveStats == nil)
        #expect(second.diaries.count == 1)
    }

    /// 上次地名查到一半 App 被结束：下次启动即使照片库没变，也要接着查。
    @Test func unchangedIncrementalStillResolvesMissingPlaces() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "港口", date: date(2026, 10, 1), latitude: 35.44, longitude: 139.64)
        let first = await startedStore(library, places: FakePlaceNamer(), directory: dir) // 查不到
        await first.saveNow()

        let places = FakePlaceNamer()
        places.set("横滨", latitude: 35.44, longitude: 139.64)
        let second = await startedStore(library, places: places, directory: dir)
        #expect(await eventually { second.entry("a")?.placeName == "横滨" })
        #expect(library.fullScans == 1)
    }

    @Test func saveNowBeforeLoadingWritesNothing() async {
        let dir = temporaryDirectory()
        let store = makeStore(library: FakeLibrary(), directory: dir)
        await store.saveNow()
        #expect(store.lastSaveStats == nil)
        #expect(!FileManager.default.fileExists(atPath: indexFolder(dir).path()))
    }
}

extension IndexDatabase {
    /// 测试用：直接改库里存的解析结果。
    func tamperDisplay(id: String, title: String, version: Int) throws {
        let record = try #require(try modelContext.fetch(FetchDescriptor<EntryRecord>()).first { $0.id == id })
        var display = try JSONDecoder().decode(CaptionDisplay.self, from: record.display)
        display.title = title
        record.display = try JSONEncoder().encode(display)
        record.displayVersion = version
        try modelContext.save()
    }
}
