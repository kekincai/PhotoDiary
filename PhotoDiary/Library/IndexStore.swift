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
    /// 旧版本把地名缓存写在索引里；现在单独存 place-cache.json，这两项只在迁移时读。
    var placeCache: [String: String] = [:]
    var timeZoneCache: [String: String]? = [:]
}

/// 坐标（约 1km 精度）到地名、拍摄地时区的缓存，减少反向地理编码请求。
/// 和索引分开存：索引版本升级或重建时整个丢掉，地名是按频率限制慢慢查来的，要留着。
nonisolated struct PlaceCache: Codable, Sendable, Equatable {
    var names: [String: String] = [:]
    var timeZones: [String: String] = [:]
}

/// 索引文件的读写。目录可换，测试用临时目录。
///
/// 文件都能从照片库重建，所以不进 iCloud 备份：换机恢复时旧设备的 localIdentifier 在新设备上不成立，
/// 带过去只会先显示一批找不到照片的空白条目。
nonisolated struct IndexStore: Sendable {
    var directory: URL = .applicationSupportDirectory

    var fileURL: URL { url("diary-index.json") }
    var placesURL: URL { url("place-cache.json") }

    private func url(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name)
    }

    /// 没有文件、读不了、版本不符都返回 nil，由调用方从照片库重建。
    @concurrent
    func load() async -> IndexSnapshot? {
        let state = Log.signposter.beginInterval("index.load")
        defer { Log.signposter.endInterval("index.load", state) }
        guard let data = read(fileURL, what: "索引") else { return nil }
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
        var snapshot = snapshot
        snapshot.placeCache = [:]
        snapshot.timeZoneCache = nil
        if let bytes = write(snapshot, to: fileURL, what: "索引") {
            Log.index.debug("索引已保存：\(snapshot.entries.count) 条，\(bytes) 字节")
        }
    }

    @concurrent
    func loadPlaces() async -> PlaceCache? {
        guard let data = read(placesURL, what: "地名缓存") else { return nil }
        do {
            return try JSONDecoder().decode(PlaceCache.self, from: data)
        } catch {
            Log.index.error("地名缓存解码失败：\(error, privacy: .public)")
            return nil
        }
    }

    @concurrent
    func savePlaces(_ places: PlaceCache) async {
        write(places, to: placesURL, what: "地名缓存")
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

    // MARK: 文件

    private func read(_ url: URL, what: String) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            Log.index.info("没有\(what, privacy: .public)文件")
        } catch {
            Log.index.error("读取\(what, privacy: .public)失败：\(error, privacy: .public)")
        }
        return nil
    }

    /// 原子写入并排除备份。原子写入会换掉文件，排除备份的标记每次都要重新设。返回写入的字节数。
    @discardableResult
    private func write(_ value: some Encodable, to url: URL, what: String) -> Int? {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = url
            try url.setResourceValues(values)
            return data.count
        } catch {
            Log.index.error("保存\(what, privacy: .public)失败：\(error, privacy: .public)")
            return nil
        }
    }
}
