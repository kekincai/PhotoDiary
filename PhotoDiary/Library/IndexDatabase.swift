import Foundation
import OSLog
import SwiftData

// 本地索引数据库（SwiftData）。照片说明才是正本，这里的东西都能从照片库重建：
// - 每张带说明的照片一行，连同解析好的结果，启动时直接读出来，不逐条重新解析说明；
// - change token 和条目在同一个事务里写，不会出现 token 领先于条目的情况；
// - 每次只写变化的行（增量同步改了 3 张就写 3 行），不再整份重写；
// - 地名缓存单独一个库文件：条目库打不开要重建时，按频率限制慢慢查来的地名不跟着丢。
//
// 两个库文件都放在 Application Support/Index/，整个目录不进 iCloud 备份：
// 换机恢复时旧设备的 localIdentifier 在新设备上不成立，带过去只会先显示一批找不到照片的空白条目。

@Model
nonisolated final class EntryRecord {
    #Index<EntryRecord>([\.id])
    var id: String
    var caption: String
    var keywords: [String]
    var creationDate: Date?
    var latitude: Double?
    var longitude: Double?
    var mediaKind: String
    var isCloudShared: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var placeName: String?
    var timeZoneID: String?
    var writtenInApp: Bool
    /// 解析结果（CaptionDisplay 的 JSON）和当时的解析规则版本。
    var display: Data
    var displayVersion: Int

    init(_ entry: DiaryEntry) {
        id = entry.id
        caption = entry.caption
        keywords = entry.keywords
        creationDate = entry.creationDate
        latitude = entry.latitude
        longitude = entry.longitude
        mediaKind = entry.mediaKind.rawValue
        isCloudShared = entry.isCloudShared
        pixelWidth = entry.pixelWidth
        pixelHeight = entry.pixelHeight
        placeName = entry.placeName
        timeZoneID = entry.timeZoneID
        writtenInApp = entry.writtenInApp
        display = Data()
        displayVersion = 0
        update(from: entry)
    }

    func update(from entry: DiaryEntry) {
        caption = entry.caption
        keywords = entry.keywords
        creationDate = entry.creationDate
        latitude = entry.latitude
        longitude = entry.longitude
        mediaKind = entry.mediaKind.rawValue
        isCloudShared = entry.isCloudShared
        pixelWidth = entry.pixelWidth
        pixelHeight = entry.pixelHeight
        placeName = entry.placeName
        timeZoneID = entry.timeZoneID
        writtenInApp = entry.writtenInApp
        display = (try? JSONEncoder().encode(entry.display)) ?? Data()
        displayVersion = CaptionDisplay.version
    }

    /// 解析规则没变就用存着的结果；变了（或读不出来）就重新解析。
    func entry(decoder: JSONDecoder) -> (entry: DiaryEntry, reparsed: Bool) {
        let cached = displayVersion == CaptionDisplay.version ? try? decoder.decode(CaptionDisplay.self, from: display) : nil
        let entry = DiaryEntry(id: id, caption: caption, keywords: keywords, creationDate: creationDate,
                               latitude: latitude, longitude: longitude,
                               mediaKind: MediaKind(rawValue: mediaKind) ?? .photo, isCloudShared: isCloudShared,
                               pixelWidth: pixelWidth, pixelHeight: pixelHeight, placeName: placeName,
                               timeZoneID: timeZoneID, writtenInApp: writtenInApp, display: cached)
        return (entry, cached == nil)
    }
}

/// 同步进度，只有一行。
@Model
nonisolated final class SyncRecord {
    var changeToken: Data?
    /// 拿到这个 token 时的照片权限（PHAuthorizationStatus 的 rawValue）。
    var access: Int?

    init(changeToken: Data?, access: Int?) {
        self.changeToken = changeToken
        self.access = access
    }
}

/// 坐标（约 1km 精度）→ 地名、拍摄地时区。
@Model
nonisolated final class PlaceRecord {
    @Attribute(.unique) var key: String
    var name: String
    var timeZone: String?

    init(key: String, name: String, timeZone: String?) {
        self.key = key
        self.name = name
        self.timeZone = timeZone
    }
}

/// 地名缓存在内存里的样子。
nonisolated struct PlaceCache: Sendable, Equatable {
    var names: [String: String] = [:]
    var timeZones: [String: String] = [:]
}

@ModelActor
actor IndexDatabase {
    struct Loaded: Sendable {
        var entries: [DiaryEntry] = []
        var changeToken: Data?
        var tokenAccess: Int?
        var places = PlaceCache()
    }

    /// 一次要写进库里的变化。
    struct Changes: Sendable {
        var upserts: [DiaryEntry] = []
        var deletions: Set<String> = []
        var changeToken: Data?
        var tokenAccess: Int?
        var places: [String: (name: String, timeZone: String?)] = [:]
    }

    struct Stats: Sendable, Equatable {
        var upserted = 0
        var deleted = 0
    }

    // MARK: 打开

    static let entriesStoreName = "entries.store"
    static let placesStoreName = "places.store"

    /// 打开 directory/Index/ 下的数据库。条目库打不开（例如模型改得不兼容）就删掉重建，地名库照常保留；
    /// 都不行时退回只在内存里，App 照常能用，只是下次启动要重读照片库。
    @concurrent
    static func open(directory: URL) async -> IndexDatabase {
        let folder = directory.appending(path: "Index", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = folder
            try url.setResourceValues(values)
        } catch {
            Log.index.error("创建索引目录失败：\(error, privacy: .public)")
        }

        let entriesURL = folder.appending(path: entriesStoreName)
        let placesURL = folder.appending(path: placesStoreName)
        func container() throws -> ModelContainer {
            try ModelContainer(for: EntryRecord.self, SyncRecord.self, PlaceRecord.self, configurations:
                ModelConfiguration("entries", schema: Schema([EntryRecord.self, SyncRecord.self]), url: entriesURL),
                ModelConfiguration("places", schema: Schema([PlaceRecord.self]), url: placesURL))
        }
        do {
            let begin = ContinuousClock.now
            let database = IndexDatabase(modelContainer: try container())
            Log.index.debug("打开索引数据库：\(ContinuousClock.now - begin, privacy: .public)")
            return database
        } catch {
            Log.index.error("打开索引数据库失败，删除条目库后重建：\(error, privacy: .public)")
            removeStore(at: entriesURL)
        }
        do {
            return IndexDatabase(modelContainer: try container())
        } catch {
            Log.index.fault("重建索引数据库仍然失败，改用内存：\(error, privacy: .public)")
            removeStore(at: placesURL)
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            // 内存库不会打不开。
            return IndexDatabase(modelContainer: try! ModelContainer(for: EntryRecord.self, SyncRecord.self, PlaceRecord.self,
                                                                     configurations: memory))
        }
    }

    /// SQLite 库连同 -wal、-shm 一起删。路径要用不带百分号编码的（Application Support 里有空格）。
    static func removeStore(at url: URL) {
        let folder = url.deletingLastPathComponent()
        for suffix in ["", "-wal", "-shm"] {
            let file = folder.appending(path: url.lastPathComponent + suffix)
            do {
                try FileManager.default.removeItem(at: file)
            } catch CocoaError.fileNoSuchFile {
                // 本来就没有（-wal、-shm 不一定在）。
            } catch {
                Log.index.error("删除 \(file.lastPathComponent, privacy: .public) 失败：\(error, privacy: .public)")
            }
        }
    }

    // MARK: 读

    func load() -> Loaded {
        let state = Log.signposter.beginInterval("index.load")
        defer { Log.signposter.endInterval("index.load", state) }
        var loaded = Loaded()
        do {
            let decoder = JSONDecoder()
            var reparsed = 0
            for record in try modelContext.fetch(FetchDescriptor<EntryRecord>()) {
                let (entry, didReparse) = record.entry(decoder: decoder)
                if didReparse {
                    record.update(from: entry)
                    reparsed += 1
                }
                loaded.entries.append(entry)
            }
            if reparsed > 0 {
                try modelContext.save()
                Log.index.notice("解析规则变了，重新解析 \(reparsed) 条")
            }
            if let sync = try modelContext.fetch(FetchDescriptor<SyncRecord>()).first {
                loaded.changeToken = sync.changeToken
                loaded.tokenAccess = sync.access
            }
            for place in try modelContext.fetch(FetchDescriptor<PlaceRecord>()) {
                loaded.places.names[place.key] = place.name
                loaded.places.timeZones[place.key] = place.timeZone
            }
            Log.index.info("读入索引：\(loaded.entries.count) 条，地名 \(loaded.places.names.count) 个")
        } catch {
            Log.index.error("读取索引失败：\(error, privacy: .public)")
        }
        return loaded
    }

    // MARK: 写

    /// 条目、token、地名一起写入：条目和 token 在条目库里，同一次保存；地名在另一个库文件里（条目库损坏重建时地名留着），
    /// 用的是同一个上下文的同一次 save，但不是跨两个文件的原子事务。
    @discardableResult
    func apply(_ changes: Changes) throws -> Stats {
        let state = Log.signposter.beginInterval("index.save")
        defer { Log.signposter.endInterval("index.save", state) }
        var stats = Stats()

        let deletions = changes.deletions.subtracting(changes.upserts.map(\.id))
        if !deletions.isEmpty {
            for chunk in Self.chunks(Array(deletions)) {
                let ids = Array(chunk)
                try modelContext.delete(model: EntryRecord.self, where: #Predicate { ids.contains($0.id) })
            }
            stats.deleted = deletions.count
        }

        if !changes.upserts.isEmpty {
            // 先查完已有的行再插入：插入后的查询要在内存里扫一遍所有未保存的新对象，越往后越慢。
            var byID: [String: EntryRecord] = [:]
            for chunk in Self.chunks(changes.upserts) {
                let ids = chunk.map(\.id)
                for record in try modelContext.fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { ids.contains($0.id) })) {
                    byID[record.id] = record
                }
            }
            for entry in changes.upserts {
                if let record = byID[entry.id] { record.update(from: entry) } else { modelContext.insert(EntryRecord(entry)) }
            }
            stats.upserted = changes.upserts.count
        }

        if let sync = try modelContext.fetch(FetchDescriptor<SyncRecord>()).first {
            sync.changeToken = changes.changeToken
            sync.access = changes.tokenAccess
        } else {
            modelContext.insert(SyncRecord(changeToken: changes.changeToken, access: changes.tokenAccess))
        }

        if !changes.places.isEmpty {
            var byKey: [String: PlaceRecord] = [:]
            for chunk in Self.chunks(Array(changes.places.keys)) {
                let keys = Array(chunk)
                for record in try modelContext.fetch(FetchDescriptor<PlaceRecord>(predicate: #Predicate { keys.contains($0.key) })) {
                    byKey[record.key] = record
                }
            }
            for (key, place) in changes.places {
                if let record = byKey[key] {
                    record.name = place.name
                    record.timeZone = place.timeZone
                } else {
                    modelContext.insert(PlaceRecord(key: key, name: place.name, timeZone: place.timeZone))
                }
            }
        }

        try modelContext.save()
        Log.index.debug("索引已保存：写入 \(stats.upserted) 行，删除 \(stats.deleted) 行，地名 \(changes.places.count) 个")
        return stats
    }

    /// 谓词里的 IN 列表不宜太长。
    private static func chunks<T>(_ items: [T], size: Int = 500) -> [ArraySlice<T>] {
        stride(from: 0, to: items.count, by: size).map { items[$0..<min($0 + size, items.count)] }
    }
}
