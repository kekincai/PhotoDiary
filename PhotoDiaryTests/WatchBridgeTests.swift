import Testing
import Foundation
import Photos
import WatchConnectivity
@testable import PhotoDiary

/// 表上口述的感想发到 iPhone：写进照片说明；写不进去就留在队列里，之后再补写；同一段只写一次。
/// WatchBridge 是全 App 一份，这些测试依次执行。
@Suite(.serialized)
struct WatchBridgeTests {
    let bridge = WatchBridge.shared

    init() {
        bridge.resetForTesting()
    }

    @Test func newDiaryFromWatchIsWrittenIntoCaption() async throws {
        let library = FakeLibrary()
        library.seed("p", caption: nil, date: date(2026, 10, 31))
        let store = await startedStore(library)
        bridge.attach(store: store)

        let write = WatchWrite(assetID: "p", text: "在表上说的 #散步#", mode: .new)
        #expect(await bridge.handle(.write(write)) == .ok)
        #expect(await eventually { library.caption(of: "p") == "在表上说的 #散步#\n— 2026.10.31" })
        #expect(await eventually { bridge.pendingWrites.isEmpty })
        #expect(store.entry("p")?.tags == ["散步"])
    }

    @Test func appendFromWatchKeepsEarlierText() async throws {
        let library = FakeLibrary()
        library.seed("p", caption: "原来的\n— 2026.10.01", date: date(2026, 10, 1))
        let store = await startedStore(library)
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "p", text: "再看一次", mode: .append)))
        #expect(await eventually { library.caption(of: "p") == "原来的\n— 2026.10.01\n\n再看一次\n— 2026.10.31" })
    }

    /// 同一段（重发、userInfo 队列和消息都到了）只写一次。
    @Test func duplicateWriteIsWrittenOnce() async throws {
        let library = FakeLibrary()
        library.seed("p", caption: nil, date: date(2026, 10, 31))
        let store = await startedStore(library)
        bridge.attach(store: store)

        let write = WatchWrite(assetID: "p", text: "只写一次", mode: .append)
        _ = await bridge.handle(.write(write))
        _ = await bridge.handle(.write(write))
        #expect(await eventually { bridge.pendingWrites.isEmpty })
        // 消息的回复丢了，表改走 userInfo 队列又发了一遍：已经写过，不再写。
        _ = await bridge.handle(.write(write))
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.writes.count == 1)
    }

    /// 没有照片权限时先留着，有了权限、回到前台再写。
    @Test func writeWaitsForPhotoAccess() async throws {
        let library = FakeLibrary()
        library.seed("p", caption: nil, date: date(2026, 10, 31))
        library.setAuthorization(.denied)
        let store = makeStore(library: library)
        await store.start()
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "p", text: "等权限", mode: .new)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(bridge.pendingWrites.count == 1)
        #expect(library.writes.isEmpty)

        library.setAuthorization(.authorized)
        store.refreshAuthorization()
        bridge.resume()
        #expect(await eventually { library.caption(of: "p")?.hasPrefix("等权限") == true })
        #expect(await eventually { bridge.pendingWrites.isEmpty })
    }

    /// 照片已经删了（表上的快照是旧的）：不假装写进去了，移出队列（字留在表上），也不挡住后面的。
    @Test func writeToDeletedPhotoIsDroppedAndDoesNotBlockQueue() async throws {
        let library = FakeLibrary()
        library.seed("在", caption: nil, date: date(2026, 10, 31))
        let store = await startedStore(library)
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "删了", text: "写不进去", mode: .new)))
        _ = await bridge.handle(.write(WatchWrite(assetID: "在", text: "后面这段照写", mode: .new)))
        #expect(await eventually { library.caption(of: "在")?.hasPrefix("后面这段照写") == true })
        #expect(await eventually { bridge.pendingWrites.isEmpty })
        #expect(library.caption(of: "删了") == nil)
    }

    /// 共享相簿里别人的照片改不了说明：同样移出队列，不会每次回到前台都卡在这一段上。
    @Test func writeToLockedPhotoIsDropped() async throws {
        let library = FakeLibrary()
        library.seed("共享", caption: nil, date: date(2026, 10, 31))
        library.lock("共享")
        let store = await startedStore(library)
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "共享", text: "改不了", mode: .new)))
        #expect(await eventually { bridge.pendingWrites.isEmpty })
        #expect(library.writes.isEmpty)
    }

    /// 暂时写不进去的一段留在队列里，但不挡住后面的；下次回到前台再写。
    @Test func temporaryFailureKeepsWriteButLetsOthersThrough() async throws {
        let library = FakeLibrary()
        library.seed("a", caption: nil, date: date(2026, 10, 30))
        library.seed("b", caption: nil, date: date(2026, 10, 31))
        library.failWrites(to: ["a"])
        let store = await startedStore(library)
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "a", text: "先卡住", mode: .new)))
        _ = await bridge.handle(.write(WatchWrite(assetID: "b", text: "照样写", mode: .new)))
        #expect(await eventually { library.caption(of: "b")?.hasPrefix("照样写") == true })
        #expect(await eventually { bridge.pendingWrites.map(\.assetID) == ["a"] })

        library.failWrites(to: [])
        bridge.resume()
        #expect(await eventually { library.caption(of: "a")?.hasPrefix("先卡住") == true })
        #expect(await eventually { bridge.pendingWrites.isEmpty })
    }

    /// 正在写的时候又到了几段（表离线时攒下的，连上后连着送到）：这次就都写完，不等下次回到前台。
    @Test func writesArrivingWhileDrainingAreWrittenToo() async throws {
        let library = FakeLibrary()
        for id in ["a", "b", "c"] { library.seed(id, caption: nil, date: date(2026, 10, 31)) }
        library.delayWrites(.milliseconds(100))
        let store = await startedStore(library)
        bridge.attach(store: store)

        _ = await bridge.handle(.write(WatchWrite(assetID: "a", text: "一", mode: .new)))
        try await Task.sleep(for: .milliseconds(30))
        _ = await bridge.handle(.write(WatchWrite(assetID: "b", text: "二", mode: .new)))
        _ = await bridge.handle(.write(WatchWrite(assetID: "c", text: "三", mode: .new)))
        #expect(await eventually { library.writes.count == 3 })
        #expect(await eventually { bridge.pendingWrites.isEmpty })
    }

    /// WCSession 在自己的后台队列上调代理：不能因为隔离不对而终止，消息要交到主线程处理、回复要送回去。
    @Test func delegateCallbacksArriveOffMainThread() async throws {
        let library = FakeLibrary()
        library.seed("p", caption: nil, date: date(2026, 10, 31))
        let store = await startedStore(library)
        bridge.attach(store: store)
        nonisolated(unsafe) let session = WCSession.default
        nonisolated(unsafe) let delegate: any WCSessionDelegate = bridge

        let reply = await withCheckedContinuation { (done: CheckedContinuation<Data, Never>) in
            DispatchQueue.global().async {
                delegate.session?(session, didReceiveMessageData: WatchMessage.ok.data) { done.resume(returning: $0) }
            }
        }
        #expect(WatchMessage(data: reply) == .ok)

        let write = WatchWrite(assetID: "p", text: "从后台队列来的", mode: .new)
        DispatchQueue.global().async {
            delegate.session?(session, didReceiveUserInfo: WatchMessage.write(write).userInfo)
        }
        #expect(await eventually { library.caption(of: "p")?.hasPrefix("从后台队列来的") == true })

        DispatchQueue.global().async {
            delegate.sessionWatchStateDidChange?(session)
            delegate.sessionDidBecomeInactive(session)
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    /// 要缩略图时照片不在照片库里：回一个空的结果，不崩。
    @Test func thumbnailsForMissingPhotosAreEmpty() async {
        let reply = await bridge.handle(.thumbnails(ids: ["不存在/L0/001"]))
        #expect(reply == .images([:]))
    }

    @Test func otherMessagesAreAcknowledged() async {
        #expect(await bridge.handle(.ok) == .ok)
        #expect(await bridge.handle(.wrote(UUID())) == .ok)
    }
}
