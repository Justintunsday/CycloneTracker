import Foundation

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
