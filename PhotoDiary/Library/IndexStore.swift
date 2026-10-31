import Foundation

/// 本地索引的磁盘快照。照片说明才是正本，这个文件丢了就从照片库重建。
nonisolated struct IndexSnapshot: Codable, Sendable {
    static let currentVersion = 1

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

nonisolated enum IndexStore {
    static var fileURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "diary-index.json")
    }

    @concurrent
    static func load() async -> IndexSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(IndexSnapshot.self, from: data),
              snapshot.version == IndexSnapshot.currentVersion else { return nil }
        return snapshot
    }

    @concurrent
    static func save(_ snapshot: IndexSnapshot) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
