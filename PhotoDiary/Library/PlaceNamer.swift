import CoreLocation
import MapKit

/// 坐标 → 地名和当地时区。查不到返回 nil。地名用哪种语言由调用方给（DiaryStore 的 placeLanguage），只有这一个来源。
protocol PlaceNaming {
    func place(for coordinate: CLLocationCoordinate2D, language: String) async -> (name: String?, timeZone: String?)?
}

/// 照片自带位置 → 城市名（如“横滨”）和当地时区。
final class PlaceNamer: PlaceNaming {
    func place(for coordinate: CLLocationCoordinate2D, language: String) async -> (name: String?, timeZone: String?)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: language)
        guard let item = try? await request.mapItems.first else { return nil }
        let reps = item.addressRepresentations
        return (reps?.cityName ?? reps?.cityWithContext ?? item.name, item.timeZone?.identifier)
    }
}
