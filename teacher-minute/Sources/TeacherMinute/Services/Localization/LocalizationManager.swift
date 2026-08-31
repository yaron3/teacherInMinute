import SwiftUI
#if !os(Android)
import FirebaseAnalytics
#else
import SkipFirebaseAnalytics
#endif
#if SKIP
import SkipFuseUI
#endif

@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private enum DefaultsKey {
        static let appLanguage = "appLanguage"
        static let appleLanguages = "AppleLanguages"
    }

    /// Google Analytics user properties that Remote Config conditions can
    /// target to pick the translation set. The fetch request carries user
    /// properties in its `analyticsUserProperties` field, so a condition on
    /// one of these resolves against the language the user picked in-app
    /// rather than the device locale that `device.language` reports.
    private enum AnalyticsProperty {
        static let userLanguage = "user_language"
        static let appLanguage = "app_language"
    }

    var dataFetched = false
    var languageCode: String
    var layoutDirection: LayoutDirection
    var locale: Locale
    var isLoading = false

    /// Public lookup used by views/view-models for active-language strings.
    /// Backed by Remote Config; falls back to the English source.
  let service: any LocalizationServiceProtocol = RemoteConfigLocalizationService.shared

    let languages: [String: String] = [
        "": "System",
        "en": "English",
        "he": "עברית",
        // "ar": "عربي",
        // "ru": "Русский",
    ]

    private init() {
        let savedCode = UserDefaults.standard.string(forKey: DefaultsKey.appLanguage) ?? ""
        self.languageCode = savedCode
        let resolvedCode = Self.resolvedLanguageCode(for: savedCode)
        self.locale = Self.locale(for: savedCode)
        self.layoutDirection = Self.layoutDirection(for: resolvedCode)
        // Re-apply the saved override on every launch so Firebase Remote
        // Config evaluates `device.language` against the user's chosen app
        // language rather than the JVM/system default.
        Self.applySystemLocaleOverride(for: savedCode)
        Self.applyRemoteConfigLanguageSignal(resolvedCode)
    }

    /// Applies the new language to the process-wide locale, then awaits the
    /// Remote Config refresh so the caller can trigger UI updates only after
    /// the active values reflect the new language.
    func updateLanguageCode(to newLanguageCode: String) async {
        languageCode = newLanguageCode
        let resolvedCode = Self.resolvedLanguageCode(for: newLanguageCode)
        locale = Self.locale(for: newLanguageCode)
        layoutDirection = Self.layoutDirection(for: resolvedCode)

        if newLanguageCode.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.appLanguage)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.appleLanguages)
        } else {
            UserDefaults.standard.set(newLanguageCode, forKey: DefaultsKey.appLanguage)
            UserDefaults.standard.set([newLanguageCode], forKey: DefaultsKey.appleLanguages)
        }
        UserDefaults.standard.synchronize()

        Self.applySystemLocaleOverride(for: newLanguageCode)
        Self.applyRemoteConfigLanguageSignal(resolvedCode)

        isLoading = true
        dataFetched = false
        await RemoteConfigService.shared.refresh(language: resolvedCode)
        dataFetched = true
        isLoading = false
    }

    func selectedLanguageName() -> String {
        languages[languageCode] ?? languageCode
    }

    static func locale(for code: String) -> Locale {
        Locale(identifier: resolvedLanguageCode(for: code))
    }

    static func layoutDirection(forLanguageCode code: String) -> LayoutDirection {
        layoutDirection(for: resolvedLanguageCode(for: code))
    }

    private static func resolvedLanguageCode(for code: String) -> String {
        if !code.isEmpty { return code }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }

    private static func layoutDirection(for code: String) -> LayoutDirection {
        ["ar", "he", "iw", "fa", "ur"].contains(code) ? .rightToLeft : .leftToRight
    }

    /// Aligns the process-wide locale with the user's chosen language so the
    /// Firebase Remote Config SDK sends the matching `device.language` on its
    /// next fetch. iOS reads from `AppleLanguages` automatically (we wrote it
    /// to `UserDefaults` above), while Android needs an explicit JVM default
    /// locale update before fetching Remote Config.
    private static func applySystemLocaleOverride(for code: String) {
        #if os(Android)
        AndroidLocaleBridge.applyLanguageCode(resolvedLanguageCode(for: code))
        #endif
    }

    /// Publishes the selected language to every channel a Remote Config
    /// condition can read, then leaves the fetch to the caller — every call
    /// site is immediately followed by `RemoteConfigService.refresh()`, which
    /// force-fetches with `expirationDuration: 0` so the new values are not
    /// served from the one-hour cache.
    static func applyRemoteConfigLanguageSignal(_ languageCode: String = LocalizationSupport.currentLanguageCode) {
        Analytics.setUserProperty(languageCode, forName: AnalyticsProperty.userLanguage)
        Analytics.setUserProperty(languageCode, forName: AnalyticsProperty.appLanguage)
        #if os(Android)
        AndroidLocaleBridge.applyRemoteConfigLanguageSignal(languageCode)
        #endif
        logger.info("[Localization] applied Remote Config language signal \(AnalyticsProperty.userLanguage)=\(languageCode)")
    }
}
