import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum LocalizationSupport {
    static let languagePreferenceKey = "settings.language.preference"

    static var currentLocale: Locale {
        let rawValue = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? SettingsLanguageChoice.system.rawValue
        return locale(languagePreference: rawValue)
    }

    static var preferredFieldPrefix: String? {
        preferredLanguageCode
    }

    static func localized(_ key: String) -> String {
        #if os(Android)
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

    /// The current app language code ("en" or "he"), resolving "System" via the device locale.
    static var currentLanguageCode: String {
        if let code = preferredLanguageCode {
            return code
        }
        let deviceCode = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }
        return deviceCode == "he" ? "he" : "en"
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

    @MainActor
    static func applyPlatformLayoutDirection(languagePreference rawValue: String) {
        #if canImport(UIKit)
        let semanticAttribute: UISemanticContentAttribute = layoutDirection(languagePreference: rawValue) == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = semanticAttribute
        UINavigationBar.appearance().semanticContentAttribute = semanticAttribute
        UITabBar.appearance().semanticContentAttribute = semanticAttribute
        #endif
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
