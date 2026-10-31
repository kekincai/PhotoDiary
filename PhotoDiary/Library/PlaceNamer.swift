import CoreLocation
import MapKit

/// 照片自带位置 → 城市名（如“横滨”）和当地时区。
final class PlaceNamer {
    var failed = Set<String>()

    func place(for coordinate: CLLocationCoordinate2D) async -> (name: String?, timeZone: String?)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        let reps = item.addressRepresentations
        return (reps?.cityName ?? reps?.cityWithContext ?? item.name, item.timeZone?.identifier)
    }
}
