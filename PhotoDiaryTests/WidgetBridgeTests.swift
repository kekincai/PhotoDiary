import Testing
import Foundation
import Photos
@testable import PhotoDiary

/// App 写给小组件的快照：写进共享容器，日记变了跟着变；撤销照片权限后不留旧的日记和照片。
/// WidgetBridge 和共享容器都是全 App 一份，这些测试依次执行。
@Suite(.serialized, .enabled(if: WidgetSnapshot.directory != nil, "需要 App Group 的共享容器"))
@MainActor
struct WidgetBridgeTests {
    let bridge = WidgetBridge.shared

    @Test func writesOnThisDayIntoSharedContainer() async throws {
        let library = FakeLibrary()
        let today = DayStamp.today
        let lastYear = Calendar.diary.date(from: DateComponents(year: today.year - 1, month: today.month, day: today.day, hour: 12))!
        library.seed("去年/L0/001", caption: "去年今天。\n— \(DayStamp(lastYear).captionString)", date: lastYear)
        let store = await startedStore(library, clock: TestClock(.now))
        bridge.attach(store: store)
        await bridge.updateNow()
        let snapshot = try #require(WidgetSnapshot.load())
        #expect(snapshot.memories.map(\.id) == ["去年/L0/001"])
        #expect(snapshot.today == today)
    }

    /// 撤销权限后冷启动：索引不会读（hasLoaded 一直是 false），也要把共享容器里的旧快照和缩略图清掉。
    @Test func revokedAccessClearsWidgetData() async throws {
        let directory = try #require(WidgetSnapshot.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = directory.appending(path: WidgetSnapshot.thumbnailName(for: "旧/L0/001"))
        try Data([0xFF, 0xD8]).write(to: stale)
        let old = WidgetSnapshot(generated: .now, today: .today, language: "zh-Hans", wroteToday: true,
                                 memories: [WidgetMemory(id: "旧/L0/001", day: .today, title: "旧的", preview: "")])
        try JSONEncoder().encode(old).write(to: try #require(WidgetSnapshot.fileURL))

        let library = FakeLibrary()
        library.setAuthorization(.denied)
        let store = makeStore(library: library)
        await store.start()
        #expect(!store.hasLoaded)
        bridge.attach(store: store)
        await bridge.updateNow()

        let snapshot = try #require(WidgetSnapshot.load())
        #expect(snapshot.memories.isEmpty)
        #expect(!snapshot.wroteToday)
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
    }
}
