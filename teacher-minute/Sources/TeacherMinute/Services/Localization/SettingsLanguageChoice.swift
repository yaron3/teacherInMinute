import Foundation

/// User-facing language preference. `system` follows the device language;
/// concrete cases pin the app to that ISO code regardless of the device
/// setting. Lives alongside `LocalizationSupport` so the whole localization
/// module can be copied between apps as a unit.
enum SettingsLanguageChoice: String, CaseIterable, Identifiable {
    case system
    case english
    case hebrew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: LocalizationSupport.localized("System Language")
        case .english: LocalizationSupport.localized("English")
        case .hebrew: LocalizationSupport.localized("Hebrew")
        }
    }

    var subtitle: String? {
        switch self {
        case .system: LocalizationSupport.localized("Use the device language")
        case .english, .hebrew: nil
        }
    }

    var remoteConfigLanguageCode: String {
        switch self {
        case .english:
            return "en"
        case .hebrew:
            return "he"
        case .system:
            return LocalizationSupport.currentLanguageCode
        }
    }
}
