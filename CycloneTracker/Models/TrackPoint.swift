import CoreLocation
import Foundation

struct TrackPoint: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let latitude: Double
    let longitude: Double
    let windKnots: Int?
    let pressureMB: Int?
    let category: StormCategory

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
