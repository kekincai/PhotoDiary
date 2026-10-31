import Foundation
import Photos

/// 读取照片库：全库遍历、按 change token 增量、写入说明与关键词。
/// 所有方法都在后台执行，不持有任何 UI 状态。
nonisolated enum LibraryScanner {
    enum ScanEvent: Sendable {
        case started(total: Int)
        case batch(processed: Int, entries: [DiaryEntry])
        case finished(token: Data?)
    }

    struct IncrementalResult: Sendable {
        var updated: [DiaryEntry]
        /// 删除的照片，或说明被清空的照片。
        var removed: Set<String>
        var token: Data?
    }

    enum ScanError: Error {
        case tokenExpired
    }

    static let sourceTypes: PHAssetSourceType = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

    // MARK: 全库

    /// 后台分批遍历整个照片库，建好的部分先交给界面。
    static func fullScan(batchSize: Int = 400) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                // 先取 token，遍历期间发生的变化会在下次增量里补上。
                let token = archive(PHPhotoLibrary.shared().currentChangeToken)
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.includeAssetSourceTypes = sourceTypes
                options.prefetchAssetExtendedMetadata = true
                let result = PHAsset.fetchAssets(with: options)
                let total = result.count
                continuation.yield(.started(total: total))

                var index = 0
                while index < total {
                    if Task.isCancelled { break }
                    let upper = min(index + batchSize, total)
                    var found: [DiaryEntry] = []
                    autoreleasepool {
                        result.enumerateObjects(at: IndexSet(integersIn: index..<upper)) { asset, _, _ in
                            if let entry = entry(for: asset) { found.append(entry) }
                        }
                    }
                    index = upper
                    continuation.yield(.batch(processed: index, entries: found))
                }
                continuation.yield(.finished(token: Task.isCancelled ? nil : token))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 增量

    /// App 关闭期间或运行中发生的变化，只重新解析变化的照片。
    @concurrent
    static func incremental(since tokenData: Data) async throws -> IncrementalResult {
        guard let token = unarchiveToken(tokenData) else { throw ScanError.tokenExpired }
        let library = PHPhotoLibrary.shared()
        let changes: PHPersistentChangeFetchResult
        do {
            changes = try library.fetchPersistentChanges(since: token)
        } catch {
            throw ScanError.tokenExpired
        }

        var touched = Set<String>()
        var deleted = Set<String>()
        var lastToken: PHPersistentChangeToken?
        for change in changes {
            lastToken = change.changeToken
            guard let details = try? change.changeDetails(for: .asset) else { continue }
            touched.formUnion(details.insertedLocalIdentifiers)
            touched.formUnion(details.updatedLocalIdentifiers)
            deleted.formUnion(details.deletedLocalIdentifiers)
        }
        touched.subtract(deleted)

        let updated = fetchEntries(ids: Array(touched))
        let withCaption = Set(updated.map(\.id))
        let removed = deleted.union(touched.subtracting(withCaption))
        let newToken = archive(lastToken ?? library.currentChangeToken)
        return IncrementalResult(updated: updated, removed: removed, token: newToken)
    }

    static func fetchEntries(ids: [String]) -> [DiaryEntry] {
        guard !ids.isEmpty else { return [] }
        var entries: [DiaryEntry] = []
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = sourceTypes
            options.prefetchAssetExtendedMetadata = true
            let result = PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: options)
            result.enumerateObjects { asset, _, _ in
                if let entry = entry(for: asset) { entries.append(entry) }
            }
        }
        return entries
    }

    static func entry(for asset: PHAsset) -> DiaryEntry? {
        let metadata = asset.extendedMetadata
        guard let caption = metadata.caption,
              !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !CaptionFormat.isCameraBoilerplate(caption) else { return nil }
        let kind: MediaKind = asset.mediaType == .video ? .video
            : asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
        return DiaryEntry(
            id: asset.localIdentifier,
            caption: caption,
            keywords: metadata.keywords,
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            mediaKind: kind,
            isCloudShared: asset.sourceType.contains(.typeCloudShared),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    // MARK: 写入

    /// 写入说明，并让关键词与说明里的标签保持一致。caption 为 nil 表示清除说明。
    @concurrent
    static func write(caption: String?, to id: String) async throws {
        try await write([id: caption])
    }

    /// 一次 performChanges 修改多张照片的说明（标签改名、合并时只弹一次系统确认）。
    @concurrent
    static func write(_ captions: [String: String?]) async throws {
        guard !captions.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = sourceTypes
            options.prefetchAssetExtendedMetadata = true
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(captions.keys), options: options)
            assets.enumerateObjects { asset, _, _ in
                guard let caption = captions[asset.localIdentifier] else { return }
                let request = PHAssetChangeRequest(for: asset)
                request.caption = caption ?? ""
                applyKeywords(tags: CaptionFormat.tags(in: caption ?? ""),
                              current: asset.extendedMetadata.keywords, to: request)
            }
        }
    }

    /// 同步时关键词与标签不一致（例如在 Mac 照片里直接改了关键词），按说明改回。
    @concurrent
    static func reconcileKeywords(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = sourceTypes
            options.prefetchAssetExtendedMetadata = true
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
            assets.enumerateObjects { asset, _, _ in
                guard asset.canPerform(.properties) else { return }
                let request = PHAssetChangeRequest(for: asset)
                applyKeywords(tags: CaptionFormat.tags(in: asset.extendedMetadata.caption ?? ""),
                              current: asset.extendedMetadata.keywords, to: request)
            }
        }
    }

    private static func applyKeywords(tags: [String], current: [String], to request: PHAssetChangeRequest) {
        let target = Set(tags)
        for keyword in current where !target.contains(keyword) { request.removeKeyword(keyword) }
        for tag in tags where !current.contains(tag) { request.addKeyword(tag) }
    }

    @concurrent
    static func delete(ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    // MARK: Token

    static func archive(_ token: PHPersistentChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func unarchiveToken(_ data: Data) -> PHPersistentChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }
}
