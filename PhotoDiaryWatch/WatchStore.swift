import Foundation
import Observation
import WatchConnectivity
import UIKit
import OSLog
import Synchronization

/// 表上的数据源：iPhone 放在 applicationContext 里的快照（存在本地，下次打开直接显示）、
/// 按需向 iPhone 要来的缩略图（存在本地缓存），以及发回 iPhone 的口述段落。
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()
    nonisolated private static let log = Logger(subsystem: "com.kejincai.photodiary.watch", category: "store")

    private(set) var snapshot: WatchSnapshot?
    /// 快照里的日记，按照片日期倒序（和 iPhone 的列表一致）。
    private(set) var entries: [DiaryEntry] = []
    private(set) var onThisDay: [DiaryEntry] = []
    private(set) var isReachable = false
    /// 已发给 iPhone、还没收到“已写入”回执的段落。
    private(set) var pending: [WatchWrite] = []
    /// 最近一次成功写入的段落，用来在界面上打个勾。
    private(set) var lastConfirmed: UUID?
    /// 正在向 iPhone 要缩略图。
    private(set) var isLoadingImages = false

    private var images: [String: UIImage] = [:]
    private var byID: [String: DiaryEntry] = [:]
    private var fetching = false

    private static var snapshotURL: URL {
        URL.applicationSupportDirectory.appending(path: WatchSnapshot.fileName)
    }
    private static var imagesDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    // MARK: 启动

    func start() {
        load()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 读本地存着的快照和缩略图；第一次打开还没有就等 iPhone 发。
    private func load() {
        if let data = try? Data(contentsOf: Self.snapshotURL),
           let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            apply(snapshot)
        }
    }

    private func apply(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        // 星期行的顺序跟 iPhone 的设置走，和快照里的一周对齐。
        Calendar.diaryFirstWeekday = snapshot.firstWeekday ?? WeekStart.default.rawValue
        let all = snapshot.entries.map(\.entry)
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let recentIDs = Set(snapshot.entries.prefix(WatchSnapshot.maxEntries).map(\.id))
        entries = all.filter { recentIDs.contains($0.id) }.sorted { $0.sortDate > $1.sortDate }
        onThisDay = snapshot.onThisDay.compactMap { byID[$0] }
        // 本地缓存里已有的图直接用，缺的去要。
        var loaded: [String: UIImage] = [:]
        for id in snapshot.imageIDs {
            if let image = images[id] ?? Self.cachedImage(id) { loaded[id] = image }
        }
        images = loaded
        pruneCache(keeping: Set(snapshot.imageIDs))
        Self.log.info("快照：\(snapshot.entries.count) 篇，那年今日 \(snapshot.onThisDay.count) 篇，缺图 \(self.missingImageIDs.count) 张")
        fetchMissingImages()
    }

    private func receive(snapshotData data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
              snapshot.version == WatchSnapshot.version else {
            Self.log.error("快照无法解析或版本不对")
            return
        }
        do {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.snapshotURL, options: .atomic)
        } catch {
            Self.log.error("保存快照失败：\(error, privacy: .public)")
        }
        apply(snapshot)
    }

    // MARK: 缩略图

    private var missingImageIDs: [String] {
        (snapshot?.imageIDs ?? []).filter { images[$0] == nil }
    }

    /// 逐张向 iPhone 要缺的图（一条消息最多约 64 KB）。
    private func fetchMissingImages() {
        guard !fetching, WCSession.default.isReachable else { return }
        let missing = missingImageIDs
        guard !missing.isEmpty else { return }
        fetching = true
        isLoadingImages = true
        Task {
            defer { fetching = false; isLoadingImages = false }
            for id in missing {
                // 一次一张：JSON 里的 Base64 会把 20 KB 的图撑到 27 KB，两张就可能超过一条消息的上限。
                guard let reply = await send(.thumbnails(ids: [id])), case .images(let received) = reply else { continue }
                for (id, data) in received {
                    guard let image = UIImage(data: data) else { continue }
                    images[id] = image
                    Self.cache(data, for: id)
                }
            }
            Self.log.info("缩略图：还缺 \(self.missingImageIDs.count) 张")
        }
    }

    private static func cacheURL(_ id: String) -> URL {
        imagesDirectory.appending(path: id.replacingOccurrences(of: "/", with: "_") + ".jpg")
    }

    private static func cachedImage(_ id: String) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheURL(id)) else { return nil }
        return UIImage(data: data)
    }

    private static func cache(_ data: Data, for id: String) {
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL(id), options: .atomic)
    }

    private func pruneCache(keeping ids: Set<String>) {
        let keep = Set(ids.map { Self.cacheURL($0).lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.imagesDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: 读

    func entry(_ id: String) -> DiaryEntry? { byID[id] }
    func image(_ id: String) -> UIImage? { images[id] }
    var unwritten: [WatchPhoto] { snapshot?.unwritten ?? [] }
    var week: [WatchWeekDay] { snapshot?.week ?? [] }
    var writtenThisWeek: Int { snapshot?.writtenThisWeek ?? 0 }
    var hasSnapshot: Bool { snapshot != nil }

    // MARK: 写

    /// 口述的一段发给 iPhone：可达时直接送到；不可达时排队，连上后自动送达。
    func send(_ write: WatchWrite) {
        pending.append(write)
        Self.log.info("发出一段（\(write.mode.rawValue, privacy: .public)）")
        if WCSession.default.isReachable {
            Task {
                if await send(.write(write)) == nil {
                    WCSession.default.transferUserInfo(WatchMessage.write(write).userInfo)
                }
            }
        } else {
            WCSession.default.transferUserInfo(WatchMessage.write(write).userInfo)
        }
    }

    func requestRefresh() {
        guard WCSession.default.isReachable else { return }
        Task { _ = await send(.refresh) }
    }

    /// 发一条要回复的消息；iPhone 没回或出错时返回 nil。
    /// 两个回调都在 WCSession 的队列上执行，不能继承主线程隔离；只允许恢复一次。
    private func send(_ message: WatchMessage) async -> WatchMessage? {
        await withCheckedContinuation { continuation in
            let resumed = Mutex(false)
            WCSession.default.sendMessageData(message.data) { @Sendable data in
                guard resumed.withLock({ let was = $0; $0 = true; return !was }) else { return }
                continuation.resume(returning: WatchMessage(data: data))
            } errorHandler: { @Sendable error in
                Self.log.error("消息失败：\(error, privacy: .public)")
                guard resumed.withLock({ let was = $0; $0 = true; return !was }) else { return }
                continuation.resume(returning: nil)
            }
        }
    }

    private func confirm(_ id: UUID) {
        pending.removeAll { $0.id == id }
        lastConfirmed = id
    }

    private func update(reachable: Bool) {
        isReachable = reachable
        if reachable {
            fetchMissingImages()
            if snapshot == nil { requestRefresh() }
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        if let error { Self.log.error("WCSession 激活失败：\(error, privacy: .public)") }
        let reachable = session.isReachable
        // 没在运行时 iPhone 放进来的快照。
        let context = session.receivedApplicationContext[WatchMessage.snapshotKey] as? Data
        Task { @MainActor in
            if let context { self.receive(snapshotData: context) }
            self.update(reachable: reachable)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.update(reachable: reachable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchMessage.snapshotKey] as? Data else { return }
        Task { @MainActor in self.receive(snapshotData: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let message = WatchMessage(data: messageData), case .wrote(let id) = message else { return }
        Task { @MainActor in self.confirm(id) }
    }
}
