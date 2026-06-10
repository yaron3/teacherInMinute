import Foundation

/// Boundary that turns an English source string into the active-language
/// version. Replaces the bundled `Localizable.xcstrings` lookup with a
/// Remote-Config-driven fetch so translations can be edited in the Firebase
/// console without an app update.
protocol LocalizationServiceProtocol {
    /// Returns the active-language string for the given English source. The
    /// English text is both the lookup hint (the impl maps it to a stable
    /// snake-case key) and the fallback when no translation is active.
    func localized(_ english: String) -> String
}

/// Static fallback used by previews, tests, and any code path that needs the
/// protocol but shouldn't hit Remote Config. Returns the English source
/// unchanged.
struct StaticLocalizationService: LocalizationServiceProtocol {
    func localized(_ english: String) -> String { english }
}
