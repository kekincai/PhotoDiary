import Photos
import UIKit
import AVFoundation

/// 只从照片库取图，不复制、不存储。缩略图只用本地数据；大图允许从 iCloud 临时下载。
@MainActor
final class AssetImages {
    static let shared = AssetImages()

    private let manager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]

    func asset(_ id: String) -> PHAsset? {
        if let cached = assets[id] { return cached }
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).firstObject else { return nil }
        assets[id] = asset
        return asset
    }

    func forget(_ id: String) { assets.removeValue(forKey: id) }

    /// 先给低清图，再给清晰图。
    func images(for id: String, pixelSize: CGSize, contentMode: PHImageContentMode = .aspectFill,
                allowNetwork: Bool = false) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = asset(id) else { continuation.finish(); return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            let requestID = manager.requestImage(for: asset, targetSize: pixelSize, contentMode: contentMode,
                                                 options: options) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if !degraded || cancelled || info?[PHImageErrorKey] != nil { continuation.finish() }
            }
            let manager = manager
            continuation.onTermination = { _ in
                Task { @MainActor in manager.cancelImageRequest(requestID) }
            }
        }
    }

    func livePhoto(for id: String, pixelSize: CGSize) async -> PHLivePhoto? {
        guard let asset = asset(id) else { return nil }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestLivePhoto(for: asset, targetSize: pixelSize, contentMode: .aspectFit,
                                                      options: options) { photo, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: photo)
            }
        }
    }

    func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    /// 最近的照片（不读说明），用于“从照片添加”。
    nonisolated static func recentAssets(limit: Int) -> [(id: String, date: Date?)] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: options)
        var out: [(String, Date?)] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in out.append((asset.localIdentifier, asset.creationDate)) }
        return out
    }
}
