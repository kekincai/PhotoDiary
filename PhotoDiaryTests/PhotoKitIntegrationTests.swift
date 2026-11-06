import Testing
import Foundation
import Photos
import UIKit
import CoreLocation
import UserNotifications
import ObjectiveC
@testable import PhotoDiary

/// 直接读写模拟器里的真实照片库：假照片库测不到 PhotoKit 在哪条线程回调、说明和关键词是不是真的写进去了。
/// 回归：保存说明后照片库在后台队列上发变更通知，主线程隔离的观察者让 App 直接终止（11 月 2 日的闪退）。
@Suite(.serialized, .enabled(if: PhotoFixtures.enabled, "需要在测试模拟器上授权照片访问（Tools/test.sh）"), .clearsCreatedCaptions)
struct PhotoKitIntegrationTests {
    init() {
        #expect(PhotoFixtures.authorized, "测试模拟器没有授权完整的照片访问")
    }

    // MARK: 后台线程回调

    /// 照片库的变更通知在后台队列上到：观察者必须收得到，而且不能因为线程不对而终止进程。
    @Test func changeObserverReceivesNotificationOffMainThread() async throws {
        let calls = Counter()
        let observer = ChangeObserver()
        observer.onChange = { _ in calls.value += 1 }
        PHPhotoLibrary.shared().register(observer)
        defer { PHPhotoLibrary.shared().unregisterChangeObserver(observer) }

        let id = try await PhotoFixtures.makePhoto()
        try await LibraryScanner.write(caption: "回调测试", to: id)
        #expect(await eventually(timeout: .seconds(10)) { calls.value > 0 })
    }

    /// App 里真正注册的两个观察者（取图缓存、增量同步）都在时保存说明。
    @Test func savingWithAppObserversRegisteredDoesNotCrash() async throws {
        let id = try await PhotoFixtures.makePhoto()
        _ = AssetImages.shared
        AssetImages.shared.warm(ids: [id])
        let changes = Counter()
        let token = PhotoKitLibrary().observeChanges { changes.value += 1 }
        defer { withExtendedLifetime(token) {} }

        try await LibraryScanner.write(caption: "保存不该闪退 #测试#", to: id)
        #expect(await eventually(timeout: .seconds(10)) { changes.value > 0 })
        // 再给取图缓存的观察者一点时间处理同一个通知。
        try await Task.sleep(for: .milliseconds(300))
        #expect(AssetImages.shared.asset(id) != nil)
    }

    // MARK: 说明和关键词

    @Test func captionAndKeywordsRoundTrip() async throws {
        let id = try await PhotoFixtures.makePhoto(date: date(2026, 10, 20))

        try await LibraryScanner.write(caption: "海边 #旅行# #夏天#\n— 2026.10.20", to: id)
        var stored = try #require(PhotoFixtures.metadata(id))
        #expect(stored.caption == "海边 #旅行# #夏天#\n— 2026.10.20")
        #expect(stored.keywords.sorted() == ["夏天", "旅行"])

        let entry = try #require(LibraryScanner.fetchEntries(ids: [id]).first)
        #expect(entry.tags.sorted() == ["夏天", "旅行"])
        #expect(entry.mediaKind == .photo)

        // 去掉一个标签：关键词跟着去掉。
        try await LibraryScanner.write(caption: "海边 #旅行#", to: id)
        stored = try #require(PhotoFixtures.metadata(id))
        #expect(stored.keywords == ["旅行"])

        // 清除说明：不再是日记，关键词也清掉。
        try await LibraryScanner.write(caption: nil, to: id)
        stored = try #require(PhotoFixtures.metadata(id))
        #expect(stored.caption?.isEmpty ?? true)
        #expect(stored.keywords.isEmpty)
        #expect(LibraryScanner.fetchEntries(ids: [id]).isEmpty)
    }

    @Test func batchWriteChangesSeveralPhotosAtOnce() async throws {
        let a = try await PhotoFixtures.makePhoto()
        let b = try await PhotoFixtures.makePhoto()
        try await LibraryScanner.write([a: "一 #甲#", b: "二 #甲#"])
        #expect(PhotoFixtures.metadata(a)?.caption == "一 #甲#")
        #expect(PhotoFixtures.metadata(b)?.caption == "二 #甲#")
        #expect(Set(LibraryScanner.fetchEntries(ids: [a, b]).map(\.id)) == [a, b])
    }

    @Test func externalKeywordChangeIsReconciled() async throws {
        let id = try await PhotoFixtures.makePhoto()
        try await LibraryScanner.write(caption: "#猫#", to: id)
        // 在照片 App 里手动加了一个关键词。
        // 照片库在自己的队列上执行这个闭包：要标 @Sendable，否则继承测试的主线程隔离，运行时检查会直接终止进程。
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject!
            PHAssetChangeRequest(for: asset).addKeyword("狗")
        }
        try await LibraryScanner.reconcileKeywords(ids: [id])
        #expect(PhotoFixtures.metadata(id)?.keywords == ["猫"])
    }

    @Test func videoIsReadAsVideoEntry() async throws {
        let id = try await PhotoFixtures.makeVideo()
        try await LibraryScanner.write(caption: "一段视频", to: id)
        let entry = try #require(LibraryScanner.fetchEntries(ids: [id]).first)
        #expect(entry.mediaKind == .video)
    }

    // MARK: 同步

    @Test func fullScanAndIncrementalSeeWrites() async throws {
        let id = try await PhotoFixtures.makePhoto()
        try await LibraryScanner.write(caption: "全量能读到", to: id)

        var token: Data?
        var found = false
        for await event in LibraryScanner.fullScan(batchSize: 50) {
            switch event {
            case .batch(_, let entries): found = found || entries.contains { $0.id == id }
            case .finished(let t): token = t
            case .started: break
            }
        }
        #expect(found)
        let since = try #require(token)

        try await LibraryScanner.write(caption: "增量能读到", to: id)
        let other = try await PhotoFixtures.makePhoto()
        try await LibraryScanner.write(caption: "新照片", to: other)
        let result = try await LibraryScanner.incremental(since: since)
        #expect(result.updated.first { $0.id == id }?.caption == "增量能读到")
        #expect(result.updated.contains { $0.id == other })

        // 说明被清空的照片算移除。
        try await LibraryScanner.write(caption: nil, to: other)
        let again = try await LibraryScanner.incremental(since: try #require(result.token))
        #expect(again.removed.contains(other))
    }

    @Test func expiredTokenIsReported() async {
        await #expect(throws: LibraryScanner.ScanError.self) {
            _ = try await LibraryScanner.incremental(since: Data("不是 token".utf8))
        }
    }

    // MARK: DiaryStore + 真实照片库：App 里的每一种写法

    @Test func storeWritesNewAppendEditRenameThroughPhotoKit() async throws {
        // 标签名每次不同：照片库里还有界面测试用的日记，改名不能碰到它们。
        let run = String(UUID().uuidString.prefix(4))
        let (walk, stroll, merged) = ("散步\(run)", "走路\(run)", "步行\(run)")
        let id = try await PhotoFixtures.makePhoto(date: date(2026, 10, 25))
        let other = try await PhotoFixtures.makePhoto(date: date(2026, 10, 26))
        let store = DiaryStore(.init(library: PhotoKitLibrary(), indexDirectory: temporaryDirectory(),
                                     placeNamer: FakePlaceNamer(), defaults: isolatedDefaults(),
                                     now: { fixedNow }, saveDelay: .zero, changeDelay: .zero,
                                     geocodeInterval: .zero, placeLanguage: { "zh-Hans" }))
        await store.start()
        #expect(await eventually(timeout: .seconds(20)) { store.hasSynced && store.syncState == .idle })

        // 写日记
        try await store.save(text: "第一次写 #\(walk)#", mode: .new, for: id)
        #expect(store.entry(id)?.title == "第一次写")
        #expect(PhotoFixtures.metadata(id)?.caption == "第一次写 #\(walk)#\n— 2026.10.31")
        #expect(PhotoFixtures.metadata(id)?.keywords == [walk])

        // 追加感想
        try await store.save(text: "过了几天再看", mode: .append, for: id)
        #expect(store.entry(id)?.segments.count == 2)
        #expect(PhotoFixtures.metadata(id)?.caption?.hasSuffix("过了几天再看\n— 2026.10.31") == true)

        // 编辑
        try await store.save(text: "改过的 #\(walk)#\n— 2026.10.25", mode: .edit, for: id)
        #expect(PhotoFixtures.metadata(id)?.caption == "改过的 #\(walk)#\n— 2026.10.25")

        // 标签改名、合并
        try await store.save(text: "另一张 #\(stroll)#", mode: .new, for: other)
        try await store.renameTags([walk, stroll], to: merged)
        #expect(PhotoFixtures.metadata(id)?.keywords == [merged])
        #expect(PhotoFixtures.metadata(other)?.keywords == [merged])
        #expect(store.entries(tagged: merged).count == 2)
        #expect(store.entries(tagged: walk).isEmpty)

        // 编辑成空：清除说明，日记消失。
        try await store.save(text: "", mode: .edit, for: other)
        #expect(store.entry(other) == nil)
        #expect(PhotoFixtures.metadata(other)?.caption?.isEmpty ?? true)

        // 别的 App 改了说明：通过照片库通知和增量同步进来。
        try await LibraryScanner.write(caption: "在照片 App 里改的", to: id)
        #expect(await eventually(timeout: .seconds(10)) { store.entry(id)?.caption == "在照片 App 里改的" })
    }

    @Test func placeIsReadFromPhotoLocation() async throws {
        let tokyo = CLLocation(latitude: 35.68, longitude: 139.76)
        let id = try await PhotoFixtures.makePhoto(location: tokyo)
        try await LibraryScanner.write(caption: "有地点", to: id)
        let entry = try #require(LibraryScanner.fetchEntries(ids: [id]).first)
        #expect(abs((entry.latitude ?? 0) - 35.68) < 0.01)
        #expect(abs((entry.longitude ?? 0) - 139.76) < 0.01)
    }

    // MARK: 取图（回调线程各不相同）

    @Test func imagesArriveForPhoto() async throws {
        let id = try await PhotoFixtures.makePhoto()
        AssetImages.shared.warm(ids: [id])
        var last: UIImage?
        for await image in AssetImages.shared.images(for: id, pixelSize: CGSize(width: 40, height: 40)) { last = image }
        #expect(last != nil)
        // 第二次命中解码缓存。
        #expect(AssetImages.shared.cached(id, pixelSize: CGSize(width: 40, height: 40)) != nil)
    }

    /// 视频的回调在任意一条后台队列上。
    @Test func playerItemArrivesForVideo() async throws {
        let id = try await PhotoFixtures.makeVideo()
        let item = await AssetImages.shared.playerItem(for: id)
        #expect(item != nil)
    }

    /// 不是实况照片时也要回来（nil），不能一直等。
    @Test(.timeLimit(.minutes(1))) func livePhotoRequestFinishesForStillPhoto() async throws {
        let id = try await PhotoFixtures.makePhoto()
        _ = await AssetImages.shared.livePhoto(for: id, pixelSize: CGSize(width: 40, height: 40))
    }

    @Test func recentAssetsListsNewPhotosFirst() async throws {
        let id = try await PhotoFixtures.makePhoto(date: .now.addingTimeInterval(3600))
        #expect(AssetImages.recentAssets(limit: 5).first?.id == id)
    }

    // MARK: 晚间提醒

    /// 系统在自己的队列上调通知代理（走 Objective-C 的 completionHandler 版本）：不能因为隔离不对而终止，点开的内容要交到主线程。
    @Test func reminderDelegateIsCalledOffMainThread() async throws {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Reminder.category
        content.userInfo = [Reminder.assetKey: "照片-123"]
        let request = UNNotificationRequest(identifier: Reminder.identifierPrefix + "0", content: content, trigger: nil)
        let notification = try SystemNotifications.notification(request, date: .now)
        let reply = try SystemNotifications.textResponse(notification, action: Reminder.replyAction, text: "海边的风")
        ReminderScheduler.shared.pending = nil
        defer { ReminderScheduler.shared.pending = nil }

        nonisolated(unsafe) let delegate: any UNUserNotificationCenterDelegate = ReminderNotificationDelegate()
        nonisolated(unsafe) let center = UNUserNotificationCenter.current()
        nonisolated(unsafe) let (n, r) = (notification, reply)

        let options = await withCheckedContinuation { (done: CheckedContinuation<UNNotificationPresentationOptions, Never>) in
            DispatchQueue.global().async {
                delegate.userNotificationCenter?(center, willPresent: n) { done.resume(returning: $0) }
            }
        }
        #expect(options.contains(.banner))

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                delegate.userNotificationCenter?(center, didReceive: r) { done.resume() }
            }
        }
        #expect(ReminderScheduler.shared.pending == Reminder.Response(assetID: "照片-123", day: DayStamp(.now), reply: "海边的风"))
    }

    /// 通用提醒（没带照片）点开时现挑当天的照片；带的照片已经删了就不开编辑器。
    @Test func reminderOpensEditorForTodaysPhoto() async throws {
        let id = try await PhotoFixtures.makePhoto(date: .now)
        let today = DayStamp(.now)
        #expect(Reminder.photos(on: today).contains { $0.id == id })

        let store = makeStore(library: FakeLibrary())
        let picked = await ReminderScheduler.shared.editorRequest(
            for: Reminder.Response(assetID: nil, day: today, reply: "  晚饭很好吃 "), store: store)
        #expect(picked?.seed == "晚饭很好吃")
        #expect(picked?.mode == .new)

        let given = await ReminderScheduler.shared.editorRequest(
            for: Reminder.Response(assetID: id, day: today, reply: nil), store: store)
        #expect(given?.assetID == id)
        #expect(given?.seed == nil)

        let gone = await ReminderScheduler.shared.editorRequest(
            for: Reminder.Response(assetID: "不存在的照片/L0/001", day: today, reply: "x"), store: store)
        #expect(gone == nil)
    }
}

/// UNNotification、UNNotificationResponse 没有公开的初始化方法：用系统自己的工厂方法造一个，模拟系统调代理。
enum SystemNotifications {
    struct Missing: Error {}

    static func notification(_ request: UNNotificationRequest, date: Date) throws -> UNNotification {
        typealias Make = @convention(c) (AnyClass, Selector, UNNotificationRequest, NSDate) -> UNNotification
        let (imp, sel) = try factory(UNNotification.self, "notificationWithRequest:date:")
        return unsafeBitCast(imp, to: Make.self)(UNNotification.self, sel, request, date as NSDate)
    }

    static func textResponse(_ notification: UNNotification, action: String, text: String) throws -> UNTextInputNotificationResponse {
        typealias Make = @convention(c) (AnyClass, Selector, UNNotification, NSString, NSString) -> UNTextInputNotificationResponse
        let (imp, sel) = try factory(UNTextInputNotificationResponse.self, "responseWithNotification:actionIdentifier:userText:")
        return unsafeBitCast(imp, to: Make.self)(UNTextInputNotificationResponse.self, sel, notification, action as NSString, text as NSString)
    }

    private static func factory(_ cls: AnyClass, _ name: String) throws -> (IMP, Selector) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getClassMethod(cls, sel) else { throw Missing() }
        return (method_getImplementation(method), sel)
    }
}

/// 主线程上计数（回调里递增，测试里读）。
@MainActor final class Counter {
    var value = 0
}
