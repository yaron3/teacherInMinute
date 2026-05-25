import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum LocalizationSupport {
    static let languagePreferenceKey = "settings.language.preference"
    private static let supportedLanguageCodes = ["en", "he"]

    static var currentLocale: Locale {
        Locale(identifier: currentLanguageCode)
    }

    static var preferredFieldPrefix: String? {
        preferredLanguageCode
    }

    static func localized(_ key: String) -> String {
        #if os(Android)
        // On Skip Fuse Android the module's `.strings` files are shipped as
        // Android assets (not in the Swift resource bundle that
        // swift-corelibs-foundation's Bundle can see), so we load them via the
        // `asset://` URL protocol that Skip registers at app startup.
        return androidLocalized(key)
        #else
        let languageCode = currentLanguageCode
        if let bundleURL = Bundle.module.url(forResource: languageCode, withExtension: "lproj"),
           let localizedBundle = Bundle(url: bundleURL) {
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        #endif
    }

    #if os(Android)
    // Module assets are nested under the Android package path. For this app the
    // ANDROID_PACKAGE_NAME (`teacher.minute`) becomes `teacher/minute/Resources`.
    private static let androidAssetsModulePath = "teacher/minute/Resources"

    private final class AndroidTranslationsStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var cache: [String: [String: String]] = [:]

        func translations(for languageCode: String) -> [String: String] {
            lock.lock()
            defer { lock.unlock() }
            if let cached = cache[languageCode] { return cached }
            let table = LocalizationSupport.loadAndroidStrings(for: languageCode) ?? [:]
            cache[languageCode] = table
            return table
        }
    }

    private static let androidTranslationsStorage = AndroidTranslationsStorage()

    private static func androidLocalized(_ key: String) -> String {
        let languageCode = currentLanguageCode
        let table = androidTranslationsStorage.translations(for: languageCode)
        if let value = table[key], !value.isEmpty { return value }
        if languageCode != "en" {
            let fallback = androidTranslationsStorage.translations(for: "en")
            if let value = fallback[key], !value.isEmpty { return value }
        }
        return key
    }

    fileprivate static func loadAndroidStrings(for languageCode: String) -> [String: String]? {
        let path = "\(androidAssetsModulePath)/\(languageCode).lproj/Localizable.strings"
        guard let url = URL(string: "asset:///\(path)"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return plist
    }
    #endif

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

    /// Resolves the current language code with this priority order:
    /// 1. In-app language selection (Settings → Language inside the app)
    /// 2. iOS Settings → App → Language (per-app override)
    /// 3. Device language (Settings → General → Language & Region)
    /// 4. English fallback
    static var currentLanguageCode: String {
        #if !os(Android)
        let inAppRaw = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? "<unset>"
        let appleLanguages = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]) ?? []
        //logger.info("[Localization] resolve — inAppPref='\(inAppRaw)' AppleLanguages=\(appleLanguages) Locale.preferredLanguages=\(Locale.preferredLanguages) Bundle.main.preferredLocalizations=\(Bundle.main.preferredLocalizations) Bundle.main.localizations=\(Bundle.main.localizations)")
        #endif
        if let code = preferredLanguageCode {
            //logger.info("[Localization] using in-app preference → \(code)")
            return code
        }
        return systemLanguageCode
    }

    private static var systemLanguageCode: String {
        #if !os(Android)
        // `Locale.preferredLanguages` reads `AppleLanguages` from the app's
        // UserDefaults. iOS prepends the per-app language override (if set in
        // Settings → App → Language) to that list, so iterating naturally
        // applies the per-app choice first, then the device language list.
        // We avoid `Bundle.main.preferredLocalizations` because the app's
        // localized strings live in `Bundle.module`, so the main bundle may
        // not advertise Hebrew and would incorrectly fall back to "en".
        for identifier in Locale.preferredLanguages {
            if let code = normalizedSupportedLanguageCode(for: identifier) {
             //   logger.info("[Localization] matched Locale.preferredLanguages entry '\(identifier)' → \(code)")
                return code
            }
        }
       // logger.info("[Localization] no Locale.preferredLanguages entry matched supported codes \(supportedLanguageCodes); falling back to 'en'")
        #endif
        return "en"
    }

    private static func normalizedSupportedLanguageCode(for identifier: String) -> String? {
        let languageCode = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        return supportedLanguageCodes.contains(languageCode) ? languageCode : nil
    }

    static func locale(languagePreference rawValue: String) -> Locale {
        switch rawValue {
        case SettingsLanguageChoice.english.rawValue:
            Locale(identifier: "en")
        case SettingsLanguageChoice.hebrew.rawValue:
            Locale(identifier: "he")
        default:
            Locale(identifier: systemLanguageCode)
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
        currentLanguageCode == "he"
    }

    static var layoutDirection: LayoutDirection {
        usesRightToLeftLayout ? .rightToLeft : .leftToRight
    }
}
