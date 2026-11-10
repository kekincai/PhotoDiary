import Foundation
import CoreLocation

nonisolated enum MediaKind: String, Codable, Sendable {
    case photo, livePhoto, video
}

/// 说明解析后给界面用的结果，只由说明决定。和条目一起存进索引数据库，启动时直接读出来，不必逐条重新解析。
nonisolated struct CaptionDisplay: Hashable, Codable, Sendable {
    /// 解析规则的版本。CaptionFormat 的解析或显示规则改了就加一，数据库里旧的解析结果会在启动时重算。
    static let version = 1

    var segments: [DiarySegment] = []
    var tags: [String] = []
    /// 去掉行尾标签后的各段正文。
    var displaySegments: [DiarySegment] = []
    var title = ""
    /// 列表预览：只有一段时显示首句之后的内容；多段时显示最新追加的那段。
    var preview = ""

    init() {}

    init(caption: String) {
        let parsed = CaptionFormat.parse(caption)
        segments = parsed.segments
        tags = parsed.tags
        displaySegments = segments
            .map { DiarySegment(text: CaptionFormat.strippingTrailingTags($0.text), date: $0.date) }
            .filter { !$0.text.isEmpty || $0.date != nil }
        let first = CaptionFormat.splitTitle(displaySegments.first?.text ?? "")
        title = first.title
        preview = displaySegments.count > 1 ? (displaySegments.last?.text ?? "") : first.rest
    }
}

/// 本地索引里的一条记录：一张带说明的照片。可以随时从照片库完整重建。
///
/// 列表、日历每次刷新都会读日期、标题、预览，所以这些派生值在说明或时区变化时算一次存起来，
/// 不在每次访问时重新解析说明、重新做日历换算。解析结果（display）随条目存进索引数据库；
/// 照片日期由拍摄时间和时区算出，不存。
nonisolated struct DiaryEntry: Identifiable, Hashable, Sendable {
    /// PHAsset.localIdentifier
    let id: String
    var caption: String { didSet { if caption != oldValue { reparse() } } }
    var keywords: [String]
    var creationDate: Date? { didSet { updateDay() } }
    var latitude: Double?
    var longitude: Double?
    var mediaKind: MediaKind
    var isCloudShared: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    /// 地点名称，由反向地理编码得到，可为空。
    var placeName: String?
    /// 拍摄地时区（由位置得到）。照片日期按拍摄地当地时间算，和照片 App 一致。
    var timeZoneID: String? { didSet { if timeZoneID != oldValue { updateDay() } } }
    /// 曾在本 App 写过。决定同步时是否按标签改写关键词。
    var writtenInApp: Bool = false

    /// 解析结果（由 caption 派生，随 caption 一起更新）。
    private(set) var display = CaptionDisplay()
    var segments: [DiarySegment] { display.segments }
    var tags: [String] { display.tags }
    var displaySegments: [DiarySegment] { display.displaySegments }
    var title: String { display.title }
    var preview: String { display.preview }
    private(set) var writingDays: [DayStamp] = []
    /// 照片日期；没有拍摄日期时退回第一段的写作日期。
    private(set) var day: DayStamp = .today
    /// 用于显示星期、日期的时间点（拍摄地当天的正午）。
    private(set) var displayDate: Date = .distantPast


    init(id: String, caption: String, keywords: [String], creationDate: Date?, latitude: Double?,
         longitude: Double?, mediaKind: MediaKind, isCloudShared: Bool, pixelWidth: Int,
         pixelHeight: Int, placeName: String? = nil, timeZoneID: String? = nil, writtenInApp: Bool = false,
         display: CaptionDisplay? = nil) {
        self.id = id
        self.caption = caption
        self.keywords = keywords
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
        self.mediaKind = mediaKind
        self.isCloudShared = isCloudShared
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.placeName = placeName
        self.timeZoneID = timeZoneID
        self.writtenInApp = writtenInApp
        // 从数据库读出时带着已有的解析结果，不再解析一遍。
        if let display { apply(display) } else { reparse() }
    }


    private mutating func reparse() {
        apply(CaptionDisplay(caption: caption))
    }

    /// 系统时区变了：没有拍摄地时区的照片按新的时区重算是哪一天。
    mutating func timeZoneChanged() {
        updateDay()
    }

    private mutating func apply(_ display: CaptionDisplay) {
        self.display = display
        writingDays = display.segments.compactMap(\.date)
        updateDay()
    }

    private mutating func updateDay() {
        if let creationDate {
            if let tz = timeZoneID.flatMap(TimeZone.init(identifier:)) {
                var calendar = Calendar.diary
                calendar.timeZone = tz
                day = DayStamp(creationDate, calendar: calendar)
            } else {
                day = DayStamp(creationDate)
            }
        } else {
            day = writingDays.first ?? .today
        }
        displayDate = day.date
    }

    var sortDate: Date { creationDate ?? displayDate }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    /// 一行标签：#旅行#  #镜头测试#（中间两个空格，卡片、行、分享图都用这个）。
    var tagLine: String { Self.tagLine(tags) }

    static func tagLine(_ tags: [String]) -> String { tags.map { "#\($0)#" }.joined(separator: "  ") }
}
