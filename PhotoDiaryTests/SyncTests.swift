import Testing
import Foundation
import Photos
@testable import PhotoDiary

/// 同步的并发与取消：任何时刻只有一个同步在跑，被取消的读取不留下任何痕迹。
struct SyncTests {
    @Test func syncDuringScanIsCoalescedIntoOneIncremental() async {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        library.seed("b", caption: "二", date: date(2026, 10, 2))
        library.seed("c", caption: "三", date: date(2026, 10, 3))
        library.holdScans()
        let store = makeStore(library: library)
        await store.start()
        #expect(await eventually { store.syncState != .idle })

        store.sync()
        store.sync()
        #expect(library.fullScans == 1)
        library.releaseScans()

        #expect(await eventually { library.incrementals == 1 })
        #expect(await eventually { store.syncState == .idle })
        #expect(library.fullScans == 1)
        #expect(store.diaries.count == 3)
    }

    /// 回归：rebuildIndex 取消旧读取后，旧任务结束时曾把新任务的引用清掉，之后会同时跑两个同步。
    @Test func rebuildDuringScanKeepsASingleSync() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一 #旅行#", date: date(2026, 10, 1))
        library.seed("b", caption: "二", date: date(2026, 10, 2))
        library.seed("c", caption: "三", date: date(2026, 10, 3))
        library.holdScans()
        let store = makeStore(library: library)
        await store.start()
        #expect(await eventually { store.syncState != .idle })

        store.rebuildIndex()
        #expect(await eventually { library.fullScans == 2 })
        try await Task.sleep(for: .milliseconds(50)) // 让被取消的旧任务走完

        // 被取消的读取不算同步完成，也不改写关键词。
        #expect(!store.hasSynced)
        #expect(store.syncState != .idle)
        #expect(library.reconciled.isEmpty)

        // 新读取还在进行，再要求同步只能排队。
        store.sync()
        #expect(library.fullScans == 2)

        library.releaseScans()
        #expect(await eventually { store.hasSynced && store.syncState == .idle && library.incrementals == 1 })
        #expect(library.fullScans == 2)
        #expect(store.diaries.count == 3)
    }

    @Test func cancelledScanDoesNotReplaceEntriesOrToken() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        let dir = temporaryDirectory()
        let first = await startedStore(library, directory: dir)
        #expect(first.diaries.count == 1)

        // 重建时照片库里多了几篇；重建在读完第一批时又被重建取代。
        library.seed("b", caption: "二", date: date(2026, 10, 2))
        library.seed("c", caption: "三", date: date(2026, 10, 3))
        library.holdScans()
        first.rebuildIndex()
        #expect(await eventually { library.fullScans == 2 })
        first.rebuildIndex()
        #expect(await eventually { library.fullScans == 3 })
        try await Task.sleep(for: .milliseconds(50))
        library.releaseScans()

        #expect(await eventually { first.syncState == .idle && first.diaries.count == 3 })
        #expect(library.fullScans == 3)
    }

    /// 回归：有限访问时建的索引，改成完整访问后只走增量，之前看不到的日记一直不出现。
    @Test func accessChangeWhileRunningRescansLibrary() async {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        library.setAuthorization(.limited)
        let store = await startedStore(library)
        #expect(library.fullScans == 1)

        library.setAuthorization(.authorized)
        store.refreshAuthorization()
        #expect(await eventually { library.fullScans == 2 && store.syncState == .idle })
        #expect(library.incrementals == 0)
    }

    @Test func accessChangeWhileClosedRescansOnLaunch() async {
        let library = FakeLibrary()
        library.seed("a", caption: "一", date: date(2026, 10, 1))
        library.setAuthorization(.limited)
        let dir = temporaryDirectory()
        let first = await startedStore(library, directory: dir)
        await first.saveNow()

        // 权限没变：增量。
        let second = await startedStore(library, directory: dir)
        await second.saveNow()
        #expect(library.fullScans == 1)
        #expect(library.incrementals == 1)

        // 关着 App 时在系统设置里改成完整访问：全库重读。
        library.setAuthorization(.authorized)
        let third = await startedStore(library, directory: dir)
        #expect(library.fullScans == 2)
        #expect(third.diaries.count == 1)
    }
}
