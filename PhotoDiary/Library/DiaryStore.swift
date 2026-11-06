import Foundation
import Observation
import Photos
import CoreLocation
import UIKit
import OSLog

/// App 的单一数据源：本地索引 + 照片库同步。
@Observable
final class DiaryStore {
    enum SyncState: Equatable {
        case idle
        case scanning(processed: Int, total: Int)
    }

    /// 外部依赖。默认值就是真实实现；测试换成假照片库、临时目录和固定时间。
    struct Dependencies {
        var library: any PhotoLibraryClient = PhotoKitLibrary()
        /// 索引数据库放在这个目录下的 Index/ 里。
        var indexDirectory: URL = .applicationSupportDirectory
        var placeNamer: any PlaceNaming = PlaceNamer()
        /// 说明过滤规则存在这里。
        var defaults: UserDefaults = .standard
        var now: () -> Date = { .now }
        /// 索引写盘前的防抖。
        var saveDelay: Duration = .seconds(1)
        /// 照片库变更通知的防抖。
        var changeDelay: Duration = .milliseconds(350)
        /// 两次反向地理编码之间的间隔（频率限制）。
        var geocodeInterval: Duration = .milliseconds(600)
        /// 地名用的语言（界面语言）。
        var placeLanguage: () -> String = { AppLanguage.current.rawValue }
    }

    private let deps: Dependencies
    private var library: any PhotoLibraryClient { deps.library }

    private(set) var authorization: PHAuthorizationStatus
    private(set) var syncState: SyncState = .idle
    private(set) var hasLoaded = false
    /// 至少完成过一次同步。之前列表为空不代表真的没有日记。
    private(set) var hasSynced = false

    /// 所有带说明的照片，按 localIdentifier 索引。
    private(set) var entries: [String: DiaryEntry] = [:] {
        didSet {
            trackChanges(from: oldValue)
            rebuildDerived()
        }
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
    /// 本周写过的日记（按说明里的写作日期），给本周回顾用。
    private(set) var weekEntries: [DiaryEntry] = []
    /// 本月写了几篇（按说明里的写作日期）。
    private(set) var writtenThisMonth = 0
    private var byDay: [DayStamp: [DiaryEntry]] = [:]
    private var byTag: [String: [DiaryEntry]] = [:]
    /// 被设置里的说明过滤规则隐藏的照片。
    private var hiddenIDs: Set<String> = []
    /// 派生数据是按哪一天算的；跨天回到前台时重算“那年今日”和本周。
    private var derivedDay: DayStamp

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

    private var changeToken: Data? {
        didSet { if changeToken != oldValue { tokenDirty = true } }
    }
    /// changeToken 是在哪种照片权限下拿到的。权限变了（有限 → 完整），之前看不到的照片不会出现在增量里，要全库重读。
    private var tokenAccess: PHAuthorizationStatus? {
        didSet { if tokenAccess != oldValue { tokenDirty = true } }
    }
    private var writtenInApp: Set<String> = []
    private var placeCache: [String: String] = [:]
    private var timeZoneCache: [String: String] = [:]
    private var observer: AnyObject?
    private var syncTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pendingIncremental = false
    /// 本 App 写过的照片 → 写入序号。同步是先读、过一会儿才交回主线程的：
    /// 读的时候还没写、交回来时已经写过的照片，同步的结果是旧的，要按照片库现在的内容重读。
    private var localWrites: [String: Int] = [:]
    private var writeSequence = 0
    /// 反向地理编码失败过的照片，本次运行不再重试。
    private var placeFailures = Set<String>()
    /// 界面语言变了就加一，旧语言那一轮查到的地名不再写回。
    private var placeGeneration = 0
    /// 已有地名是用哪种语言查的；全部查完才写入。
    static let placeLanguageKey = "placeLanguage"

    private var database: IndexDatabase?
    private var preparing: Task<(IndexDatabase, IndexDatabase.Loaded), Never>?
    // 自上次保存以来变化的行。保存时只写这些。
    private var dirtyIDs = Set<String>()
    private var removedIDs = Set<String>()
    private var dirtyPlaces: [String: (name: String, timeZone: String?)] = [:]
    private var tokenDirty = false
    /// 最近一次保存写了多少行（日志和测试用）。
    private(set) var lastSaveStats: IndexDatabase.Stats?

    init(_ dependencies: Dependencies = Dependencies()) {
        deps = dependencies
        authorization = dependencies.library.authorizationStatus()
        derivedDay = DayStamp(dependencies.now())
    }

    private var today: DayStamp { DayStamp(deps.now()) }

    var isLimited: Bool { authorization == .limited }

    /// 第一次全库读取进行中（没有本地索引时）。之后的启动走增量同步，不算。
    var isFirstScan: Bool {
        guard !hasSynced, case .scanning = syncState else { return false }
        return true
    }
    var canRead: Bool { authorization == .authorized || authorization == .limited }

    // MARK: 启动

    /// App 一启动就在后台打开并读入索引，和第一帧界面的绘制同时进行；start() 直接接着用。
    /// 数据库第一次查询要几百毫秒建立连接，不提前开始就会全算在开屏等待里。
    func prepare() {
        guard preparing == nil else { return }
        let directory = deps.indexDirectory
        // detached：不等主线程有空才开始。
        preparing = Task.detached(priority: .userInitiated) {
            let database = await IndexDatabase.open(directory: directory)
            return (database, await database.load())
        }
    }

    func start() async {
        authorization = library.authorizationStatus()
        Log.app.notice("启动，照片权限 \(self.authorization.rawValue, privacy: .public)")
        guard canRead else { return }
        if !hasLoaded {
            // 打开、读取都在数据库自己的线程上，一次回到主线程。
            prepare()
            guard let (database, loaded) = await preparing?.value else { return }
            self.database = database
            placeCache = loaded.places.names
            timeZoneCache = loaded.places.timeZones
            writtenInApp = Set(loaded.entries.lazy.filter(\.writtenInApp).map(\.id))
            changeToken = loaded.changeToken
            tokenAccess = loaded.tokenAccess.flatMap(PHAuthorizationStatus.init(rawValue:))
            entries = Dictionary(loaded.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            // 刚从库里读出来的不算变化。
            clearDirty()
            placeLanguageChanged()
        }
        hasLoaded = true
        registerObserver()
        sync()
    }

    func requestAccess() async {
        authorization = await library.requestAuthorization()
        await start()
    }

    func refreshAuthorization() {
        if today != derivedDay { rebuildDerived() }
        let status = library.authorizationStatus()
        guard status != authorization else { return }
        Log.app.notice("照片权限变为 \(status.rawValue, privacy: .public)")
        authorization = status
        if canRead { Task { await start() } }
    }

    private func registerObserver() {
        guard observer == nil else { return }
        observer = library.observeChanges { [weak self] in self?.scheduleIncremental() }
    }

    // MARK: 同步

    /// 有 token 走增量，否则（或 token 失效）全库重建。同一时刻只有一个同步任务；
    /// 进行中再调用只记下“结束后再增量一次”。
    func sync() {
        guard syncTask == nil else { pendingIncremental = true; return }
        let started = writeSequence
        syncTask = Task {
            if let token = changeToken, tokenAccess == authorization {
                Log.sync.debug("增量同步开始")
                let state = Log.signposter.beginInterval("sync.incremental")
                do {
                    let result = try await library.incremental(since: token)
                    Log.signposter.endInterval("sync.incremental", state)
                    guard !Task.isCancelled else { return }
                    Log.sync.info("增量同步：更新 \(result.updated.count)，移除 \(result.removed.count)")
                    apply(result, writesSince: started)
                } catch {
                    Log.signposter.endInterval("sync.incremental", state)
                    guard !Task.isCancelled else { return }
                    Log.sync.notice("增量同步失败，改为全量读取：\(error, privacy: .public)")
                    await fullScan()
                }
            } else {
                if changeToken != nil {
                    Log.sync.notice("照片权限变了（\(self.tokenAccess?.rawValue ?? -1, privacy: .public) → \(self.authorization.rawValue, privacy: .public)），全量读取")
                }
                await fullScan()
            }
            // 被 rebuildIndex 取消的任务已经被新任务取代，不能再动任何状态（包括 syncTask）。
            guard !Task.isCancelled else { return }
            syncTask = nil
            hasSynced = true
            // 这次同步开始前的写入已经不会再被旧结果盖掉了。
            localWrites = localWrites.filter { $0.value > started }
            if pendingIncremental {
                pendingIncremental = false
                sync()
            }
        }
    }

    func rebuildIndex() {
        Log.sync.notice("手动重建索引")
        syncTask?.cancel()
        syncTask = nil
        changeToken = nil
        sync()
    }

    private var incrementalDebounce: Task<Void, Never>?

    private func scheduleIncremental() {
        incrementalDebounce?.cancel()
        incrementalDebounce = Task {
            try? await Task.sleep(for: deps.changeDelay)
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    private func fullScan() async {
        let state = Log.signposter.beginInterval("sync.fullScan")
        defer { Log.signposter.endInterval("sync.fullScan", state) }
        let access = authorization
        let started = writeSequence
        var fresh: [String: DiaryEntry] = [:]
        for await event in library.fullScan() {
            switch event {
            case .started(let total):
                Log.sync.info("全量读取开始：\(total) 张照片")
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
                // 建好的部分先可用。读取开始后本 App 写过的照片不拿旧结果盖掉。
                let written = writes(since: started)
                decorated.removeAll { written.contains($0.0) }
                if !decorated.isEmpty {
                    entries.merge(decorated, uniquingKeysWith: { _, b in b })
                }
            case .finished(let token):
                if let token {
                    Log.sync.info("全量读取完成：\(fresh.count) 篇日记")
                    reread(writes(since: started), into: &fresh)
                    entries = fresh
                    changeToken = token
                    tokenAccess = access
                }
            }
        }
        // 被取消：读到一半的结果不保存、不改写关键词，进度由接手的新任务更新。
        guard !Task.isCancelled else {
            Log.sync.notice("全量读取被取消，已读到 \(fresh.count) 篇")
            return
        }
        syncState = .idle
        scheduleSave()
        afterSync(ids: Array(entries.keys))
    }

    private func apply(_ result: LibraryScanner.IncrementalResult, writesSince started: Int) {
        var copy = entries
        for id in result.removed { copy.removeValue(forKey: id) }
        for var entry in result.updated {
            decorate(&entry)
            copy[entry.id] = entry
        }
        reread(writes(since: started), into: &copy)
        // 没有变化时不重写索引（每次启动都会走一遍增量）；地名补查照常进行。
        let changed = copy != entries || result.token != changeToken
        if copy != entries { entries = copy }
        changeToken = result.token
        if changed { scheduleSave() }
        afterSync(ids: result.updated.map(\.id))
    }

    /// 同步开始之后本 App 写过的照片。
    private func writes(since started: Int) -> Set<String> {
        Set(localWrites.compactMap { $0.value > started ? $0.key : nil })
    }

    /// 同步读到的可能是写入之前的样子：这些照片按照片库现在的内容重读（不是简单跳过，免得漏掉同一时间在别处的修改）。
    private func reread(_ ids: Set<String>, into copy: inout [String: DiaryEntry]) {
        guard !ids.isEmpty else { return }
        let fetched = library.fetchEntries(ids: Array(ids))
        for id in ids { copy.removeValue(forKey: id) }
        for var entry in fetched {
            decorate(&entry)
            copy[entry.id] = entry
        }
        Log.sync.debug("同步期间本 App 写过 \(ids.count) 张，按现在的照片库重读")
    }

    private func noteLocalWrite(_ ids: some Sequence<String>) {
        writeSequence += 1
        for id in ids { localWrites[id] = writeSequence }
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
            Log.library.info("按标签改写关键词：\(mismatched.count) 张")
            Task { [library] in
                do {
                    try await library.reconcileKeywords(ids: mismatched)
                } catch {
                    Log.library.error("改写关键词失败：\(error, privacy: .public)")
                }
            }
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
            caption = CaptionFormat.appending(text, to: existing, on: today,
                                              hidden: CaptionFilter.matcher(defaults: deps.defaults))
        case .edit:
            caption = CaptionFormat.finalizingEdit(text, on: today)
        }
        do {
            try await library.write([id: caption])
        } catch {
            Log.library.error("写入说明失败（\(String(describing: mode), privacy: .public)）：\(error, privacy: .public)")
            throw error
        }
        Log.library.info("写入说明（\(String(describing: mode), privacy: .public)）\(id)")
        if caption != nil { writtenInApp.insert(id) } else { writtenInApp.remove(id) }
        refresh(ids: [id])
    }

    /// 给一篇日记补一个标签（采纳建议）。写在最后一段末尾，关键词随后照常同步。
    func addTag(_ tag: String, to id: String) async throws {
        guard let existing = entries[id]?.caption ?? currentCaption(for: id) else { return }
        let caption = CaptionFormat.addingTag(tag, to: existing)
        guard caption != existing else { return }
        do {
            try await library.write([id: caption])
        } catch {
            Log.library.error("补标签失败：\(error, privacy: .public)")
            throw error
        }
        Log.library.info("补标签 #\(tag, privacy: .public)# \(id)")
        writtenInApp.insert(id)
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
        do {
            try await library.write(captions)
        } catch {
            Log.library.error("标签改名失败（\(captions.count) 张）：\(error, privacy: .public)")
            throw error
        }
        Log.library.info("标签改名：\(olds.count) 个标签，\(captions.count) 张照片")
        refresh(ids: Array(captions.keys))
    }

    func delete(id: String) async throws {
        do {
            try await library.delete(ids: [id])
        } catch {
            Log.library.error("删除照片失败：\(error, privacy: .public)")
            throw error
        }
        Log.library.info("删除照片 \(id)")
        noteLocalWrite([id])
        entries.removeValue(forKey: id)
        scheduleSave()
    }

    private func refresh(ids: [String]) {
        noteLocalWrite(ids)
        var copy = entries
        let fetched = library.fetchEntries(ids: ids)
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
        library.currentCaption(for: id)
    }

    // MARK: 派生数据

    private func rebuildDerived() {
        let signpost = Log.signposter.beginInterval("store.rebuildDerived")
        defer { Log.signposter.endInterval("store.rebuildDerived", signpost) }
        let now = deps.now()
        let today = DayStamp(now)
        derivedDay = today
        let hidden = CaptionFilter.matcher(defaults: deps.defaults)
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

        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let week = (0..<7).map { offset in
            let day = DayStamp(cal.date(byAdding: .day, value: offset, to: weekStart) ?? now)
            return WeekDay(day: day, wrote: writing.contains(day))
        }
        let weekDays = Set(week.map(\.day))
        let writtenThisWeek = visible.reduce(0) { $0 + $1.writingDays.filter(weekDays.contains).count }
        let weekEntries = visible.filter { $0.writingDays.contains(where: weekDays.contains) }

        let thisMonth = cal.dateInterval(of: .month, for: now)?.start ?? now
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
        update(\.weekEntries, weekEntries)
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

    /// 设置里改了一周起始日后，本周写作要按新的一周重算。
    func weekStartChanged() { rebuildDerived() }

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

    /// 每条隐藏规则各隐藏了几张照片，按规则的规范化文字索引。
    func hiddenCaptionCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for id in hiddenIDs {
            guard let caption = entries[id]?.caption else { continue }
            counts[CaptionFilter.normalized(caption), default: 0] += 1
        }
        return counts
    }

    var allTags: [String] { tagCounts.map(\.name) }

    func entries(tagged tag: String) -> [DiaryEntry] { byTag[tag] ?? [] }

    func entries(on day: DayStamp) -> [DiaryEntry] { byDay[day] ?? [] }

    func entries(at place: String) -> [DiaryEntry] { diaries.filter { $0.placeName == place } }

    func search(text: String, tags: [String], range: ClosedRange<Date>?) -> [DiaryEntry] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        return timeline.filter { e in
            if !tags.allSatisfy(e.tags.contains) { return false }
            if let range, !range.contains(e.sortDate) { return false }
            if needle.isEmpty { return true }
            return Self.matches(e.caption, needle) || e.placeName.map { Self.matches($0, needle) } == true
        }
    }

    /// 模型拆出来的条件：关键词任一命中即可，标签都要有，地点、日期照旧。
    func search(_ filter: SearchFilter) -> [DiaryEntry] {
        let range = filter.dateRange
        return timeline.filter { e in
            if !filter.tags.allSatisfy(e.tags.contains) { return false }
            if let place = filter.place, e.placeName != place { return false }
            if let range, !range.contains(e.sortDate) { return false }
            if filter.keywords.isEmpty { return true }
            return filter.keywords.contains { word in
                Self.matches(e.caption, word) || e.placeName.map { Self.matches($0, word) } == true
            }
        }
    }

    /// 不分大小写、重音和全角半角（输入法打出的 ＫＡＭＡＫＵＲＡ 也能搜到 Kamakura）。
    private static func matches(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) != nil
    }

    // MARK: 地点

    private func placeKey(_ e: DiaryEntry) -> String? {
        guard let lat = e.latitude, let lon = e.longitude else { return nil }
        return String(format: "%.2f,%.2f", lat, lon)
    }

    private var placeTask: Task<Void, Never>?

    /// 地名跟着界面语言：语言和查地名时用的不一样时，丢掉旧地名，按新语言重新查（时区不变）。
    func placeLanguageChanged() {
        let language = deps.placeLanguage()
        guard deps.defaults.string(forKey: Self.placeLanguageKey) != language,
              !placeCache.isEmpty || entries.values.contains(where: { $0.placeName != nil }) else { return }
        Log.places.info("地名改用 \(language, privacy: .public) 重新查询")
        placeGeneration += 1
        placeTask?.cancel()
        placeTask = nil
        placeCache.removeAll()
        placeFailures.removeAll()
        var copy = entries
        for id in copy.keys { copy[id]?.placeName = nil }
        entries = copy
        resolvePlaces()
    }

    private func resolvePlaces() {
        guard placeTask == nil else { return }
        let generation = placeGeneration
        let language = deps.placeLanguage()
        placeTask = Task {
            // 一次列出还缺地名的坐标；同一坐标只查一次。
            var pending: [String: CLLocationCoordinate2D] = [:]
            var order: [String] = []
            for e in diaries where e.placeName == nil && !placeFailures.contains(e.id) {
                guard let key = placeKey(e), let coordinate = e.coordinate, pending[key] == nil else { continue }
                pending[key] = coordinate
                order.append(key)
            }
            // 查到的地名攒一批再写回：每写一次 entries，所有界面都会重算。
            var resolved: [String: (name: String, timeZone: String?)] = [:]
            var lastFlush = ContinuousClock.now
            var looked = 0, failures = 0, filled = 0
            if !order.isEmpty { Log.places.info("待解析地名：\(order.count) 个坐标") }
            for key in order {
                guard !Task.isCancelled else { break }
                if let cached = placeCache[key] {
                    filled += 1
                    resolved[key] = (cached, timeZoneCache[key])
                } else if let coordinate = pending[key], let place = await deps.placeNamer.place(for: coordinate), let name = place.name {
                    guard generation == placeGeneration else { break }
                    looked += 1
                    filled += 1
                    placeCache[key] = name
                    timeZoneCache[key] = place.timeZone
                    dirtyPlaces[key] = (name, place.timeZone)
                    resolved[key] = (name, place.timeZone)
                    try? await Task.sleep(for: deps.geocodeInterval) // 遵守地理编码的频率限制
                } else {
                    looked += 1
                    failures += 1
                    Log.places.debug("地名解析失败：\(key)")
                    for e in diaries where placeKey(e) == key { placeFailures.insert(e.id) }
                }
                if !resolved.isEmpty, ContinuousClock.now - lastFlush > .seconds(3) {
                    applyPlaces(resolved)
                    resolved.removeAll()
                    lastFlush = .now
                }
            }
            guard generation == placeGeneration else { return }
            applyPlaces(resolved)
            if looked > 0 { Log.places.info("地名解析结束：查询 \(looked) 次，失败 \(failures) 次") }
            if !Task.isCancelled { deps.defaults.set(language, forKey: Self.placeLanguageKey) }
            placeTask = nil
            // 有条目补上了地名才需要保存。
            if filled > 0 { scheduleSave() }
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
            try? await Task.sleep(for: deps.saveDelay)
            guard !Task.isCancelled else { return }
            await persist()
        }
    }

    /// 不等防抖立即保存。进入后台时调用：之后随时可能被系统结束。
    func saveNow() async {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = nil
        await persist()
    }

    /// 只把上次保存以来变化的行写进数据库。
    private func persist() async {
        guard let database, hasPendingChanges else { return }
        var changes = IndexDatabase.Changes(changeToken: changeToken, tokenAccess: tokenAccess?.rawValue, places: dirtyPlaces)
        changes.upserts = dirtyIDs.compactMap { entries[$0] }
        changes.deletions = removedIDs
        clearDirty()
        do {
            lastSaveStats = try await database.apply(changes)
        } catch {
            Log.index.error("保存索引失败，下次再试：\(error, privacy: .public)")
            // 没写进去的变化放回去（期间又有新变化的以新的为准）。
            for entry in changes.upserts where !removedIDs.contains(entry.id) { dirtyIDs.insert(entry.id) }
            removedIDs.formUnion(changes.deletions.subtracting(dirtyIDs))
            dirtyPlaces.merge(changes.places) { new, _ in new }
            tokenDirty = true
        }
    }

    private var hasPendingChanges: Bool {
        !dirtyIDs.isEmpty || !removedIDs.isEmpty || !dirtyPlaces.isEmpty || tokenDirty
    }

    private func clearDirty() {
        dirtyIDs.removeAll()
        removedIDs.removeAll()
        dirtyPlaces.removeAll()
        tokenDirty = false
    }

    /// entries 每次赋值后找出变了的行：新增和修改的记进 dirtyIDs，没了的记进 removedIDs。
    private func trackChanges(from old: [String: DiaryEntry]) {
        for (id, entry) in entries where old[id] != entry {
            dirtyIDs.insert(id)
            removedIDs.remove(id)
        }
        for id in old.keys where entries[id] == nil {
            removedIDs.insert(id)
            dirtyIDs.remove(id)
        }
    }

    // MARK: 导出

    func markdownExport() -> String {
        var out = "# \(String(localized: "照片日记", bundle: .app, locale: .app))\n\n"
        for e in diaries.reversed() {
            var title = DiaryDates.fullWithWeekday(e.displayDate)
            if let place = e.placeName { title += " · \(place)" }
            out += "## \(title)\n\n\(e.caption)\n\n"
        }
        return out
    }
}
