import Testing
import Foundation
@testable import PhotoDiary

/// 保存和同步同时发生：同步读到的是保存之前的照片库，交回来时不能盖掉刚保存的内容。
/// 回归：在真实照片库上改标签后，列表里短暂显示改名前的标签（真实照片库测试里发现）。
struct WriteRaceTests {
    @Test func incrementalReadBeforeSaveDoesNotOverwriteSavedEntry() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "原来的", date: date(2026, 10, 1))
        let store = await startedStore(library)

        // 照片 App 里改了一下，增量读取读到“外面改的”，还没交回来。
        library.holdIncrementals()
        library.externalEdit("a", caption: "外面改的")
        #expect(await eventually { library.incrementalIsHeld })

        // 这时在 App 里保存。
        try await store.save(text: "App 里写的", mode: .edit, for: "a")
        #expect(store.entry("a")?.title == "App 里写的")

        library.releaseIncrementals()
        #expect(await eventually { store.syncState == .idle && !library.incrementalIsHeld })
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.entry("a")?.title == "App 里写的")
    }

    @Test func incrementalReadBeforeDeleteDoesNotBringEntryBack() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let store = await startedStore(library)

        library.holdIncrementals()
        library.externalEdit("a", caption: "改过")
        #expect(await eventually { library.incrementalIsHeld })
        try await store.delete(id: "a")
        #expect(store.entry("a") == nil)

        library.releaseIncrementals()
        #expect(await eventually { !library.incrementalIsHeld && store.syncState == .idle })
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.entry("a") == nil)
    }

    @Test func fullScanReadBeforeSaveDoesNotOverwriteSavedEntry() async throws {
        let library = FakeLibrary(batchSize: 1)
        library.seed("a", caption: "原来的 #甲#", date: date(2026, 10, 2))
        library.seed("b", caption: "二", date: date(2026, 10, 1))
        let store = await startedStore(library)

        // 重建索引：全量读取读到一半停住，这时保存。
        library.holdScans()
        store.rebuildIndex()
        #expect(await eventually { library.fullScans == 2 })
        try await store.save(text: "改名后 #乙#", mode: .edit, for: "a")

        library.releaseScans()
        #expect(await eventually { store.syncState == .idle && store.hasSynced })
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.entry("a")?.tags == ["乙"])
        #expect(store.entries(tagged: "甲").isEmpty)
    }

    /// 和真实照片库一样，自己的写入也会触发通知：最后仍是保存的内容，且不会重复全量读取。
    @Test func ownWriteNotificationsSettleOnSavedContent() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一 #散步#\n— 2026.10.01", date: date(2026, 10, 1))
        library.seed("b", caption: "二 #走路#", date: date(2026, 10, 2))
        library.notifyOwnWrites(true)
        let store = await startedStore(library)

        try await store.save(text: "追加", mode: .append, for: "a")
        try await store.renameTags(["散步", "走路"], to: "步行")
        #expect(store.entries(tagged: "步行").count == 2)
        #expect(await eventually { store.syncState == .idle && library.incrementals >= 1 })
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.entries(tagged: "步行").count == 2)
        #expect(store.entry("a")?.segments.count == 2)
        #expect(library.fullScans == 1)
    }
}
