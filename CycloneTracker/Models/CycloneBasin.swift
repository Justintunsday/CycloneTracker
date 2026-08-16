import Foundation

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
