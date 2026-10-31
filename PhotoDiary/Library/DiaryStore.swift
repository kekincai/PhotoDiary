import Foundation
import Observation
import Photos
import UIKit

/// App 的单一数据源：本地索引 + 照片库同步。
@Observable
final class DiaryStore {
    enum SyncState: Equatable {
        case idle
        case scanning(processed: Int, total: Int)
    }

    private(set) var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var syncState: SyncState = .idle
    private(set) var hasLoaded = false

    /// 所有带说明的照片，按 localIdentifier 索引。
    private(set) var entries: [String: DiaryEntry] = [:] {
        didSet { rebuildDerived() }
    }

    /// 日记（按照片日期倒序）。
    private(set) var diaries: [DiaryEntry] = []
    /// 外部说明（Lightroom 导入、以前手写的）。
    private(set) var externals: [DiaryEntry] = []
    /// 标签及数量，按数量排序。
    private(set) var tagCounts: [(name: String, count: Int)] = []

    var showExternal: Bool = UserDefaults.standard.bool(forKey: "showExternal") {
        didSet {
            UserDefaults.standard.set(showExternal, forKey: "showExternal")
            rebuildDerived()
        }
    }

    /// 列表、日历、照片、地图里显示的条目。
    private(set) var timeline: [DiaryEntry] = []

    private var changeToken: Data?
    private var writtenInApp: Set<String> = []
    private var placeCache: [String: String] = [:]
    private var timeZoneCache: [String: String] = [:]
    private var observer: LibraryObserver?
    private var syncTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pendingIncremental = false
    private let placeNamer = PlaceNamer()

    var isLimited: Bool { authorization == .limited }
    var canRead: Bool { authorization == .authorized || authorization == .limited }

    // MARK: 启动

    func start() async {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else { return }
        if !hasLoaded, let snapshot = await IndexStore.load() {
            writtenInApp = snapshot.writtenInApp
            placeCache = snapshot.placeCache
            timeZoneCache = snapshot.timeZoneCache ?? [:]
            changeToken = snapshot.changeToken
            entries = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        }
        hasLoaded = true
        registerObserver()
        sync()
    }

    func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await start()
    }

    func refreshAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != authorization else { return }
        authorization = status
        if canRead { Task { await start() } }
    }

    private func registerObserver() {
        guard observer == nil else { return }
        let observer = LibraryObserver { [weak self] in self?.scheduleIncremental() }
        PHPhotoLibrary.shared().register(observer)
        self.observer = observer
    }

    // MARK: 同步

    /// 有 token 走增量，否则（或 token 失效）全库重建。
    func sync() {
        guard syncTask == nil else { pendingIncremental = true; return }
        syncTask = Task {
            if let token = changeToken {
                do {
                    let result = try await LibraryScanner.incremental(since: token)
                    apply(result)
                } catch {
                    await fullScan()
                }
            } else {
                await fullScan()
            }
            syncTask = nil
            if pendingIncremental {
                pendingIncremental = false
                sync()
            }
        }
    }

    func rebuildIndex() {
        syncTask?.cancel()
        syncTask = nil
        changeToken = nil
        sync()
    }

    private var incrementalDebounce: Task<Void, Never>?

    private func scheduleIncremental() {
        incrementalDebounce?.cancel()
        incrementalDebounce = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    private func fullScan() async {
        var fresh: [String: DiaryEntry] = [:]
        for await event in LibraryScanner.fullScan() {
            switch event {
            case .started(let total):
                syncState = .scanning(processed: 0, total: total)
            case .batch(let processed, let found):
                var decorated: [(String, DiaryEntry)] = []
                for var entry in found {
                    decorate(&entry)
                    fresh[entry.id] = entry
                    decorated.append((entry.id, entry))
                }
                if case .scanning(_, let total) = syncState {
                    syncState = .scanning(processed: processed, total: total)
                }
                // 建好的部分先可用。
                if !decorated.isEmpty {
                    entries.merge(decorated, uniquingKeysWith: { _, b in b })
                }
            case .finished(let token):
                if let token {
                    entries = fresh
                    changeToken = token
                }
            }
        }
        syncState = .idle
        scheduleSave()
        afterSync(ids: Array(entries.keys))
    }

    private func apply(_ result: LibraryScanner.IncrementalResult) {
        var copy = entries
        for id in result.removed { copy.removeValue(forKey: id) }
        for var entry in result.updated {
            decorate(&entry)
            copy[entry.id] = entry
        }
        if copy != entries { entries = copy }
        changeToken = result.token
        scheduleSave()
        afterSync(ids: result.updated.map(\.id))
    }

    /// 补上本地才有的信息：曾在本 App 写过、地点名称。
    private func decorate(_ entry: inout DiaryEntry) {
        entry.writtenInApp = writtenInApp.contains(entry.id)
        if let old = entries[entry.id], old.latitude == entry.latitude, old.longitude == entry.longitude {
            entry.placeName = old.placeName
            entry.timeZoneID = old.timeZoneID
        }
        if entry.placeName == nil, let key = placeKey(entry) {
            entry.placeName = placeCache[key]
            entry.timeZoneID = timeZoneCache[key]
        }
    }

    private func afterSync(ids: [String]) {
        // 关键词完全由说明里的标签生成；只修正日记，不碰外部说明。
        let mismatched = ids.compactMap { entries[$0] }.filter {
            $0.isDiary && Set($0.keywords) != Set($0.tags)
        }.map(\.id)
        if !mismatched.isEmpty {
            Task { try? await LibraryScanner.reconcileKeywords(ids: mismatched) }
        }
        resolvePlaces()
    }

    // MARK: 写入

    enum WriteMode: Equatable {
        case new, append, edit
    }

    /// 写日记 / 追加感想 / 编辑整条说明。成功后立即更新索引。
    func save(text: String, mode: WriteMode, for id: String) async throws {
        let existing = entries[id]?.caption ?? currentCaption(for: id)
        let caption: String?
        switch mode {
        case .new, .append:
            caption = CaptionFormat.appending(text, to: existing)
        case .edit:
            caption = CaptionFormat.finalizingEdit(text)
        }
        try await LibraryScanner.write(caption: caption, to: id)
        if caption != nil { writtenInApp.insert(id) } else { writtenInApp.remove(id) }
        refresh(ids: [id])
    }

    /// 标签改名或合并：一次修改所有相关照片。
    func renameTags(_ olds: Set<String>, to new: String) async throws {
        var captions: [String: String?] = [:]
        for entry in entries.values where !olds.isDisjoint(with: entry.tags) {
            var caption = entry.caption
            for old in olds { caption = CaptionFormat.renamingTag(old, to: new, in: caption) }
            if caption != entry.caption { captions[entry.id] = caption }
        }
        try await LibraryScanner.write(captions)
        refresh(ids: Array(captions.keys))
    }

    func delete(id: String) async throws {
        try await LibraryScanner.delete(ids: [id])
        entries.removeValue(forKey: id)
        scheduleSave()
    }

    private func refresh(ids: [String]) {
        var copy = entries
        let fetched = LibraryScanner.fetchEntries(ids: ids)
        for id in ids where !fetched.contains(where: { $0.id == id }) { copy.removeValue(forKey: id) }
        for var entry in fetched {
            decorate(&entry)
            copy[entry.id] = entry
        }
        entries = copy
        scheduleSave()
        resolvePlaces()
    }

    func currentCaption(for id: String) -> String? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.extendedMetadata.caption
    }

    // MARK: 派生数据

    private func rebuildDerived() {
        let all = entries.values.sorted { $0.sortDate > $1.sortDate }
        diaries = all.filter(\.isDiary)
        externals = all.filter { !$0.isDiary }
        timeline = showExternal ? all : diaries

        var counts: [String: Int] = [:]
        for entry in diaries { for tag in entry.tags { counts[tag, default: 0] += 1 } }
        tagCounts = counts.map { ($0.key, $0.value) }.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    func entry(_ id: String) -> DiaryEntry? { entries[id] }

    var allTags: [String] { tagCounts.map(\.name) }

    /// 本月写了几篇（按说明里的写作日期）。
    var writtenThisMonth: Int {
        let today = DayStamp.today
        return diaries.reduce(0) { sum, e in
            sum + e.writingDays.filter { $0.year == today.year && $0.month == today.month }.count
        }
    }

    /// 本周（周日起）每一天是否写过日记。
    var weekWriting: [(day: DayStamp, wrote: Bool)] {
        let cal = Calendar.diary
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let written = Set(diaries.flatMap(\.writingDays))
        return (0..<7).map { offset in
            let day = DayStamp(cal.date(byAdding: .day, value: offset, to: start) ?? .now)
            return (day, written.contains(day))
        }
    }

    /// 那年今日：往年同月同日的照片日记。
    var onThisDay: [DiaryEntry] {
        let today = DayStamp.today
        return diaries.filter { e in
            let d = e.day
            return d.month == today.month && d.day == today.day && d.year < today.year
        }
    }

    func entries(tagged tag: String) -> [DiaryEntry] {
        diaries.filter { $0.tags.contains(tag) }
    }

    func entries(on day: DayStamp) -> [DiaryEntry] {
        timeline.filter { $0.day == day }
    }

    func search(text: String, tags: [String], range: ClosedRange<Date>?) -> [DiaryEntry] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        return timeline.filter { e in
            if !tags.allSatisfy(e.tags.contains) { return false }
            if let range, !range.contains(e.sortDate) { return false }
            if needle.isEmpty { return true }
            return e.caption.localizedStandardContains(needle)
                || (e.placeName?.localizedStandardContains(needle) ?? false)
        }
    }

    // MARK: 地点

    private func placeKey(_ e: DiaryEntry) -> String? {
        guard let lat = e.latitude, let lon = e.longitude else { return nil }
        return String(format: "%.2f,%.2f", lat, lon)
    }

    private var placeTask: Task<Void, Never>?

    private func resolvePlaces() {
        guard placeTask == nil else { return }
        placeTask = Task {
            while let next = diaries.first(where: { $0.placeName == nil && placeKey($0) != nil && !placeNamer.failed.contains($0.id) }),
                  let key = placeKey(next), let coordinate = next.coordinate {
                if let cached = placeCache[key] {
                    entries[next.id]?.placeName = cached
                    entries[next.id]?.timeZoneID = timeZoneCache[key]
                    continue
                }
                if let place = await placeNamer.place(for: coordinate), let name = place.name {
                    placeCache[key] = name
                    timeZoneCache[key] = place.timeZone
                    var copy = entries
                    for e in copy.values where placeKey(e) == key {
                        copy[e.id]?.placeName = name
                        copy[e.id]?.timeZoneID = place.timeZone
                    }
                    entries = copy
                } else {
                    placeNamer.failed.insert(next.id)
                }
                try? await Task.sleep(for: .milliseconds(600)) // 遵守地理编码的频率限制
            }
            placeTask = nil
            scheduleSave()
        }
    }

    // MARK: 持久化

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let snapshot = IndexSnapshot(entries: Array(entries.values), changeToken: changeToken,
                                         writtenInApp: writtenInApp, placeCache: placeCache,
                                         timeZoneCache: timeZoneCache)
            await IndexStore.save(snapshot)
        }
    }

    // MARK: 导出

    func markdownExport() -> String {
        let header = DateFormatter.zh("yyyy年M月d日 EEEE")
        var out = "# 照片日记\n\n"
        for e in diaries.reversed() {
            var title = header.string(from: e.displayDate)
            if let place = e.placeName { title += " · \(place)" }
            out += "## \(title)\n\n\(e.caption)\n\n"
        }
        return out
    }
}

/// PHPhotoLibraryChangeObserver：App 运行时收到变更就做一次增量同步。
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    let onChange: @MainActor @Sendable () -> Void

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in onChange() }
    }
}
