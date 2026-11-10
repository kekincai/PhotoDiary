import Foundation
import ImageIO
import UniformTypeIdentifiers

// 给测试照片写入 EXIF 拍摄日期、GPS 和 IPTC 说明（照片 App 会把 IPTC 说明读成“说明”）。
// usage: tag <spec.json> <inDir> <outDir>
// spec: [{"file": "u_00.jpg", "date": "2026:10:30 19:20:00", "lat": 35.6, "lon": 139.7, "caption": "..."}]
// 日期也可以按今天算：{"daysAgo": 2, "yearsAgo": 1, "time": "09:30:00"}，"time": "now" 是今天、导入前一分钟；
// 说明里的 {date} 换成那天的 2026.10.30。
// 界面测试的种子照片都按今天算，哪天跑都有“那年今日”、都在本月。
struct Item: Decodable {
    var file: String
    var date: String?
    var daysAgo: Int?
    var yearsAgo: Int?
    var time: String?
    var lat: Double?
    var lon: Double?
    var caption: String?

    /// （EXIF 的日期时间，说明里的日期）
    var resolved: (exif: String, stamp: String) {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let calendar = Calendar(identifier: .gregorian)
        let when: Date
        if let date, let fixed = parse.date(from: date) {
            when = fixed
        } else if time == "now" {
            // 今天、但不在将来：跑测试前一分钟（刚过零点时就是零点整）。
            when = max(calendar.startOfDay(for: .now), Date.now.addingTimeInterval(-60))
        } else {
            let parts = (time ?? "12:00:00").split(separator: ":").compactMap { Int($0) }
            var day = calendar.startOfDay(for: .now)
            day = calendar.date(byAdding: .year, value: -(yearsAgo ?? 0), to: day)!
            day = calendar.date(byAdding: .day, value: -(daysAgo ?? 0), to: day)!
            when = calendar.date(bySettingHour: parts[0], minute: parts[1], second: parts.count > 2 ? parts[2] : 0, of: day)!
        }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy.MM.dd"
        return (parse.string(from: when), stamp.string(from: when))
    }
}

let args = CommandLine.arguments
let items = try JSONDecoder().decode([Item].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
for var item in items {
    let (date, stamp) = item.resolved
    item.date = date
    item.caption = item.caption?.replacingOccurrences(of: "{date}", with: stamp)
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(args[2])/\(item.file)") as CFURL, nil)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(args[3])/\(item.file)") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var tiff: [CFString: Any] = [kCGImagePropertyTIFFDateTime: date]
    var props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: date, kCGImagePropertyExifDateTimeDigitized: date],
        kCGImageDestinationLossyCompressionQuality: 0.85,
    ]
    if let lat = item.lat, let lon = item.lon {
        props[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: abs(lat), kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(lon), kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
        ]
    }
    if let caption = item.caption {
        props[kCGImagePropertyIPTCDictionary] = [kCGImagePropertyIPTCCaptionAbstract: caption]
        tiff[kCGImagePropertyTIFFImageDescription] = caption
    }
    props[kCGImagePropertyTIFFDictionary] = tiff
    CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}
print("tagged \(items.count)")
