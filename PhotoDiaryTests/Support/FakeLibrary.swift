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

    /// 在别的 App 里改了说明（nil 表示删除照片），并像 PHPhotoLibraryChangeObserver 一样通知。
    /// `notify: false` 模拟本 App 没在运行时发生的修改。
    @MainActor
    func externalEdit(_ id: String, caption: String?, notify: Bool = true) {
        let handler = state.withLock { s in
            if let caption {
                s.assets[id, default: Asset()].caption = caption
                s.recordChange(touched: [id])
            } else {
                s.assets.removeValue(forKey: id)
                s.recordChange(deleted: [id])
            }
            return notify ? s.onChange : nil
        }
        handler?()
    }

    /// 让手里所有的 token 失效（例如系统清理了变更历史）。
    func expireTokens() {
        state.withLock { $0.oldestValidToken = $0.token + 1 }
    }

    var fullScans: Int { state.withLock { $0.fullScans } }
    var incrementals: Int { state.withLock { $0.incrementals } }
    var writes: [[String: String?]] { state.withLock { $0.writes } }

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
        return AsyncStream { continuation in
            continuation.yield(.started(total: total))
            var processed = 0
            for start in stride(from: 0, to: max(entries.count, 1), by: batchSize) {
                let batch = Array(entries[start..<min(start + batchSize, entries.count)])
                processed = min(processed + batchSize, total)
                continuation.yield(.batch(processed: processed, entries: batch))
            }
            continuation.yield(.finished(token: Self.archive(token)))
            continuation.finish()
        }
    }

    func incremental(since tokenData: Data) async throws -> LibraryScanner.IncrementalResult {
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

    func currentCaption(for id: String) -> String? { caption(of: id) }

    func write(_ captions: [String: String?]) async throws {
        state.withLock { s in
            s.writes.append(captions)
            for (id, caption) in captions {
                s.assets[id, default: Asset()].caption = caption ?? ""
                s.assets[id]?.keywords = CaptionFormat.tags(in: caption ?? "")
            }
            s.recordChange(touched: Set(captions.keys))
        }
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
        state.withLock { s in
            s.deleted.append(ids)
            for id in ids { s.assets.removeValue(forKey: id) }
            s.recordChange(deleted: Set(ids))
        }
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
