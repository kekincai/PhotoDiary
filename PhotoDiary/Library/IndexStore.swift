import Foundation
import OSLog

/// 本地索引的磁盘快照。照片说明才是正本，这个文件丢了就从照片库重建。
nonisolated struct IndexSnapshot: Codable, Sendable {
    static let currentVersion = 2

    var version = IndexSnapshot.currentVersion
    var entries: [DiaryEntry] = []
    var changeToken: Data?
    /// 曾在本 App 写过的照片。
    var writtenInApp: Set<String> = []
    /// 坐标（约 1km 精度）到地名的缓存，减少反向地理编码请求。
    var placeCache: [String: String] = [:]
    /// 同一坐标的拍摄地时区。
    var timeZoneCache: [String: String]? = [:]
}

/// 索引文件的读写。目录可换，测试用临时目录。
nonisolated struct IndexStore: Sendable {
    var directory: URL = .applicationSupportDirectory

    var fileURL: URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "diary-index.json")
    }

    /// 没有文件、读不了、版本不符都返回 nil，由调用方从照片库重建。
    @concurrent
    func load() async -> IndexSnapshot? {
        let state = Log.signposter.beginInterval("index.load")
        defer { Log.signposter.endInterval("index.load", state) }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            Log.index.info("没有索引文件，将全量读取")
            return nil
        } catch {
            Log.index.error("读取索引失败：\(error, privacy: .public)")
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(IndexSnapshot.self, from: data)
            guard snapshot.version == IndexSnapshot.currentVersion else {
                Log.index.notice("索引版本 \(snapshot.version) 不是当前的 \(IndexSnapshot.currentVersion)，将全量读取")
                return nil
            }
            Log.index.info("读入索引：\(snapshot.entries.count) 条，\(data.count) 字节")
            return snapshot
        } catch {
            Log.index.error("索引解码失败（\(data.count) 字节）：\(error, privacy: .public)")
            return nil
        }
    }

    @concurrent
    func save(_ snapshot: IndexSnapshot) async {
        let state = Log.signposter.beginInterval("index.save")
        defer { Log.signposter.endInterval("index.save", state) }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            Log.index.debug("索引已保存：\(snapshot.entries.count) 条，\(data.count) 字节")
        } catch {
            Log.index.error("保存索引失败：\(error, privacy: .public)")
        }
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Log.index.error("删除索引失败：\(error, privacy: .public)")
        }
    }
}
