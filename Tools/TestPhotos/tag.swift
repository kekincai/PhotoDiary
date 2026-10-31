import Foundation
import ImageIO
import UniformTypeIdentifiers

// 给测试照片写入 EXIF 拍摄日期、GPS 和 IPTC 说明（照片 App 会把 IPTC 说明读成“说明”）。
// usage: tag <spec.json> <inDir> <outDir>
// spec: [{"file": "u_00.jpg", "date": "2026:10:30 19:20:00", "lat": 35.6, "lon": 139.7, "caption": "..."}]
struct Item: Decodable { var file: String; var date: String; var lat: Double?; var lon: Double?; var caption: String? }

let args = CommandLine.arguments
let items = try JSONDecoder().decode([Item].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
for item in items {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(args[2])/\(item.file)") as CFURL, nil)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(args[3])/\(item.file)") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var tiff: [CFString: Any] = [kCGImagePropertyTIFFDateTime: item.date]
    var props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: item.date, kCGImagePropertyExifDateTimeDigitized: item.date],
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
