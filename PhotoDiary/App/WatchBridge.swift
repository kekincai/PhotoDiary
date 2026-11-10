import Foundation
import WatchConnectivity
import UIKit
import OSLog

/// iPhone 这边和 Apple Watch 的连接。
///
/// - 日记一变就（防抖后）把快照放进 applicationContext：最近的日记、那年今日、本周写作、还没写的照片。
/// - 表按需来要缩略图，这里现做现回（sendMessageData 的回复）。
/// - 表上口述的感想发回来，这里写进照片说明；暂时写不进去（没权限、系统拒绝）就留在队列里，下次回到前台再试；
///   永远写不进去的（照片删了、改不了说明）移出队列，告诉表“没写进去”，字留在表上。
/// - 所有 WCSession 回调都在后台队列，先把数据变成 Sendable 的值再回到主线程。
@Observable
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    enum Status: Equatable {
        case unsupported, notPaired, appNotInstalled, ready
    }

    private(set) var status: Status = .unsupported
    private(set) var lastSent: Date?
    private(set) var isSending = false
    /// 从表上收到、还没写进照片说明的。
    private(set) var pendingWrites: [WatchWrite] = [] {
        didSet { Self.persist(pendingWrites) }
    }

    private weak var store: DiaryStore?
    private var syncTask: Task<Void, Never>?
    private var draining = false
    /// 上次发出去的内容（不含生成时间），内容没变就不重发。
    private var lastPayload: WatchSnapshot?

    /// 已经写进照片说明的段落。表那边消息的回复丢了会改走 userInfo 队列再发一遍，同一段不能写两次。
    private var written: [UUID] = [] {
        didSet { UserDefaults.standard.set(written.map(\.uuidString), forKey: Self.writtenKey) }
    }

    private static let queueKey = "watchWriteQueue"
    private static let writtenKey = "watchWritten"

    override private init() {
        super.init()
        pendingWrites = Self.restore()
        written = (UserDefaults.standard.stringArray(forKey: Self.writtenKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    // MARK: 启动

    func start(store: DiaryStore) {
        attach(store: store)
        guard WCSession.isSupported() else { status = .unsupported; return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 只连上日记库、不激活 WCSession（测试直接调 handle）。
    func attach(store: DiaryStore) {
        self.store = store
    }

    /// 测试之间清空队列和状态。
    func resetForTesting() {
        pendingWrites = []
        written = []
        draining = false
        lastPayload = nil
        store = nil
    }

    /// 回到前台：补写队列里的，再同步一次。
    func resume() {
        drainQueue()
        scheduleSync()
    }

    // MARK: iPhone → Watch

    /// 日记变化后等一会儿再发，连续写入只发最后一次。
    func scheduleSync(after delay: Duration = .seconds(2)) {
        guard status == .ready else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    func syncNow() async {
        syncTask?.cancel()
        lastPayload = nil
        await sync()
    }

    private func sync() async {
        guard status == .ready, let store, !isSending else { return }
        // 索引还没读出来时不发：发出去的是空快照，表会删光缩略图再一张张重要。
        guard store.hasLoaded || !store.canRead else { return }
        isSending = true
        defer { isSending = false }
        // 没有照片权限时发一份空快照（表上不留旧的日记），也不碰照片库：取照片会触发系统的授权弹窗。
        var snapshot = store.canRead ? await buildSnapshot(store: store) : WatchSnapshot(generated: .now, today: .today)
        if let last = lastPayload {
            snapshot.generated = last.generated
            if snapshot == last { return }
        }
        snapshot.generated = .now
        do {
            // 去重按裁剪前的内容比：裁剪过的和下次新算的永远不一样，会每次都重发。
            var sending = snapshot
            let data = try Self.encodeWithinLimit(&sending)
            try WCSession.default.updateApplicationContext([WatchMessage.snapshotKey: data])
            lastPayload = snapshot
            lastSent = snapshot.generated
            Log.watch.info("发送快照：\(sending.entries.count) 篇，\(data.count / 1024) KB")
        } catch {
            Log.watch.error("发送快照失败：\(error, privacy: .public)")
        }
    }

    /// applicationContext 有大小上限（约 64 KB 以内最稳）：超了就从旧的日记开始少带几篇，那年今日最多带 maxOnThisDay 篇。
    static func encodeWithinLimit(_ snapshot: inout WatchSnapshot, limit: Int = WatchSnapshot.maxBytes) throws -> Data {
        var data = try JSONEncoder().encode(snapshot)
        while data.count > limit, !snapshot.entries.isEmpty {
            let keep = Set(snapshot.onThisDay)
            // 先丢不是今天那年今日的最旧一篇（往后几天的也算）；都是今天的那年今日时丢最后一篇。
            let index = snapshot.entries.lastIndex(where: { !keep.contains($0.id) }) ?? snapshot.entries.count - 1
            let removed = snapshot.entries.remove(at: index).id
            snapshot.onThisDay.removeAll { $0 == removed }
            for i in snapshot.ahead.indices { snapshot.ahead[i].ids.removeAll { $0 == removed } }
            snapshot.ahead.removeAll { $0.ids.isEmpty }
            data = try JSONEncoder().encode(snapshot)
        }
        return data
    }

    private func buildSnapshot(store: DiaryStore) async -> WatchSnapshot {
        let today = DayStamp.today
        let recent = Array(store.diaries.prefix(WatchSnapshot.maxEntries))
        let memories = Array(store.onThisDay.prefix(WatchSnapshot.maxOnThisDay))
        // 往后几天的那年今日：表上过了零点、iPhone 没来得及发新快照时用。
        let ahead: [(day: DayStamp, entries: [DiaryEntry])] = (1...WatchSnapshot.daysAhead).compactMap { offset in
            let day = DayStamp(Calendar.diary.date(byAdding: .day, value: offset, to: today.date) ?? today.date)
            let picked = store.diaries.filter { $0.day.month == day.month && $0.day.day == day.day && $0.day.year < day.year }
                .prefix(WatchSnapshot.maxOnThisDay)
            return picked.isEmpty ? nil : (day, Array(picked))
        }
        // 那年今日不在最近 40 篇里的也带上。
        var known = Set(recent.map(\.id))
        var picked = recent
        for entry in memories + ahead.flatMap(\.entries) where known.insert(entry.id).inserted {
            picked.append(entry)
        }
        let entries = picked.map {
            WatchEntry(id: $0.id, caption: $0.caption, day: $0.day, placeName: $0.placeName, mediaKind: $0.mediaKind)
        }
        // 改不了说明的照片（共享相簿里别人的）不列：在表上口述了也写不进去。
        let unwritten = await Task.detached { AssetImages.recentAssets(limit: 40, editableOnly: true) }.value
            .filter { store.entry($0.id) == nil }
            .prefix(WatchSnapshot.maxUnwritten)
            .map { WatchPhoto(id: $0.id, day: $0.date.map { DayStamp($0) }) }

        return WatchSnapshot(
            generated: .now,
            today: today,
            entries: entries,
            onThisDay: memories.map(\.id),
            ahead: ahead.map { WatchMemories(day: $0.day, ids: $0.entries.map(\.id)) },
            week: store.weekWriting.map { WatchWeekDay(day: $0.day, wrote: $0.wrote) },
            writtenThisWeek: store.writtenThisWeek,
            unwritten: Array(unwritten),
            firstWeekday: Calendar.diaryFirstWeekday)
    }

    /// 表要的缩略图：正方形裁切、缩到 256 像素的 JPEG，一张 15 KB 左右。只用本地已有的图，不为表去下载。
    private func thumbnails(for ids: [String]) async -> [String: Data] {
        var out: [String: Data] = [:]
        for id in ids {
            if let data = await thumbnail(id) { out[id] = data }
        }
        return out
    }

    private func thumbnail(_ id: String) async -> Data? {
        let side = WatchSnapshot.thumbnailPixels
        var last: UIImage?
        for await image in AssetImages.shared.images(for: id, pixelSize: CGSize(width: side, height: side)) {
            last = image
        }
        guard let image = last else { return nil }
        // PhotoKit 给的图往往比要的大，先缩一遍再编码。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: side, height: side)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2)
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.55) { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
    }

    // MARK: Watch → iPhone

    private func enqueue(_ write: WatchWrite) {
        if written.contains(write.id) {
            // 已经写过：只再确认一次，让表把它移出待发列表。
            tellWatch(.wrote(write.id))
            return
        }
        guard !pendingWrites.contains(where: { $0.id == write.id }) else { return }
        pendingWrites.append(write)
        Log.watch.info("收到表上的一段（\(write.mode.rawValue, privacy: .public)）")
        drainQueue()
    }

    /// 按顺序写队列里的段落。写的时候新到的也接着写（每次从队列里重新取）；
    /// 一段暂时写不进去就跳过、留着下次再试，不挡住后面的；永远写不进去的移出队列并告诉表。
    private func drainQueue() {
        guard let store, !draining, !pendingWrites.isEmpty, store.canRead else { return }
        draining = true
        Task {
            defer { draining = false }
            var retryLater = Set<UUID>()
            while let write = pendingWrites.first(where: { !retryLater.contains($0.id) }) {
                do {
                    try await store.save(text: write.text, mode: write.mode == .new ? .new : .append, for: write.assetID)
                    pendingWrites.removeAll { $0.id == write.id }
                    written = Array((written + [write.id]).suffix(200))
                    tellWatch(.wrote(write.id))
                } catch let error as LibraryScanner.WriteError {
                    Log.watch.error("表上的一段写不进去，退回表上：\(error, privacy: .public)")
                    pendingWrites.removeAll { $0.id == write.id }
                    tellWatch(.failed(write.id))
                } catch {
                    Log.watch.error("表上的一段暂时写不进去，留在队列里：\(error, privacy: .public)")
                    retryLater.insert(write.id)
                }
            }
            scheduleSync(after: .seconds(1))
        }
    }

    /// 回执：表在旁边就直接送到，不在就排进 userInfo 队列，表下次连上时收到（不然表上那段一直停在“已发到 iPhone”）。
    private func tellWatch(_ message: WatchMessage) {
        guard status == .ready else { return }
        let session = WCSession.default
        if session.isReachable {
            // 失败回调在 WCSession 的后台队列上：必须是 @Sendable，不能带主线程隔离（否则运行时直接终止）。
            session.sendMessageData(message.data, replyHandler: nil) { @Sendable _ in
                WCSession.default.transferUserInfo(message.userInfo)
            }
        } else {
            session.transferUserInfo(message.userInfo)
        }
    }

    private static func persist(_ writes: [WatchWrite]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(writes), forKey: queueKey)
    }

    private static func restore() -> [WatchWrite] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([WatchWrite].self, from: data)) ?? []
    }

    // MARK: 状态

    private func updateStatus(paired: Bool, installed: Bool) {
        let new: Status = !paired ? .notPaired : !installed ? .appNotInstalled : .ready
        guard new != status else { return }
        status = new
        Log.watch.notice("Watch 状态：\(String(describing: new), privacy: .public)")
        if new == .ready { scheduleSync(after: .seconds(1)) }
    }

    /// 表发来的消息；要回复的在这里现算。
    func handle(_ message: WatchMessage) async -> WatchMessage {
        switch message {
        case .refresh:
            await syncNow()
            return .ok
        case .thumbnails(let ids):
            let images = await thumbnails(for: ids)
            Log.watch.info("表要缩略图 \(ids.count) 张，回复 \(images.count) 张，\(images.values.reduce(0) { $0 + $1.count } / 1024) KB")
            return .images(images)
        case .write(let write):
            enqueue(write)
            return .ok
        case .images, .wrote, .failed, .ok:
            return .ok
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        if let error { Log.watch.error("WCSession 激活失败：\(error, privacy: .public)") }
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in self.updateStatus(paired: paired, installed: installed) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in self.updateStatus(paired: paired, installed: installed) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 换了一块表：重新激活。
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = WatchMessage(userInfo: userInfo) else { return }
        Task { @MainActor in _ = await self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let message = WatchMessage(data: messageData) else { return }
        Task { @MainActor in _ = await self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let message = WatchMessage(data: messageData) else { replyHandler(WatchMessage.ok.data); return }
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let answer = await self.handle(message)
            reply(answer.data)
        }
    }
}
