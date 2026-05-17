import Foundation
import SwiftUI

enum LocalizationSupport {
    static let languagePreferenceKey = "settings.language.preference"

    static var currentLocale: Locale {
        let rawValue = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? SettingsLanguageChoice.system.rawValue
        return locale(languagePreference: rawValue)
    }

    static func localized(_ key: String) -> String {
        #if os(Android)
        if preferredLanguageCode == "he", let translated = hebrewLocalizedValue(for: key) {
            return translated
        }
        return NSLocalizedString(key, comment: "")
        #else
        if let languageCode = preferredLanguageCode,
           let bundleURL = Bundle.module.url(forResource: languageCode, withExtension: "lproj"),
           let localizedBundle = Bundle(url: bundleURL) {
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        #endif
    }

    private static var preferredLanguageCode: String? {
        let rawValue = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? SettingsLanguageChoice.system.rawValue
        switch rawValue {
        case SettingsLanguageChoice.english.rawValue:
            return "en"
        case SettingsLanguageChoice.hebrew.rawValue:
            return "he"
        default:
            return nil
        }
    }

    private static func hebrewLocalizedValue(for key: String) -> String? {
        switch key {
        case "Completed lesson with %@.":
            return "שיעור שהושלם עם %@."
        case "Lesson transcript will appear here when available.":
            return "תמלול השיעור יופיע כאן כשיהיה זמין."
        case "%lld completed":
            return "%lld שיעורים הושלמו"
        case "%lld taught":
            return "%lld שיעורים שלימדת"
        case "1 min":
            return "דקה אחת"
        case "%lld min":
            return "%lld דק׳"
        case "%lld mins":
            return "%lld דק׳"
        default:
            return nil
        }
    }

    static func locale(languagePreference rawValue: String) -> Locale {
        switch rawValue {
        case SettingsLanguageChoice.english.rawValue:
            Locale(identifier: "en")
        case SettingsLanguageChoice.hebrew.rawValue:
            Locale(identifier: "he")
        default:
            .autoupdatingCurrent
        }
    }

    static func layoutDirection(languagePreference rawValue: String) -> LayoutDirection {
        switch rawValue {
        case SettingsLanguageChoice.hebrew.rawValue:
            .rightToLeft
        case SettingsLanguageChoice.english.rawValue:
            .leftToRight
        default:
            layoutDirection
        }
    }

    static var usesRightToLeftLayout: Bool {
        Locale.preferredLanguages.contains { identifier in
            let languageCode = Locale(identifier: identifier).language.languageCode?.identifier
            return languageCode == "he"
        }
    }

    static var layoutDirection: LayoutDirection {
        usesRightToLeftLayout ? .rightToLeft : .leftToRight
    }
}
