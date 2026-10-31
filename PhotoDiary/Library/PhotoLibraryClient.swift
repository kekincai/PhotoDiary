import Foundation
import Photos

/// DiaryStore 对照片库的全部依赖。App 里是 PhotoKitLibrary，测试里换成内存里的假照片库。
nonisolated protocol PhotoLibraryClient: Sendable {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    /// 照片库变化时回调；返回值要一直持有，释放即停止监听。
    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject

    func fullScan() -> AsyncStream<LibraryScanner.ScanEvent>
    func incremental(since token: Data) async throws -> LibraryScanner.IncrementalResult
    func fetchEntries(ids: [String]) -> [DiaryEntry]
    func currentCaption(for id: String) -> String?

    func write(_ captions: [String: String?]) async throws
    func reconcileKeywords(ids: [String]) async throws
    func delete(ids: [String]) async throws
}

/// 真实照片库，转给 LibraryScanner。
nonisolated struct PhotoKitLibrary: PhotoLibraryClient {
    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject {
        let observer = LibraryObserver(onChange: onChange)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }

    func fullScan() -> AsyncStream<LibraryScanner.ScanEvent> { LibraryScanner.fullScan() }

    func incremental(since token: Data) async throws -> LibraryScanner.IncrementalResult {
        try await LibraryScanner.incremental(since: token)
    }

    func fetchEntries(ids: [String]) -> [DiaryEntry] { LibraryScanner.fetchEntries(ids: ids) }

    func currentCaption(for id: String) -> String? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.extendedMetadata.caption
    }

    func write(_ captions: [String: String?]) async throws { try await LibraryScanner.write(captions) }

    func reconcileKeywords(ids: [String]) async throws { try await LibraryScanner.reconcileKeywords(ids: ids) }

    func delete(ids: [String]) async throws { try await LibraryScanner.delete(ids: ids) }
}

/// PHPhotoLibraryChangeObserver：App 运行时收到变更就做一次增量同步。
nonisolated private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    let onChange: @MainActor @Sendable () -> Void

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in onChange() }
    }
}
