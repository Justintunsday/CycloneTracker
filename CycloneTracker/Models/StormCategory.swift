import SwiftUI

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
        case .disturbance: return L("热带扰动")
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
