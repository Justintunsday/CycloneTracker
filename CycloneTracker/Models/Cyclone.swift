import CoreLocation
import Foundation
import MapKit
import SwiftUI

enum CycloneBasin: String, CaseIterable, Identifiable, Codable, Sendable {
    case na = "NA"
    case ep = "EP"
    case wp = "WP"
    case ni = "NI"
    case si = "SI"
    case sp = "SP"
    case sa = "SA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .na: return L("北大西洋")
        case .ep: return L("东北太平洋")
        case .wp: return L("西北太平洋")
        case .ni: return L("北印度洋")
        case .si: return L("南印度洋")
        case .sp: return L("南太平洋")
        case .sa: return L("南大西洋")
        }
    }

    static func fromIBTrACS(_ code: String) -> CycloneBasin? {
        CycloneBasin(rawValue: code.uppercased())
    }
}

enum DataSource: String, Sendable {
    case nhc = "NHC"
    case jtwc = "JTWC"
    case ibtracs = "IBTrACS"

    var displayName: String { rawValue }

    var infoURL: URL? {
        switch self {
        case .nhc: return URL(string: "https://www.nhc.noaa.gov")
        case .jtwc: return URL(string: "https://www.metoc.navy.mil/jtwc/jtwc.html")
        case .ibtracs: return URL(string: "https://www.ncei.noaa.gov/products/international-best-track-archive")
        }
    }
}

enum StormCategory: Int, Comparable, Sendable {
    case disturbance = 0
    case depression = 1
    case storm = 2
    case category1 = 3
    case category2 = 4
    case category3 = 5
    case category4 = 6
    case category5 = 7

    var displayName: String {
        switch self {
        case .disturbance: return L("热带扰动")
        case .depression: return L("热带低压")
        case .storm: return L("热带风暴")
        case .category1: return L("一级气旋")
        case .category2: return L("二级气旋")
        case .category3: return L("三级气旋")
        case .category4: return L("四级气旋")
        case .category5: return L("五级气旋")
        }
    }

    var shortName: String {
        switch self {
        case .disturbance: return "扰动"
        case .depression: return "TD"
        case .storm: return "TS"
        case .category1: return "C1"
        case .category2: return "C2"
        case .category3: return "C3"
        case .category4: return "C4"
        case .category5: return "C5"
        }
    }

    var color: Color {
        switch self {
        case .disturbance: return Color(hex: 0x8A9BB5)
        case .depression: return Color(hex: 0x5EB8FF)
        case .storm: return Color(hex: 0x00FAF4)
        case .category1: return Color(hex: 0xFFFFCC)
        case .category2: return Color(hex: 0xFFE775)
        case .category3: return Color(hex: 0xFFC140)
        case .category4: return Color(hex: 0xFF8F20)
        case .category5: return Color(hex: 0xFF6060)
        }
    }

    static func fromWind(knots: Int) -> StormCategory {
        switch knots {
        case ..<25: return .disturbance
        case ..<34: return .depression
        case ..<64: return .storm
        case ..<83: return .category1
        case ..<96: return .category2
        case ..<113: return .category3
        case ..<137: return .category4
        default: return .category5
        }
    }

    static func < (lhs: StormCategory, rhs: StormCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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

struct CycloneSelection: MapSelectable {
    let id: String
    var feature: MapFeature?

    init(id: String) {
        self.id = id
        self.feature = nil
    }

    init(_ feature: MapFeature?) {
        self.feature = feature
        self.id = feature?.title ?? ""
    }

    static func == (lhs: CycloneSelection, rhs: CycloneSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CLLocationCoordinate2D {
    var formatted: String {
        String(format: "%.1f°%@ %.1f°%@",
               abs(latitude), latitude >= 0 ? "N" : "S",
               abs(longitude), longitude >= 0 ? "E" : "W")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
