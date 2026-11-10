import Foundation
import Photos
import UIKit
import AVFoundation
import CoreLocation
import Synchronization
import Testing
@testable import PhotoDiary

/// 在模拟器的真实照片库里造照片和视频，给直接读写 PhotoKit 的测试用。
///
/// 这些测试会往照片库里加东西，所以默认不跑：`Tools/test.sh` 在一台专用的测试模拟器上
/// 授权照片访问后，用环境变量 `TEST_RUNNER_PHOTODIARY_PHOTOKIT_TESTS=1` 打开。
nonisolated enum PhotoFixtures {
    static var enabled: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["PHOTODIARY_PHOTOKIT_TESTS"] == "1"
        #else
        false
        #endif
    }

    static var authorized: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    /// 没指定日期时用的拍摄时间：很早，排在照片库最后，不把界面测试要找的种子照片挤到下面去。
    static let oldDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 12))!

    /// 一张纯色照片，可选拍摄时间和位置。返回 localIdentifier。
    static func makePhoto(date: Date = oldDate, location: CLLocation? = nil, hue: CGFloat = .random(in: 0...1)) async throws -> String {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        let data = image.jpegData(compressionQuality: 0.9)!
        return try await create { request in
            request.addResource(with: .photo, data: data, options: nil)
            request.creationDate = date
            request.location = location
        }
    }

    /// 一段一秒的小视频。
    static func makeVideo() async throws -> String {
        let url = try await writeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        return try await create { request in
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }

    private static func create(_ configure: @escaping @Sendable (PHAssetCreationRequest) -> Void) async throws -> String {
        let id = Mutex<String?>(nil)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            configure(request)
            id.withLock { $0 = request.placeholderForCreatedAsset?.localIdentifier }
        }
        let created = try #require(id.withLock { $0 })
        Self.created.withLock { $0.append(created) }
        return created
    }

    /// 测试造的照片。删照片要系统确认（测试里点不了），所以只清掉说明：照片还在，但不再是日记。
    /// `Tools/test.sh` 每次都抹掉模拟器，留下的照片不会越积越多。
    private static let created = Mutex<[String]>([])

    static func clearCreatedCaptions() async {
        let ids = created.withLock { ids in defer { ids = [] }; return ids }
        guard !ids.isEmpty else { return }
        try? await LibraryScanner.write(Dictionary(uniqueKeysWithValues: ids.map { ($0, String?.none) }))
    }

    /// 用 AVAssetWriter 写一段 64×64、1 秒、H.264 的视频。
    private static func writeVideo() async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "PhotoDiaryTests-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    /// 照片库里这张照片现在的说明和关键词（不经过 App 的任何缓存）。
    static func metadata(_ id: String) -> (caption: String?, keywords: [String])? {
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).firstObject else { return nil }
        let metadata = asset.extendedMetadata
        return (metadata.caption, metadata.keywords)
    }
}

/// 每个测试结束后（不管成败）清掉它写进照片的说明。
nonisolated struct ClearsCreatedCaptions: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        do {
            try await function()
        } catch {
            await PhotoFixtures.clearCreatedCaptions()
            throw error
        }
        await PhotoFixtures.clearCreatedCaptions()
    }
}

extension Trait where Self == ClearsCreatedCaptions {
    static var clearsCreatedCaptions: Self { Self() }
}
