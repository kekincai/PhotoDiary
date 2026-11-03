import Testing
import Foundation
import Photos
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
