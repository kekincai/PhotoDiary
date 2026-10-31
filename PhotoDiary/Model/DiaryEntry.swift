import Foundation
import CoreLocation

nonisolated enum MediaKind: String, Codable, Sendable {
    case photo, livePhoto, video
}

/// 本地索引里的一条记录：一张带说明的照片。可以随时从照片库完整重建。
nonisolated struct DiaryEntry: Identifiable, Hashable, Codable, Sendable {
    /// PHAsset.localIdentifier
    let id: String
    var caption: String
    var keywords: [String]
    var creationDate: Date?
    var latitude: Double?
    var longitude: Double?
    var mediaKind: MediaKind
    var isCloudShared: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    /// 地点名称，由反向地理编码得到，可为空。
    var placeName: String?
    /// 拍摄地时区（由位置得到）。照片日期按拍摄地当地时间算，和照片 App 一致。
    var timeZoneID: String?
    /// 曾在本 App 写过（即使用户之后删掉了日期行，也仍然算日记）。
    var writtenInApp: Bool = false

    // 解析结果（由 caption 派生，随 caption 一起更新）。
    private(set) var segments: [DiarySegment] = []
    private(set) var tags: [String] = []

    init(id: String, caption: String, keywords: [String], creationDate: Date?, latitude: Double?,
         longitude: Double?, mediaKind: MediaKind, isCloudShared: Bool, pixelWidth: Int,
         pixelHeight: Int, placeName: String? = nil, writtenInApp: Bool = false) {
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
        self.writtenInApp = writtenInApp
        reparse()
    }

    mutating func reparse() {
        let parsed = CaptionFormat.parse(caption)
        segments = parsed.segments
        tags = parsed.tags
    }

    /// 带写作时间行或曾在本 App 写过的算日记；其余（Lightroom 导入的 IPTC 说明等）算外部说明。
    var isDiary: Bool { writtenInApp || segments.contains { $0.date != nil } }

    /// 照片日期；没有拍摄日期时退回第一段的写作日期。
    var day: DayStamp {
        if let creationDate {
            guard let tz = timeZoneID.flatMap(TimeZone.init(identifier:)) else { return DayStamp(creationDate) }
            var calendar = Calendar.diary
            calendar.timeZone = tz
            return DayStamp(creationDate, calendar: calendar)
        }
        return segments.compactMap(\.date).first ?? .today
    }

    /// 用于显示星期、日期的时间点（拍摄地当天的正午）。
    var displayDate: Date { day.date }

    var sortDate: Date { creationDate ?? day.date }

    var writingDays: [DayStamp] { segments.compactMap(\.date) }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    // MARK: 显示

    /// 去掉行尾标签后的各段正文。
    var displaySegments: [DiarySegment] {
        segments.map { DiarySegment(text: CaptionFormat.strippingTrailingTags($0.text), date: $0.date) }
            .filter { !$0.text.isEmpty || $0.date != nil }
    }

    var title: String {
        CaptionFormat.splitTitle(displaySegments.first?.text ?? "").title
    }

    /// 列表预览：只有一段时显示首句之后的内容；多段时显示最新追加的那段。
    var preview: String {
        let segs = displaySegments
        if segs.count > 1 { return segs.last?.text ?? "" }
        return CaptionFormat.splitTitle(segs.first?.text ?? "").rest
    }

    var tagLine: String { tags.map { "#\($0)#" }.joined(separator: " ") }
}
