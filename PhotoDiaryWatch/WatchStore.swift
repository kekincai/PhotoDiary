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
    private(set) var isReachable = false
    /// 已经写进照片说明的段落（iPhone 的回执），用来在界面上打个勾。
    private(set) var confirmed: Set<UUID> = []
    /// iPhone 写不进去的段落（照片删了、改不了说明）：字留在表上，用户看过再删。
    private(set) var failed: [WatchWrite] = [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(failed), forKey: Self.failedKey) }
    }
    /// 发出去、还没收到回执的段落；收到“没写进去”时从这里找回原文。
    private var sent: [WatchWrite] = [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(sent), forKey: Self.sentKey) }
    }
    private static let failedKey = "failedWrites"
    private static let sentKey = "sentWrites"

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
        let defaults = UserDefaults.standard
        failed = defaults.data(forKey: Self.failedKey).flatMap { try? JSONDecoder().decode([WatchWrite].self, from: $0) } ?? []
        sent = defaults.data(forKey: Self.sentKey).flatMap { try? JSONDecoder().decode([WatchWrite].self, from: $0) } ?? []
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
        // 快照前面是最近的日记（已经按照片日期倒序），后面补的是那年今日。
        entries = Array(all.prefix(WatchSnapshot.maxEntries))
        // 本地缓存里已有的图直接用，缺的去要。
        var loaded: [String: UIImage] = [:]
        for id in snapshot.imageIDs {
            if let image = images[id] ?? Self.cachedImage(id) { loaded[id] = image }
        }
        images = loaded
        pruneCache(keeping: Set(snapshot.imageIDs))
        Self.log.info("快照：\(snapshot.entries.count) 篇，那年今日 \(snapshot.onThisDay.count) 篇，缺图 \(self.missingImageIDs.count) 张")
        // 正在取图时到的快照，缺的图等这一轮取完再补（见 fetchMissingImages）。
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
        guard !missingImageIDs.isEmpty else { return }
        fetching = true
        Task {
            defer { fetching = false }
            // 取的时候到了新快照，又缺了别的图：接着取，直到这一轮没有新的可要。
            var asked = Set<String>()
            while let id = missingImageIDs.first(where: { !asked.contains($0) }), WCSession.default.isReachable {
                asked.insert(id)
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
    var hasSnapshot: Bool { snapshot != nil }

    /// 表上今天的那年今日。过了零点、iPhone 还没发新快照时用快照里往后几天的。
    func onThisDay(today: DayStamp = .today) -> [DiaryEntry] {
        (snapshot?.onThisDay(on: today) ?? []).compactMap { byID[$0] }
    }

    /// 表上今天所在的一周；进了新的一周就从头算。
    func week(today: DayStamp = .today) -> (days: [WatchWeekDay], written: Int) {
        snapshot?.week(on: today) ?? ([], 0)
    }

    /// 看过了，删掉这段没写进去的。
    func dismissFailed(_ id: UUID) {
        failed.removeAll { $0.id == id }
    }

    // MARK: 写

    /// 口述的一段发给 iPhone：可达时直接送到；不可达时排队，连上后自动送达。
    func send(_ write: WatchWrite) {
        // 只留最近的一些：回执丢了的不能越攒越多。
        sent = Array((sent + [write]).suffix(50))
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

    /// iPhone 的回执：写进去了打勾；写不进去的把原文留在表上。
    private func receive(_ message: WatchMessage) {
        switch message {
        case .wrote(let id):
            sent.removeAll { $0.id == id }
            confirmed.insert(id)
        case .failed(let id):
            guard let write = sent.first(where: { $0.id == id }) else { return }
            sent.removeAll { $0.id == id }
            if !failed.contains(where: { $0.id == id }) { failed.append(write) }
            Self.log.error("一段没写进照片说明")
        default:
            break
        }
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
        guard let message = WatchMessage(data: messageData) else { return }
        Task { @MainActor in self.receive(message) }
    }

    /// 表不在旁边时 iPhone 把回执排进 userInfo 队列，连上后到这里。
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = WatchMessage(userInfo: userInfo) else { return }
        Task { @MainActor in self.receive(message) }
    }
}
