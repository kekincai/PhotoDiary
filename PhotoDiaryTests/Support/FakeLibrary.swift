import Foundation
import Photos
import Synchronization
@testable import PhotoDiary

/// 内存里的照片库。按真实照片库的规则产出日记条目、change token 和增量结果，并记下所有写入。
///
/// 准备数据用 `seed`（不算变化）；模拟在照片 App 里改说明用 `externalEdit`（算变化并通知观察者）。
nonisolated final class FakeLibrary: PhotoLibraryClient {
    struct Asset: Sendable {
        var caption: String?
        var keywords: [String] = []
        var date: Date?
        var latitude: Double?
        var longitude: Double?
        var kind: MediaKind = .photo
    }

    struct State {
        var assets: [String: Asset] = [:]
        var authorization: PHAuthorizationStatus = .authorized
        /// 每次变化加一；比 `oldestValidToken` 旧的 token 视为失效。
        var token = 0
        var oldestValidToken = 0
        var changes: [(token: Int, touched: Set<String>, deleted: Set<String>)] = []
        var onChange: (@MainActor @Sendable () -> Void)?
        // 调用记录
        var fullScans = 0
        var incrementals = 0
        var writes: [[String: String?]] = []
        var reconciled: [[String]] = []
        var deleted: [[String]] = []
        /// 打开后，全量读取交出第一批就停住，等 `releaseScans()`。
        var holdScans = false
        var scanWaiters: [CheckedContinuation<Void, Never>] = []
        /// 打开后，增量读取读好结果但先不交出，等 `releaseIncrementals()`（真实照片库读完到交回主线程之间也有空档）。
        var holdIncrementals = false
        var incrementalWaiters: [CheckedContinuation<Void, Never>] = []
        /// 本 App 写入后像真实照片库一样通知观察者。
        var notifyOwnWrites = false
        /// 改不了说明的照片（共享相簿里别人的照片）。
        var locked: Set<String> = []
        /// 写这些照片时失败（例如系统暂时不让改），用来测“留着下次再试”。
        var failing: Set<String> = []
        /// 每次写入前等这么久（真实照片库写入要几十到几百毫秒），用来在写入中途插入操作。
        var writeDelay: Duration = .zero
    }

    let state = Mutex(State())
    let batchSize: Int

    init(batchSize: Int = 2) {
        self.batchSize = batchSize
    }

    // MARK: 准备数据与模拟外部操作

    func seed(_ id: String, caption: String?, keywords: [String] = [], date: Date? = nil,
              latitude: Double? = nil, longitude: Double? = nil, kind: MediaKind = .photo) {
        state.withLock {
            $0.assets[id] = Asset(caption: caption, keywords: keywords, date: date,
                                  latitude: latitude, longitude: longitude, kind: kind)
        }
    }

    /// 用户在系统设置里改了照片权限。
    func setAuthorization(_ status: PHAuthorizationStatus) {
        state.withLock { $0.authorization = status }
    }

    /// 在别的 App 里改了说明（nil 表示删除照片），并像 PHPhotoLibraryChangeObserver 一样通知。
    /// `notify: false` 模拟本 App 没在运行时发生的修改。
    @MainActor
    func externalEdit(_ id: String, caption: String?, notify: Bool = true) {
        if let caption {
            externalUpdate(id, notify: notify) { $0.caption = caption }
            return
        }
        let handler = state.withLock { s in
            s.assets.removeValue(forKey: id)
            s.recordChange(deleted: [id])
            return notify ? s.onChange : nil
        }
        handler?()
    }

    /// 在别的 App 里改了照片的任意属性（位置、关键词等）。
    @MainActor
    func externalUpdate(_ id: String, notify: Bool = true, _ change: (inout Asset) -> Void) {
        let handler = state.withLock { s in
            change(&s.assets[id, default: Asset()])
            s.recordChange(touched: [id])
            return notify ? s.onChange : nil
        }
        handler?()
    }

    /// 让之后的全量读取停在第一批之后，用来在读取中途插入操作。
    func holdScans() { state.withLock { $0.holdScans = true } }

    func releaseScans() {
        let waiters = state.withLock { s in
            s.holdScans = false
            defer { s.scanWaiters = [] }
            return s.scanWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func waitIfHeld() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let held = state.withLock { s in
                if s.holdScans { s.scanWaiters.append(c) }
                return s.holdScans
            }
            if !held { c.resume() }
        }
    }

    func holdIncrementals() { state.withLock { $0.holdIncrementals = true } }

    func releaseIncrementals() {
        let waiters = state.withLock { s in
            s.holdIncrementals = false
            defer { s.incrementalWaiters = [] }
            return s.incrementalWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    /// 有增量读取停在半路上。
    var incrementalIsHeld: Bool { state.withLock { !$0.incrementalWaiters.isEmpty } }

    func notifyOwnWrites(_ on: Bool) { state.withLock { $0.notifyOwnWrites = on } }

    func lock(_ id: String) { state.withLock { _ = $0.locked.insert(id) } }

    func failWrites(to ids: Set<String>) { state.withLock { $0.failing = ids } }

    func delayWrites(_ delay: Duration) { state.withLock { $0.writeDelay = delay } }

    /// 让手里所有的 token 失效（例如系统清理了变更历史）。
    func expireTokens() {
        state.withLock { $0.oldestValidToken = $0.token + 1 }
    }

    var fullScans: Int { state.withLock { $0.fullScans } }
    var incrementals: Int { state.withLock { $0.incrementals } }
    var writes: [[String: String?]] { state.withLock { $0.writes } }
    var reconciled: [[String]] { state.withLock { $0.reconciled } }
    var deletions: [[String]] { state.withLock { $0.deleted } }

    func caption(of id: String) -> String? { state.withLock { $0.assets[id]?.caption } }
    func keywords(of id: String) -> [String]? { state.withLock { $0.assets[id]?.keywords } }

    // MARK: PhotoLibraryClient

    func authorizationStatus() -> PHAuthorizationStatus { state.withLock { $0.authorization } }

    func requestAuthorization() async -> PHAuthorizationStatus {
        state.withLock {
            if $0.authorization == .notDetermined { $0.authorization = .authorized }
            return $0.authorization
        }
    }

    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject {
        state.withLock { $0.onChange = onChange }
        return NSObject()
    }

    func fullScan() -> AsyncStream<LibraryScanner.ScanEvent> {
        let (entries, token) = state.withLock { s in
            s.fullScans += 1
            let sorted = s.assets.sorted { ($0.value.date ?? .distantPast) > ($1.value.date ?? .distantPast) }
            return (sorted.compactMap { Self.entry(id: $0.key, $0.value) }, s.token)
        }
        let total = state.withLock { $0.assets.count }
        let batchSize = batchSize
        // 和 LibraryScanner.fullScan 一样：在后台任务里分批交出，消费方取消时停止，被取消就不给 token。
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(.started(total: total))
                var processed = 0
                for (i, start) in stride(from: 0, to: max(entries.count, 1), by: batchSize).enumerated() {
                    if Task.isCancelled { break }
                    let batch = Array(entries[start..<min(start + batchSize, entries.count)])
                    processed = min(processed + batchSize, total)
                    continuation.yield(.batch(processed: processed, entries: batch))
                    if i == 0 { await self.waitIfHeld() }
                }
                continuation.yield(.finished(token: Task.isCancelled ? nil : Self.archive(token)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func incremental(since tokenData: Data) async throws -> LibraryScanner.IncrementalResult {
        let result = try readIncremental(since: tokenData)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let held = state.withLock { s in
                if s.holdIncrementals { s.incrementalWaiters.append(c) }
                return s.holdIncrementals
            }
            if !held { c.resume() }
        }
        return result
    }

    private func readIncremental(since tokenData: Data) throws -> LibraryScanner.IncrementalResult {
        try state.withLock { s in
            s.incrementals += 1
            guard let since = Self.unarchive(tokenData), since >= s.oldestValidToken else {
                throw LibraryScanner.ScanError.tokenExpired
            }
            var touched = Set<String>(), deleted = Set<String>()
            for change in s.changes where change.token > since {
                touched.formUnion(change.touched)
                deleted.formUnion(change.deleted)
            }
            touched.subtract(deleted)
            let updated = touched.compactMap { id in s.assets[id].flatMap { Self.entry(id: id, $0) } }
            let removed = deleted.union(touched.subtracting(updated.map(\.id)))
            return LibraryScanner.IncrementalResult(updated: updated, removed: removed, token: Self.archive(s.token))
        }
    }

    func fetchEntries(ids: [String]) -> [DiaryEntry] {
        state.withLock { s in ids.compactMap { id in s.assets[id].flatMap { Self.entry(id: id, $0) } } }
    }

    func currentCaption(for id: String) async -> String? { caption(of: id) }

    /// 和 LibraryScanner.write 一样：有照片不在、或改不了说明，就一张都不写。
    func write(_ captions: [String: String?]) async throws {
        let delay = state.withLock { $0.writeDelay }
        if delay > .zero { try? await Task.sleep(for: delay) }
        let handler = try state.withLock { s in
            if !s.failing.isDisjoint(with: captions.keys) { throw CocoaError(.fileWriteNoPermission) }
            let missing = Set(captions.keys).filter { s.assets[$0] == nil }
            if !missing.isEmpty { throw LibraryScanner.WriteError.missing(missing) }
            let locked = Set(captions.keys).intersection(s.locked)
            if !locked.isEmpty { throw LibraryScanner.WriteError.notEditable(locked) }
            s.writes.append(captions)
            for (id, caption) in captions {
                s.assets[id, default: Asset()].caption = caption ?? ""
                s.assets[id]?.keywords = CaptionFormat.tags(in: caption ?? "")
            }
            s.recordChange(touched: Set(captions.keys))
            return s.notifyOwnWrites ? s.onChange : nil
        }
        if let handler { await handler() }
    }

    func reconcileKeywords(ids: [String]) async throws {
        state.withLock { s in
            s.reconciled.append(ids)
            for id in ids {
                let tags = CaptionFormat.tags(in: s.assets[id]?.caption ?? "")
                s.assets[id]?.keywords = tags
            }
            s.recordChange(touched: Set(ids))
        }
    }

    func delete(ids: [String]) async throws {
        let handler = state.withLock { s in
            s.deleted.append(ids)
            for id in ids { s.assets.removeValue(forKey: id) }
            s.recordChange(deleted: Set(ids))
            return s.notifyOwnWrites ? s.onChange : nil
        }
        if let handler { await handler() }
    }

    // MARK: 内部

    /// 和 LibraryScanner.entry(for:) 同样的规则。
    private static func entry(id: String, _ asset: Asset) -> DiaryEntry? {
        guard let caption = asset.caption, LibraryScanner.isDiaryCaption(caption) else { return nil }
        return DiaryEntry(id: id, caption: caption, keywords: asset.keywords, creationDate: asset.date,
                          latitude: asset.latitude, longitude: asset.longitude, mediaKind: asset.kind,
                          isCloudShared: false, pixelWidth: 4032, pixelHeight: 3024)
    }

    static func archive(_ token: Int) -> Data { Data(String(token).utf8) }
    static func unarchive(_ data: Data) -> Int? { Int(String(decoding: data, as: UTF8.self)) }
}

nonisolated private extension FakeLibrary.State {
    mutating func recordChange(touched: Set<String> = [], deleted: Set<String> = []) {
        token += 1
        changes.append((token, touched, deleted))
    }
}
