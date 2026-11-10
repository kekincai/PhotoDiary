import Foundation
import UIKit
import WidgetKit
import Photos
import OSLog

/// App 这边给小组件写快照（见 WidgetSnapshot）。
///
/// - 日记变化、回到前台、换语言后（防抖）重算一周的那年今日；内容没变就不写、不刷新小组件。
/// - 照片缩小成 JPEG 放进共享容器，只做缺的那几张；不再用到的删掉。
/// - Mac 版没有 App Group（也没有小组件），共享容器取不到就什么都不做。
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private weak var store: DiaryStore?
    private var task: Task<Void, Never>?
    /// 上次写出去的（不含生成时间）。
    private var last: WidgetSnapshot?

    private init() {}

    func start(store: DiaryStore) {
        attach(store: store)
        scheduleUpdate(after: .zero)
    }

    /// 只连上日记库（测试直接调 updateNow）。
    func attach(store: DiaryStore) {
        self.store = store
        last = nil
    }

    /// 不等防抖，现在就写。
    func updateNow() async {
        task?.cancel()
        await update()
    }

    func scheduleUpdate(after delay: Duration = .seconds(2)) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await update()
        }
    }

    private func update() async {
        // 有权限时等索引读出来再写（不然写出去的是空的）；没有权限时直接写一份空的：撤销权限后不留旧的日记和照片在小组件上。
        guard let store, store.hasLoaded || !store.canRead, let directory = WidgetSnapshot.directory else { return }
        let diaries = store.canRead ? store.diaries : []
        var snapshot = WidgetSnapshot.make(diaries: diaries, today: .today, language: AppLanguage.current.rawValue)
        if let last {
            snapshot.generated = last.generated
            if snapshot == last { return }
        }
        snapshot.generated = .now

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let wanted = Set(snapshot.memories.map { WidgetSnapshot.thumbnailName(for: $0.id) })
            for memory in snapshot.memories {
                let url = directory.appending(path: WidgetSnapshot.thumbnailName(for: memory.id))
                guard !FileManager.default.fileExists(atPath: url.path) else { continue }
                if let data = await thumbnail(memory.id) { try data.write(to: url, options: .atomic) }
                guard !Task.isCancelled else { return }
            }
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
            where name.hasSuffix(".jpg") && !wanted.contains(name) {
                try? FileManager.default.removeItem(at: directory.appending(path: name))
            }
            let data = try JSONEncoder().encode(snapshot)
            if let url = WidgetSnapshot.fileURL { try data.write(to: url, options: .atomic) }
            last = snapshot
            WidgetCenter.shared.reloadAllTimelines()
            Log.app.info("小组件快照：\(snapshot.memories.count, privacy: .public) 篇那年今日")
        } catch {
            Log.app.error("写小组件快照失败：\(error, privacy: .public)")
        }
    }

    /// 缩到最长边 thumbnailPixels 的 JPEG。只用本地已有的图，不为小组件去下载。
    private func thumbnail(_ id: String) async -> Data? {
        let side = WidgetSnapshot.thumbnailPixels
        var image: UIImage?
        for await next in AssetImages.shared.images(for: id, pixelSize: CGSize(width: side, height: side), contentMode: .aspectFit) {
            image = next
        }
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let k = min(1, side / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * k).rounded(), height: (pixels.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.75) { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
