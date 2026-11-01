import Foundation
import WatchConnectivity
import UIKit
import OSLog

/// iPhone 这边和 Apple Watch 的连接。
///
/// - 日记一变就（防抖后）把快照放进 applicationContext：最近的日记、那年今日、本周写作、还没写的照片。
/// - 表按需来要缩略图，这里现做现回（sendMessageData 的回复）。
/// - 表上口述的感想发回来，这里写进照片说明；写不进去（没权限、系统拒绝）就留在队列里，下次回到前台再试。
/// - 所有 WCSession 回调都在后台队列，先把数据变成 Sendable 的值再回到主线程。
@Observable
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    enum Status: Equatable {
        case unsupported, notPaired, appNotInstalled, ready
    }

    private(set) var status: Status = .unsupported
    private(set) var lastSent: Date?
    private(set) var lastWriteReceived: Date?
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

    private static let queueKey = "watchWriteQueue"

    override private init() {
        super.init()
        pendingWrites = Self.restore()
    }

    // MARK: 启动

    func start(store: DiaryStore) {
        self.store = store
        guard WCSession.isSupported() else { status = .unsupported; return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
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
        // 没有照片权限时不碰照片库：取照片会触发系统的授权弹窗。
        guard status == .ready, let store, store.canRead, !isSending else { return }
        isSending = true
        defer { isSending = false }
        var snapshot = await buildSnapshot(store: store)
        if let last = lastPayload {
            snapshot.generated = last.generated
            if snapshot == last { return }
        }
        snapshot.generated = .now
        do {
            let data = try JSONEncoder().encode(snapshot)
            try WCSession.default.updateApplicationContext([WatchMessage.snapshotKey: data])
            lastPayload = snapshot
            lastSent = snapshot.generated
            Log.watch.info("发送快照：\(snapshot.entries.count) 篇，\(data.count / 1024) KB")
        } catch {
            Log.watch.error("发送快照失败：\(error, privacy: .public)")
        }
    }

    private func buildSnapshot(store: DiaryStore) async -> WatchSnapshot {
        let recent = Array(store.diaries.prefix(WatchSnapshot.maxEntries))
        // 那年今日不在最近 40 篇里的也带上。
        let known = Set(recent.map(\.id))
        let picked = recent + store.onThisDay.filter { !known.contains($0.id) }
        let entries = picked.map {
            WatchEntry(id: $0.id, caption: $0.caption, day: $0.day, placeName: $0.placeName, mediaKind: $0.mediaKind)
        }
        let unwritten = await Task.detached { AssetImages.recentAssets(limit: 40) }.value
            .filter { store.entry($0.id) == nil }
            .prefix(WatchSnapshot.maxUnwritten)
            .map { WatchPhoto(id: $0.id, day: $0.date.map { DayStamp($0) }) }

        return WatchSnapshot(
            generated: .now,
            today: .today,
            entries: entries,
            onThisDay: store.onThisDay.map(\.id),
            week: store.weekWriting.map { WatchWeekDay(day: $0.day, wrote: $0.wrote) },
            writtenThisWeek: store.writtenThisWeek,
            writtenThisMonth: store.writtenThisMonth,
            unwritten: Array(unwritten),
            tags: store.allTags,
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
        guard !pendingWrites.contains(where: { $0.id == write.id }) else { return }
        pendingWrites.append(write)
        lastWriteReceived = .now
        Log.watch.info("收到表上的一段（\(write.mode.rawValue, privacy: .public)）")
        drainQueue()
    }

    private func drainQueue() {
        guard let store, !draining, !pendingWrites.isEmpty, store.canRead else { return }
        draining = true
        Task {
            defer { draining = false }
            for write in pendingWrites {
                do {
                    try await store.save(text: write.text, mode: write.mode == .new ? .new : .append, for: write.assetID)
                    pendingWrites.removeAll { $0.id == write.id }
                    if WCSession.default.isReachable {
                        WCSession.default.sendMessageData(WatchMessage.wrote(write.id).data, replyHandler: nil)
                    }
                } catch {
                    Log.watch.error("表上的一段写入失败，留在队列里：\(error, privacy: .public)")
                    break
                }
            }
            scheduleSync(after: .seconds(1))
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
    private func handle(_ message: WatchMessage) async -> WatchMessage {
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
        case .images, .wrote, .ok:
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
