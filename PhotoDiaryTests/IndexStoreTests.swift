import Testing
import Foundation
@testable import PhotoDiary

struct IndexStoreTests {
    let index = IndexStore(directory: temporaryDirectory())

    @Test func roundTrip() async throws {
        let entry = DiaryEntry(id: "a", caption: "一\n— 2026.10.30", keywords: [], creationDate: date(2026, 10, 30),
                               latitude: 35.4, longitude: 139.6, mediaKind: .livePhoto, isCloudShared: false,
                               pixelWidth: 4, pixelHeight: 3, placeName: "横滨")
        let snapshot = IndexSnapshot(entries: [entry], changeToken: Data("7".utf8), writtenInApp: ["a"],
                                     placeCache: ["35.40,139.60": "横滨"], timeZoneCache: ["35.40,139.60": "Asia/Tokyo"])
        await index.save(snapshot)

        let loaded = try #require(await index.load())
        #expect(loaded.entries == [entry])
        #expect(loaded.changeToken == Data("7".utf8))
        #expect(loaded.writtenInApp == ["a"])
        // 地名缓存不再写进索引，单独存。
        #expect(loaded.placeCache.isEmpty)

        let places = PlaceCache(names: ["35.40,139.60": "横滨"], timeZones: ["35.40,139.60": "Asia/Tokyo"])
        await index.savePlaces(places)
        #expect(await index.loadPlaces() == places)
    }

    @Test func missingFileLoadsNil() async {
        #expect(await index.load() == nil)
    }

    @Test func corruptedFileLoadsNil() async throws {
        try Data("{not json".utf8).write(to: index.fileURL)
        #expect(await index.load() == nil)
    }

    @Test func otherVersionLoadsNil() async throws {
        var snapshot = IndexSnapshot()
        snapshot.version = IndexSnapshot.currentVersion - 1
        await index.save(snapshot)
        #expect(await index.load() == nil)
    }

    @Test func removeDeletesFile() async {
        await index.save(IndexSnapshot())
        await index.savePlaces(PlaceCache())
        index.remove()
        #expect(!FileManager.default.fileExists(atPath: index.fileURL.path()))
        #expect(!FileManager.default.fileExists(atPath: index.placesURL.path()))
    }
}

/// 索引在 DiaryStore 里的生命周期：备份、地名缓存、后台落盘。
struct IndexPersistenceTests {
    @Test func filesAreExcludedFromBackup() async throws {
        let index = IndexStore(directory: temporaryDirectory())
        await index.save(IndexSnapshot())
        await index.savePlaces(PlaceCache(names: ["1.00,1.00": "某地"]))
        // 再写一次：原子写入换了文件，标记要还在。
        await index.save(IndexSnapshot())
        for url in [index.fileURL, index.placesURL] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
    }

    @Test func placeCacheSurvivesIndexVersionBump() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "港口", date: date(2026, 10, 1), latitude: 35.44, longitude: 139.64)
        let places = FakePlaceNamer()
        places.set("横滨", timeZone: "Asia/Tokyo", latitude: 35.44, longitude: 139.64)
        let first = await startedStore(library, places: places, directory: dir)
        #expect(await eventually { first.entry("a")?.placeName == "横滨" })
        await first.saveNow()

        // 新版本 App 不认旧索引。
        var old = IndexSnapshot()
        old.version = IndexSnapshot.currentVersion - 1
        await IndexStore(directory: dir).save(old)

        let freshNamer = FakePlaceNamer()
        let second = await startedStore(library, places: freshNamer, directory: dir)
        #expect(library.fullScans == 2)
        #expect(await eventually { second.entry("a")?.placeName == "横滨" })
        #expect(second.entry("a")?.timeZoneID == "Asia/Tokyo")
        #expect(freshNamer.lookups == 0)
    }

    @Test func placeCacheMigratesFromOldIndex() async throws {
        let dir = temporaryDirectory()
        // 旧版本：地名缓存写在索引里，没有 place-cache.json。
        let legacy = IndexSnapshot(placeCache: ["35.44,139.64": "横滨"], timeZoneCache: ["35.44,139.64": "Asia/Tokyo"])
        try JSONEncoder().encode(legacy).write(to: IndexStore(directory: dir).fileURL)

        let library = FakeLibrary()
        library.seed("a", caption: "港口", date: date(2026, 10, 1), latitude: 35.44, longitude: 139.64)
        let namer = FakePlaceNamer()
        let store = await startedStore(library, places: namer, directory: dir)
        #expect(store.entry("a")?.placeName == "横滨")
        #expect(namer.lookups == 0)

        await store.saveNow()
        #expect(await IndexStore(directory: dir).loadPlaces()?.names == ["35.44,139.64": "横滨"])
        let rewritten = try JSONSerialization.jsonObject(with: Data(contentsOf: IndexStore(directory: dir).fileURL)) as? [String: Any]
        #expect((rewritten?["placeCache"] as? [String: String])?.isEmpty == true)
    }

    @Test func saveNowSkipsDebounce() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let store = makeStore(library: library, directory: dir, saveDelay: .seconds(60))
        await store.start()
        #expect(await eventually { store.hasSynced })
        #expect(!FileManager.default.fileExists(atPath: IndexStore(directory: dir).fileURL.path()))

        await store.saveNow()
        #expect(await IndexStore(directory: dir).load()?.entries.map(\.id) == ["a"])
    }

    @Test func unchangedIncrementalDoesNotRewriteIndex() async throws {
        let dir = temporaryDirectory()
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let first = await startedStore(library, directory: dir)
        await first.saveNow()
        let index = IndexStore(directory: dir)
        let written = try index.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let second = await startedStore(library, directory: dir)
        #expect(library.incrementals == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(try index.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == written)
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
        #expect(!FileManager.default.fileExists(atPath: IndexStore(directory: dir).fileURL.path()))
    }
}
