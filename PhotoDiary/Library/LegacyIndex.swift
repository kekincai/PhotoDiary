import Foundation
import OSLog

/// 旧版本的 JSON 索引快照。现在索引在 SwiftData 数据库里（IndexDatabase），这里只在第一次启动时读出来迁移。
nonisolated struct IndexSnapshot: Codable, Sendable {
    static let currentVersion = 2

    var version = IndexSnapshot.currentVersion
    var entries: [DiaryEntry] = []
    var changeToken: Data?
    /// 曾在本 App 写过的照片。
    var writtenInApp: Set<String> = []
    /// 更早的版本把地名缓存写在索引里。
    var placeCache: [String: String] = [:]
    var timeZoneCache: [String: String]? = [:]
}

/// 旧版本留下的 diary-index.json 和 place-cache.json。迁移完就删掉。
nonisolated struct LegacyIndex: Sendable {
    var directory: URL = .applicationSupportDirectory

    var fileURL: URL { directory.appending(path: "diary-index.json") }
    var placesURL: URL { directory.appending(path: "place-cache.json") }

    /// 没有文件、读不了返回 nil。版本不符也照样返回：条目不能用，但里面的地名缓存还能用。
    @concurrent
    func load() async -> IndexSnapshot? {
        guard let data = read(fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(IndexSnapshot.self, from: data)
        } catch {
            Log.index.error("旧版索引解码失败（\(data.count) 字节）：\(error, privacy: .public)")
            return nil
        }
    }

    @concurrent
    func loadPlaces() async -> PlaceCache? {
        guard let data = read(placesURL) else { return nil }
        do {
            return try JSONDecoder().decode(PlaceCache.self, from: data)
        } catch {
            Log.index.error("旧版地名缓存解码失败：\(error, privacy: .public)")
            return nil
        }
    }

    func remove() {
        for url in [fileURL, placesURL] {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
            } catch {
                Log.index.error("删除 \(url.lastPathComponent, privacy: .public) 失败：\(error, privacy: .public)")
            }
        }
    }

    private func read(_ url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Log.index.error("读取 \(url.lastPathComponent, privacy: .public) 失败：\(error, privacy: .public)")
            return nil
        }
    }
}
