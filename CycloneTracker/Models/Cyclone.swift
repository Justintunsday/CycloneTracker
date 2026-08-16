import CoreLocation
import Foundation

struct Cyclone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let basin: CycloneBasin
    let source: DataSource
    let isActive: Bool
    let windKnots: Int
    let pressureMB: Int
    let category: StormCategory
    let latitude: Double
    let longitude: Double
    let date: Date
    let track: [TrackPoint]
    let forecast: [TrackPoint]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var peakWindKnots: Int {
        track.map { $0.windKnots ?? 0 }.max() ?? windKnots
    }

    var peakPressureMB: Int {
        track.compactMap(\.pressureMB).min() ?? pressureMB
    }

    var startDate: Date? { track.first?.date }
    var endDate: Date? { track.last?.date ?? date }
    var infoURL: URL? { source.infoURL }

    var windKmh: Int { Int((Double(windKnots) * 1.852).rounded()) }
    var windMph: Int { Int((Double(windKnots) * 1.1508).rounded()) }
    var windMs: Int { Int((Double(windKnots) * 0.5144).rounded()) }

    var displayName: String {
        name.isEmpty || name.uppercased() == "UNNAMED" ? String(format: L("未命名 %@"), basin.rawValue) : name
    }

    func with(isActive: Bool) -> Cyclone {
        Cyclone(
            id: id,
            name: name,
            basin: basin,
            source: source,
            isActive: isActive,
            windKnots: windKnots,
            pressureMB: pressureMB,
            category: category,
            latitude: latitude,
            longitude: longitude,
            date: date,
            track: track,
            forecast: forecast
        )
    }
}
