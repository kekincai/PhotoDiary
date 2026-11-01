import Photos
import UIKit
import AVFoundation
import OSLog

/// 只从照片库取图，不复制、不存储。缩略图只用本地数据；大图允许从 iCloud 临时下载。
///
/// 滚动时主线程不碰照片库：
/// - PHAsset 在后台一次取齐（`warm`），界面上每个格子直接查字典；照片库变化时只换掉变了的那几张（PHChange），不整体清空。
/// - 解码好的图按“照片 + 尺寸”缓存在内存里，滚回来直接显示，不再请求、不再解码。
/// - 列表告诉这里接下来会显示哪些照片（`startCaching`），PHCachingImageManager 提前准备。
/// - 请求的像素尺寸封顶 1024：再大就超出照片库预生成的缩略图，只能解原图，真机上一张要几十毫秒。
/// 日志（images 类别）：PHAsset 预取、主线程补查、超过 120 ms 的取图都会记下来，Instruments 里有 “取图” 区间。
@MainActor
final class AssetImages {
    static let shared = AssetImages()

    /// 请求的像素尺寸封顶：照片库预生成的缩略图大约到这个尺寸，再大就要解原图。
    nonisolated static let maxPixels: CGFloat = 1024
    /// 取图超过这个时间就记一条日志。
    nonisolated private static let slowThreshold: Duration = .milliseconds(120)

    private let manager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]
    private let observer = ChangeObserver()
    /// 解码好的图：键是 “照片|宽|高”，按像素数计成本。
    private let decoded = NSCache<NSString, UIImage>()
    private var decodedKeys: [String: Set<NSString>] = [:]
    /// 已交给 PHCachingImageManager 预取的 “照片|宽|高”。
    private var caching: Set<String> = []
    private var mainThreadMisses = 0
    /// 正在后台取的 PHAsset，避免列表连着变两次就取两遍。
    private var warming: Set<String> = []
    /// 已经记过“原图在 iCloud”的照片，每张只记一次。
    fileprivate var notedInCloud: Set<String> = []

    private init() {
        decoded.totalCostLimit = 160 * 1024 * 1024
        observer.onChange = { [weak self] change in self?.apply(change) }
        PHPhotoLibrary.shared().register(observer)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didReceiveMemoryWarning() }
        }
    }

    // MARK: 像素尺寸

    /// 按屏幕倍率换算像素，再封顶：最长边不超过 maxPixels。
    nonisolated static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        var px = CGSize(width: points.width * scale, height: points.height * scale)
        let longest = max(px.width, px.height)
        if longest > maxPixels {
            let k = maxPixels / longest
            px = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        }
        return px
    }

    // MARK: PHAsset

    /// 界面上用：命中缓存直接返回；没命中才同步查一次（启动后第一屏可能遇到），并记下来。
    func asset(_ id: String) -> PHAsset? {
        if let cached = assets[id] { return cached }
        mainThreadMisses += 1
        let start = ContinuousClock.now
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).firstObject
        let ms = Self.ms(since: start)
        if ms >= 8 {
            Log.images.notice("主线程补查 PHAsset 用了 \(ms, privacy: .public) ms（累计 \(self.mainThreadMisses, privacy: .public) 次）")
        } else {
            Log.images.debug("主线程补查 PHAsset \(ms) ms（累计 \(self.mainThreadMisses) 次）")
        }
        if let asset { assets[id] = asset }
        return asset
    }

    /// 后台一次取齐这些照片的 PHAsset，日记列表一变就调；之后界面上不再查照片库。
    func warm(ids: [String]) {
        let missing = ids.filter { assets[$0] == nil && !warming.contains($0) }
        guard !missing.isEmpty else { return }
        warming.formUnion(missing)
        Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = LibraryScanner.sourceTypes
            var found: [String: PHAsset] = [:]
            var index = 0
            while index < missing.count {
                let chunk = Array(missing[index..<min(index + 500, missing.count)])
                PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: options).enumerateObjects { asset, _, _ in
                    found[asset.localIdentifier] = asset
                }
                index += 500
            }
            let batch = AssetBatch(assets: found)
            let ms = AssetImages.ms(since: start)
            await MainActor.run {
                let shared = AssetImages.shared
                shared.assets.merge(batch.assets) { _, new in new }
                shared.warming.subtract(missing)
                Log.images.notice("预取 PHAsset \(batch.assets.count, privacy: .public)/\(missing.count, privacy: .public) 张，\(ms, privacy: .public) ms")
            }
        }
    }

    /// 照片库变了：只换掉变了的那几张，删掉的拿走，其余缓存照用。内容变了的照片，解码缓存一并作废。
    private func apply(_ change: PHChange) {
        var updated = 0, removed = 0
        for (id, asset) in assets {
            guard let details = change.changeDetails(for: asset) else { continue }
            if details.objectWasDeleted {
                assets.removeValue(forKey: id)
                removed += 1
            } else if let after = details.objectAfterChanges {
                assets[id] = after
                updated += 1
            }
            if details.assetContentChanged || details.objectWasDeleted { forgetDecoded(id) }
        }
        if updated + removed > 0 {
            Log.images.notice("照片库变化：更新 \(updated, privacy: .public) 张、移除 \(removed, privacy: .public) 张 PHAsset")
        }
    }

    private func didReceiveMemoryWarning() {
        decoded.removeAllObjects()
        decodedKeys.removeAll()
        manager.stopCachingImagesForAllAssets()
        caching.removeAll()
        Log.images.notice("内存紧张，清空解码缓存")
    }

    // MARK: 解码缓存

    private func key(_ id: String, _ px: CGSize) -> NSString {
        "\(id)|\(Int(px.width))|\(Int(px.height))" as NSString
    }

    /// 已解码好的图，有就同步给，界面第一帧直接画出来。
    func cached(_ id: String, pixelSize: CGSize) -> UIImage? {
        decoded.object(forKey: key(id, pixelSize))
    }

    private func remember(_ image: UIImage, id: String, px: CGSize) {
        let k = key(id, px)
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        decoded.setObject(image, forKey: k, cost: cost)
        decodedKeys[id, default: []].insert(k)
    }

    private func forgetDecoded(_ id: String) {
        for k in decodedKeys.removeValue(forKey: id) ?? [] { decoded.removeObject(forKey: k) }
    }

    // MARK: 预取

    /// 列表告诉这里接下来会显示哪些照片：PHCachingImageManager 提前解好。只认已经取到 PHAsset 的照片。
    func startCaching(ids: [String], pixelSize: CGSize) {
        var fresh: [PHAsset] = []
        for id in ids {
            let k = "\(id)|\(Int(pixelSize.width))|\(Int(pixelSize.height))"
            guard !caching.contains(k), cached(id, pixelSize: pixelSize) == nil, let asset = assets[id] else { continue }
            caching.insert(k)
            fresh.append(asset)
        }
        guard !fresh.isEmpty else { return }
        if caching.count > 600 {
            manager.stopCachingImagesForAllAssets()
            caching = Set(fresh.map { "\($0.localIdentifier)|\(Int(pixelSize.width))|\(Int(pixelSize.height))" })
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        manager.startCachingImages(for: fresh, targetSize: pixelSize, contentMode: .aspectFill, options: options)
        Log.images.debug("预取图 \(fresh.count) 张（\(Int(pixelSize.width))×\(Int(pixelSize.height))）")
    }

    // MARK: 取图

    /// 先给低清图，再给清晰图。命中解码缓存时直接给清晰图。
    func images(for id: String, pixelSize: CGSize, contentMode: PHImageContentMode = .aspectFill,
                allowNetwork: Bool = false) -> AsyncStream<UIImage> {
        if let hit = cached(id, pixelSize: pixelSize) {
            return AsyncStream { continuation in
                continuation.yield(hit)
                continuation.finish()
            }
        }
        return AsyncStream { continuation in
            guard let asset = asset(id) else { continuation.finish(); return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            let start = ContinuousClock.now
            let signpostID = Log.signposter.makeSignpostID()
            let interval = Log.signposter.beginInterval("取图", id: signpostID)
            nonisolated(unsafe) var gotDegraded = false
            let requestID = manager.requestImage(for: asset, targetSize: pixelSize, contentMode: contentMode,
                                                 options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                if let image {
                    continuation.yield(image)
                    if !degraded {
                        Task { @MainActor in AssetImages.shared.remember(image, id: id, px: pixelSize) }
                    }
                }
                if degraded { gotDegraded = true }
                if let error, (error as NSError).code == PHPhotosError.userCancelled.rawValue {
                    // 视图消失或尺寸变了，请求被取消，不是失败。
                    Log.images.debug("取图已取消 \(id)（\(Int(pixelSize.width))×\(Int(pixelSize.height))）")
                } else if let error, !allowNetwork, (error as NSError).code == PHPhotosError.networkAccessRequired.rawValue {
                    // 开了“优化储存空间”的照片本机只有小图：缩略图、封面这类本来就只用本地的，拿到模糊的预览就够了，
                    // 不算失败；每张照片只记一次，免得封面轮换每隔几秒刷一行。
                    Task { @MainActor in
                        if AssetImages.shared.notedInCloud.insert(id).inserted {
                            Log.images.notice("原图在 iCloud，只用本地预览 \(id)")
                        }
                    }
                } else if let error {
                    Log.images.error("取图失败 \(id)（\(Int(pixelSize.width))×\(Int(pixelSize.height))，联网 \(allowNetwork)）：\(error, privacy: .public)")
                } else if image == nil, !cancelled, !degraded {
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    Log.images.notice("没有拿到图 \(id)\(inCloud ? "，原图在 iCloud" : "", privacy: .public)")
                }
                if !degraded || cancelled || error != nil {
                    let elapsed = start.duration(to: .now)
                    Log.signposter.endInterval("取图", interval)
                    if elapsed > AssetImages.slowThreshold, !cancelled {
                        let ms = Int(elapsed / .milliseconds(1))
                        Log.images.notice("取图慢 \(Int(pixelSize.width), privacy: .public)×\(Int(pixelSize.height), privacy: .public)：\(ms, privacy: .public) ms\(gotDegraded ? "，先给了预览" : "", privacy: .public)\(allowNetwork ? "，允许联网" : "", privacy: .public)")
                    }
                    continuation.finish()
                }
            }
            let manager = manager
            continuation.onTermination = { _ in
                Task { @MainActor in manager.cancelImageRequest(requestID) }
            }
        }
    }

    nonisolated private static func ms(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
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
                if let error = info?[PHImageErrorKey] as? Error {
                    Log.images.error("取实况照片失败 \(id)：\(error, privacy: .public)")
                }
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
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    Log.images.error("取视频失败 \(id)：\(error, privacy: .public)")
                }
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

    /// 手记建议里的照片是系统给的副本，没有 localIdentifier；按拍摄时间（±1 秒）找回照片库里的原片。
    /// 对不上时退回到这段时间里的第一张照片。
    nonisolated static func asset(takenAt dates: [Date], orIn interval: DateInterval?) -> String? {
        if let first = dates.min(), let last = dates.max() {
            let matches = assets(from: first.addingTimeInterval(-1), to: last.addingTimeInterval(1))
            if let hit = matches.first(where: { match in dates.contains { abs($0.timeIntervalSince(match.date)) <= 1 } }) {
                return hit.id
            }
        }
        guard let interval else { return nil }
        return assets(from: interval.start, to: interval.end).first?.id
    }

    private nonisolated static func assets(from start: Date, to end: Date) -> [(id: String, date: Date)] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var out: [(String, Date)] = []
        result.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate { out.append((asset.localIdentifier, date)) }
        }
        return out
    }
}

/// PHAsset 不是 Sendable，但它是只读快照，后台取好一批再交给主线程是安全的。
private struct AssetBatch: @unchecked Sendable {
    let assets: [String: PHAsset]
}

/// 把 PHChange 送回主线程，让缓存只换掉变了的照片。
private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    var onChange: (@MainActor (PHChange) -> Void)?

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [onChange] in onChange?(changeInstance) }
    }
}
