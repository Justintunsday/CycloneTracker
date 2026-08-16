import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return AppSettings.shared.language == .en ? "System" : "跟随系统"
        case .zhHans: return "中文"
        case .en: return "English"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .en: return Locale(identifier: "en")
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return AppSettings.shared.language == .en ? "System" : "跟随系统"
        case .light: return AppSettings.shared.language == .en ? "Light" : "浅色"
        case .dark: return AppSettings.shared.language == .en ? "Dark" : "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appAppearance") }
    }

    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "") ?? .system
    }
}

func L(_ key: String) -> String {
    let settings = AppSettings.shared
    if let locale = settings.language.locale {
        return String(localized: String.LocalizationValue(key), locale: locale)
    }
    return String(localized: String.LocalizationValue(key))
}
