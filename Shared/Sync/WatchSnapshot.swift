import Foundation

// MARK: iPhone ⇄ Apple Watch 之间传的数据
//
// Watch 上没有照片库，看到的一切都来自 iPhone；表上口述的感想发回 iPhone，由 iPhone 写进照片说明。
//
// 传输方式（都是 WatchConnectivity）：
// - 快照（不含图）走 applicationContext：总是保留最新一份，表不在旁边时下次打开也能拿到。
// - 缩略图由表按需拉取：表看缺哪些图，用 sendMessageData 一张一张问 iPhone 要，存在表的本地缓存里。
// - 表上口述的一段：可达时 sendMessageData 直接送到并等回执；不可达时 transferUserInfo 排队。
// - 回执（写进去了 / 写不进去）：表在旁边时直接送到，不在时走 transferUserInfo 排队。

/// iPhone → Watch：最近的日记、那年今日、本周写作、还没写的照片。
nonisolated struct WatchSnapshot: Codable, Sendable, Equatable {
    static let version = 3
    static let maxEntries = 40
    static let maxUnwritten = 6
    /// 那年今日最多带几篇（每一天）。
    static let maxOnThisDay = 8
    /// 往后几天的那年今日也带上：表上过了零点、iPhone 还没发新快照时照样对。
    static let daysAhead = 6
    /// 编码后的上限。applicationContext 太大会发不出去，表就再也不更新了。
    static let maxBytes = 48 * 1024
    /// 缩略图的边长（像素）。列表里 44pt@2x，详情里铺满 200pt 左右的宽度。
    static let thumbnailPixels: CGFloat = 256

    var version = WatchSnapshot.version
    var generated: Date
    /// iPhone 上的“今天”。表上的日子和它不一样（过了零点）时，那年今日改用 `ahead` 里的，本周按表上的日子重排。
    var today: DayStamp
    /// 最近的日记，按照片日期倒序。
    var entries: [WatchEntry]
    /// 那年今日的条目（在 entries 里的 id；不在最近 40 篇里的也会带上）。
    var onThisDay: [String]
    /// 往后几天的那年今日（id 也都在 entries 里）。
    var ahead: [WatchMemories]
    var week: [WatchWeekDay]
    var writtenThisWeek: Int
    /// 最近还没写日记的照片，表上可以直接口述一段。
    var unwritten: [WatchPhoto]
    /// iPhone 上设置的一周起始日（1 周日、2 周一）。
    var firstWeekday: Int?

    init(generated: Date, today: DayStamp, entries: [WatchEntry] = [], onThisDay: [String] = [], ahead: [WatchMemories] = [],
         week: [WatchWeekDay] = [], writtenThisWeek: Int = 0, unwritten: [WatchPhoto] = [], firstWeekday: Int? = nil) {
        self.generated = generated
        self.today = today
        self.entries = entries
        self.onThisDay = onThisDay
        self.ahead = ahead
        self.week = week
        self.writtenThisWeek = writtenThisWeek
        self.unwritten = unwritten
        self.firstWeekday = firstWeekday
    }

    /// 某一天的那年今日：快照的今天用 onThisDay，之后几天用 ahead；更远的不知道。
    func onThisDay(on day: DayStamp) -> [String] {
        if day == today { return onThisDay }
        return ahead.first { $0.day == day }?.ids ?? []
    }

    /// 某一天所在那一周的写作情况：还是快照里那一周就照用，进了新的一周就全是没写。
    func week(on day: DayStamp, calendar: Calendar = .diary) -> (days: [WatchWeekDay], written: Int) {
        guard !week.contains(where: { $0.day == day }) else { return (week, writtenThisWeek) }
        let start = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start ?? day.date
        let days = (0..<7).map { offset in
            WatchWeekDay(day: DayStamp(calendar.date(byAdding: .day, value: offset, to: start) ?? start), wrote: false)
        }
        return (days, 0)
    }

    static let fileName = "watch-snapshot.json"

    /// 快照里所有需要缩略图的照片。
    var imageIDs: [String] { entries.map(\.id) + unwritten.map(\.id) }
}

/// 一篇日记在表上需要的信息。说明原文照传，表上用同一套 CaptionFormat 解析。
nonisolated struct WatchEntry: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var caption: String
    var day: DayStamp
    var placeName: String?
    var mediaKind: MediaKind

    /// 表上用 DiaryEntry 的解析结果（标题、预览、段落、标签），和 iPhone 完全一致。
    var entry: DiaryEntry {
        DiaryEntry(id: id, caption: caption, keywords: [], creationDate: day.date, latitude: nil, longitude: nil,
                   mediaKind: mediaKind, isCloudShared: false, pixelWidth: 0, pixelHeight: 0, placeName: placeName)
    }
}

nonisolated struct WatchPhoto: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var day: DayStamp?
}

nonisolated struct WatchMemories: Codable, Sendable, Equatable {
    var day: DayStamp
    var ids: [String]
}

nonisolated struct WatchWeekDay: Codable, Sendable, Equatable {
    var day: DayStamp
    var wrote: Bool
}

/// Watch → iPhone：在表上口述的一段，由 iPhone 追加进照片说明。
nonisolated struct WatchWrite: Codable, Sendable, Hashable, Identifiable {
    enum Mode: String, Codable, Sendable {
        case new, append
    }

    var id: UUID = UUID()
    var assetID: String
    var text: String
    var mode: Mode

    init(assetID: String, text: String, mode: Mode) {
        self.assetID = assetID
        self.text = text
        self.mode = mode
    }
}

/// 两边来回的消息，统一 JSON 编码后用 sendMessageData / transferUserInfo 传。
nonisolated enum WatchMessage: Codable, Sendable, Equatable {
    /// Watch 请求 iPhone 重发快照。
    case refresh
    /// Watch 向 iPhone 要这些照片的缩略图。
    case thumbnails(ids: [String])
    /// iPhone 回复：id → JPEG。
    case images([String: Data])
    /// Watch 发来一段口述。
    case write(WatchWrite)
    /// iPhone 告诉 Watch 这一段已写进照片说明。
    case wrote(UUID)
    /// iPhone 告诉 Watch 这一段写不进去（照片删了、改不了说明），字留在表上。
    case failed(UUID)
    /// 收到了，没别的要说。
    case ok

    static let userInfoKey = "message"
    /// applicationContext 里快照的键。
    static let snapshotKey = "snapshot"

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    init?(data: Data) {
        guard let message = try? JSONDecoder().decode(WatchMessage.self, from: data) else { return nil }
        self = message
    }

    var userInfo: [String: Any] { [Self.userInfoKey: data] }

    init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.userInfoKey] as? Data else { return nil }
        self.init(data: data)
    }
}
