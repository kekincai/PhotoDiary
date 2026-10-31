import Foundation
import Observation
import Photos
import CoreLocation
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
    /// 至少完成过一次同步。之前列表为空不代表真的没有日记。
    private(set) var hasSynced = false

    /// 所有带说明的照片，按 localIdentifier 索引。
    private(set) var entries: [String: DiaryEntry] = [:] {
        didSet { rebuildDerived() }
    }

    /// 所有写了说明的照片，按照片日期倒序。
    private(set) var diaries: [DiaryEntry] = []
    /// 标签及数量，按数量排序。
    private(set) var tagCounts: [TagCount] = []

    // 下面这些都由 diaries 派生，在数据变化时算一次，界面直接读，不在每次刷新时遍历全部日记。
    /// 按月分组（列表的月份标题）。
    private(set) var months: [MonthGroup] = []
    /// 日历要显示的月份：写过日记的月份加上本月，倒序。
    private(set) var calendarMonths: [Date] = []
    /// 写过日记的地点，按篇数排列；封面是最近一篇。
    private(set) var places: [PlaceGroup] = []
    /// 那年今日：往年同月同日的照片日记。
    private(set) var onThisDay: [DiaryEntry] = []
    /// 本周（周日起）每一天是否写过日记。
    private(set) var weekWriting: [WeekDay] = []
    /// 本周写了几篇（按说明里的写作日期）。
    private(set) var writtenThisWeek = 0
    /// 本月写了几篇（按说明里的写作日期）。
    private(set) var writtenThisMonth = 0
    private var byDay: [DayStamp: [DiaryEntry]] = [:]
    private var byTag: [String: [DiaryEntry]] = [:]
    /// 被设置里的说明过滤规则隐藏的照片。
    private var hiddenIDs: Set<String> = []
    /// 派生数据是按哪一天算的；跨天回到前台时重算“那年今日”和本周。
    private var derivedDay = DayStamp.today

    struct TagCount: Hashable {
        var name: String
        var count: Int
    }

    struct MonthGroup: Hashable, Identifiable {
        var id: String
        var start: Date
        var entries: [DiaryEntry]
    }

    struct PlaceGroup: Hashable, Identifiable {
        var name: String
        var count: Int
        var cover: String
        var id: String { name }
    }

    struct WeekDay: Hashable {
        var day: DayStamp
        var wrote: Bool
    }

    /// 列表、日历、照片、地图里显示的条目。
    var timeline: [DiaryEntry] { diaries }

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
        if DayStamp.today != derivedDay { rebuildDerived() }
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
            hasSynced = true
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
        // 关键词由说明里的标签生成。说明里没有标签、也没在本 App 写过的照片不动，
        // 以免抹掉 Lightroom 等导入时自带的关键词。
        let mismatched = ids.compactMap { entries[$0] }.filter {
            (!$0.tags.isEmpty || $0.writtenInApp) && Set($0.keywords) != Set($0.tags)
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
        for entry in diaries where !olds.isDisjoint(with: entry.tags) {
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
        let today = DayStamp.today
        derivedDay = today
        let hidden = CaptionFilter.matcher()
        var hiddenIDs = Set<String>()
        var visible: [DiaryEntry] = []
        visible.reserveCapacity(entries.count)
        for entry in entries.values {
            if hidden(entry.caption) { hiddenIDs.insert(entry.id) } else { visible.append(entry) }
        }
        visible.sort { $0.sortDate > $1.sortDate }

        var counts: [String: Int] = [:]
        var byTag: [String: [DiaryEntry]] = [:]
        var byDay: [DayStamp: [DiaryEntry]] = [:]
        var months: [MonthGroup] = []
        var placeCounts: [String: (count: Int, cover: String)] = [:]
        var placeOrder: [String] = []
        var writing = Set<DayStamp>()
        var onThisDay: [DiaryEntry] = []
        var writtenThisMonth = 0
        let cal = Calendar.diary

        for entry in visible {
            for tag in entry.tags {
                counts[tag, default: 0] += 1
                byTag[tag, default: []].append(entry)
            }
            let d = entry.day
            byDay[d, default: []].append(entry)
            let key = "\(d.year)-\(d.month)"
            if months.last?.id == key {
                months[months.count - 1].entries.append(entry)
            } else {
                let start = cal.date(from: DateComponents(year: d.year, month: d.month, day: 1)) ?? entry.displayDate
                months.append(MonthGroup(id: key, start: start, entries: [entry]))
            }
            if let place = entry.placeName {
                if let p = placeCounts[place] { placeCounts[place] = (p.count + 1, p.cover) }
                else { placeCounts[place] = (1, entry.id); placeOrder.append(place) }
            }
            if d.month == today.month && d.day == today.day && d.year < today.year { onThisDay.append(entry) }
            for w in entry.writingDays {
                writing.insert(w)
                if w.year == today.year && w.month == today.month { writtenThisMonth += 1 }
            }
        }

        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let week = (0..<7).map { offset in
            let day = DayStamp(cal.date(byAdding: .day, value: offset, to: weekStart) ?? .now)
            return WeekDay(day: day, wrote: writing.contains(day))
        }
        let weekDays = Set(week.map(\.day))
        let writtenThisWeek = visible.reduce(0) { $0 + $1.writingDays.filter(weekDays.contains).count }

        let thisMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        var calendarMonths = months.map(\.start)
        if !calendarMonths.contains(thisMonth) { calendarMonths.append(thisMonth) }
        calendarMonths.sort(by: >)

        // 只在真的变了时才赋值：Observation 每次赋值都会让读它的界面重新计算。
        func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<DiaryStore, T>, _ value: T) {
            if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
        }
        update(\.diaries, visible)
        update(\.tagCounts, counts.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) })
        update(\.byTag, byTag)
        update(\.byDay, byDay)
        update(\.months, months)
        update(\.calendarMonths, calendarMonths)
        update(\.places, placeOrder.map { PlaceGroup(name: $0, count: placeCounts[$0]!.count, cover: placeCounts[$0]!.cover) }
            .sorted { $0.count > $1.count })
        update(\.onThisDay, onThisDay)
        update(\.weekWriting, week)
        update(\.writtenThisWeek, writtenThisWeek)
        update(\.writtenThisMonth, writtenThisMonth)
        update(\.hiddenIDs, hiddenIDs)
    }

    /// 被设置里的说明过滤规则隐藏的照片不算日记。
    func entry(_ id: String) -> DiaryEntry? {
        guard let entry = entries[id], !hiddenIDs.contains(id) else { return nil }
        return entry
    }

    /// 设置里改了说明过滤规则后，重新整理列表。
    func captionFilterChanged() { rebuildDerived() }

    /// 索引里出现多次的短说明（不像日记的那种），给设置里的过滤规则做建议。
    func frequentShortCaptions(limit: Int = 8) -> [(caption: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries.values where !hiddenIDs.contains(entry.id) {
            let text = entry.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 12, !text.contains("\n"), entry.writingDays.isEmpty else { continue }
            counts[text, default: 0] += 1
        }
        return counts.filter { $0.value >= 2 }
            .map { (caption: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.caption) > ($1.count, $0.caption) }
            .prefix(limit)
            .map { $0 }
    }

    var allTags: [String] { tagCounts.map(\.name) }

    func entries(tagged tag: String) -> [DiaryEntry] { byTag[tag] ?? [] }

    func entries(on day: DayStamp) -> [DiaryEntry] { byDay[day] ?? [] }

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
            // 一次列出还缺地名的坐标；同一坐标只查一次。
            var pending: [String: CLLocationCoordinate2D] = [:]
            var order: [String] = []
            for e in diaries where e.placeName == nil && !placeNamer.failed.contains(e.id) {
                guard let key = placeKey(e), let coordinate = e.coordinate, pending[key] == nil else { continue }
                pending[key] = coordinate
                order.append(key)
            }
            // 查到的地名攒一批再写回：每写一次 entries，所有界面都会重算。
            var resolved: [String: (name: String, timeZone: String?)] = [:]
            var lastFlush = ContinuousClock.now
            for key in order {
                guard !Task.isCancelled else { break }
                if let cached = placeCache[key] {
                    resolved[key] = (cached, timeZoneCache[key])
                } else if let coordinate = pending[key], let place = await placeNamer.place(for: coordinate), let name = place.name {
                    placeCache[key] = name
                    timeZoneCache[key] = place.timeZone
                    resolved[key] = (name, place.timeZone)
                    try? await Task.sleep(for: .milliseconds(600)) // 遵守地理编码的频率限制
                } else {
                    for e in diaries where placeKey(e) == key { placeNamer.failed.insert(e.id) }
                }
                if !resolved.isEmpty, ContinuousClock.now - lastFlush > .seconds(3) {
                    applyPlaces(resolved)
                    resolved.removeAll()
                    lastFlush = .now
                }
            }
            applyPlaces(resolved)
            placeTask = nil
            scheduleSave()
        }
    }

    private func applyPlaces(_ resolved: [String: (name: String, timeZone: String?)]) {
        guard !resolved.isEmpty else { return }
        var copy = entries
        for e in copy.values where e.placeName == nil {
            guard let key = placeKey(e), let place = resolved[key] else { continue }
            copy[e.id]?.placeName = place.name
            copy[e.id]?.timeZoneID = place.timeZone
        }
        entries = copy
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
