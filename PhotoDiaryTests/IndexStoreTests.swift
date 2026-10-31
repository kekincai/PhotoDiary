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
        #expect(loaded.placeCache == ["35.40,139.60": "横滨"])
        #expect(loaded.timeZoneCache == ["35.40,139.60": "Asia/Tokyo"])
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
        index.remove()
        #expect(!FileManager.default.fileExists(atPath: index.fileURL.path()))
    }
}
