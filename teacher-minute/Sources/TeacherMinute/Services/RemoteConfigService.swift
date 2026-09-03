//
//  RemoteConfigService.swift
//  teacher-minute
//

import Foundation

#if !os(Android)
import FirebaseRemoteConfig
import FirebaseCore
#else
import SkipFirebaseRemoteConfig
#endif

enum RemoteConfigKey: String {
    case eulaURL = "eula_url"
    case privacyPolicyURL = "privacy_policy"
    case teacherIdGovIdDescription = "teacher_id_govid_description"
    case teacherIdCredentialsDescription = "teacher_id_credentials_description"
    case teacherIdSelfieDescription = "teacher_id_selfie_description"
    /// Ordered list of payment methods to offer at checkout, as an array (or
    /// comma-separated string) of `PaymentMethod` raw values. Platform targeting
    /// (iOS vs Android) is expected to be handled by Remote Config conditions on
    /// this key, so the client reads a single key and falls back to the built-in
    /// per-platform defaults when the key is absent.
    case paymentMethods = "payment_methods"
    case teacherDescription = "teacher_description"
    case studentDescription = "student_description"
}

enum RemoteConfigLaunchError: LocalizedError {
    case initialFetchTimedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .initialFetchTimedOut(let seconds):
            return "Remote Config initial fetch did not complete within \(seconds) seconds."
        }
    }
}

private final class RemoteConfigLaunchContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Bool, Never>

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resumeOnce(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}

@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    private var firstFetch: Task<Void, Never>?
    private var didRecordLaunchTimeout = false
    private let launchTimeoutSeconds = 30

    private init() {}

    /// Configure Remote Config and kick off the first fetch.
    /// Call once at app launch. Subsequent reads are served from memory.
    func start() {
        guard firstFetch == nil else {
            #if os(Android)
            logger.info("[RemoteConfig][Android] start skipped; first fetch task already exists")
            #endif
            return
        }
        LocalizationManager.applyRemoteConfigLanguageSignal()
        #if os(Android)
        AndroidLocaleBridge.applyLanguageCode(LocalizationSupport.currentLanguageCode)
        #endif
        configureRemoteConfig()
        #if os(Android)
        logger.info("[RemoteConfig][Android] start; language=\(LocalizationSupport.currentLanguageCode) locale=\(LocalizationSupport.currentLocale.identifier)")
        #endif
        firstFetch = Task { @MainActor in
            let remoteConfig = RemoteConfig.remoteConfig()
            do {
                let status = try await remoteConfig.fetchAndActivate()
                // Newly activated values must not be shadowed by strings
                // resolved against the previous config.
                RemoteConfigLocalizationService.invalidateCache()
                #if os(Android)
                Self.logFetchState(remoteConfig, context: "initial fetchAndActivate", activateStatus: status)
                #endif
            } catch {
                logger.error("[RemoteConfig] initial fetchAndActivate failed: \(error.localizedDescription)")
            }
        }
    }

    /// Await this when startup must hold until Remote Config is ready. Returns
    /// `false` only when the launch timeout wins; the fetch task continues so a
    /// late result can still activate values for the running app.
    func readyForLaunch() async -> Bool {
        if firstFetch == nil {
            start()
        }
        guard let firstFetch else { return true }

        let timeoutSeconds = launchTimeoutSeconds
        let completedBeforeTimeout = await firstFetchCompletedWithinLaunchTimeout(
            firstFetch,
            timeoutSeconds: timeoutSeconds
        )

        if completedBeforeTimeout {
            logger.info("[RemoteConfig] initial fetch completed before launch gate timeout")
        } else {
            recordLaunchTimeout(seconds: timeoutSeconds)
        }
        return completedBeforeTimeout
    }

    private nonisolated func firstFetchCompletedWithinLaunchTimeout(
        _ firstFetch: Task<Void, Never>,
        timeoutSeconds: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let launchContinuation = RemoteConfigLaunchContinuation(continuation)

            Task {
                await firstFetch.value
                launchContinuation.resumeOnce(true)
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                launchContinuation.resumeOnce(false)
            }
        }
    }

    /// Await this when a caller needs to be sure the first fetch has completed.
    func ready() async {
        await firstFetch?.value
    }

    /// Force a refresh, ignoring the minimum fetch interval. Uses
    /// `fetch(withExpirationDuration: 0)` so the SDK actually re-pulls the
    /// template — `fetchAndActivate()` alone honors `minimumFetchInterval`
    /// and would otherwise serve cached values for up to an hour.
    ///
    /// Pass `language` when refreshing as part of a language switch. The
    /// default reads `settings.language.preference`, which a switch only
    /// writes *after* this call returns — so relying on the default here would
    /// re-publish the outgoing language to Analytics and the JVM locale
    /// immediately before fetching, and the server would hand back the
    /// language the user just moved away from.
    func refresh(language: String? = nil) async {
        let languageCode = language ?? LocalizationSupport.currentLanguageCode
        LocalizationManager.applyRemoteConfigLanguageSignal(languageCode)
        #if os(Android)
        AndroidLocaleBridge.applyLanguageCode(languageCode)
        #endif
        let remoteConfig = RemoteConfig.remoteConfig()
        #if os(Android)
        logger.info("[RemoteConfig][Android] refresh; language=\(languageCode) locale=\(LocalizationSupport.currentLocale.identifier)")
        #endif
        do {
            let fetchStatus = try await remoteConfig.fetch(withExpirationDuration: 0)
            let activated = try await remoteConfig.activate()
            RemoteConfigLocalizationService.invalidateCache()
            #if os(Android)
            Self.logFetchState(remoteConfig, context: "refresh", fetchStatus: fetchStatus, activated: activated)
            #endif
        } catch {
            logger.error("[RemoteConfig] refresh failed: \(error.localizedDescription)")
        }
    }

    private func configureRemoteConfig() {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = Double(launchTimeoutSeconds)
        remoteConfig.configSettings = settings
        #if os(Android)
        logger.info("[RemoteConfig][Android] configured; minimumFetchInterval=\(settings.minimumFetchInterval) fetchTimeout=\(settings.fetchTimeout)")
        #endif
    }

    private func recordLaunchTimeout(seconds: Int) {
        guard !didRecordLaunchTimeout else { return }
        didRecordLaunchTimeout = true
        logger.warning("[RemoteConfig] launch gate timed out after \(seconds) seconds; continuing with cached/default values")
        AnalyticsService.shared.logEvent("remote_config_launch_timeout", parameters: [
            "timeout_seconds": seconds
        ])
    }

    // MARK: - Sync accessors

    static func getLocalizedString(for key: RemoteConfigKey) -> String {
        shared.getLocalizedString(key.rawValue)
    }

    /// Like `getLocalizedString(for:)` but returns `fallback` when Remote Config
    /// has no value for the key yet (missing key, or before the first fetch).
    /// Use this for display text so the UI is never blank.
    static func getLocalizedString(for key: RemoteConfigKey, fallback: String) -> String {
        let value = shared.getLocalizedString(key.rawValue)
        return value.isEmpty ? fallback : value
    }

    static func getLocalizedStringArray(for key: RemoteConfigKey) -> [String] {
        shared.getLocalizedStringArray(key.rawValue)
    }

    func getLocalizedString(_ key: String) -> String {
        let localizedKey = "\(key)_\(LocalizationSupport.currentLanguageCode)"
        return getString(localizedKey)
    }

    func getLocalizedStringArray(_ key: String) -> [String] {
        let localizedKey = "\(key)_\(LocalizationSupport.currentLanguageCode)"
        return getStringArray(localizedKey)
    }

    func getString(_ key: String) -> String {
        Self.readString(key)
    }

    /// Non-isolated read for callers (e.g. `LocalizationSupport.localized`) that
    /// run outside the main actor. Firebase Remote Config reads are thread-safe
    /// once `start()` has activated the initial fetch.
    nonisolated static func readString(_ key: String) -> String {
        #if !os(Android)
        guard FirebaseApp.app() != nil else { return "" }
        #endif
        let value = RemoteConfig.remoteConfig().configValue(forKey: key)
        // Deliberately not logged per call: this runs for every localized
        // string, and on Android the extra `value.source` read is a second JNI
        // round trip. RemoteConfigLocalizationService logs each key once, on
        // its cache miss, which covers the same diagnostic need.
        return decodingEscapes(value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Remote Config stores values as plain text, so a `\n` typed into the
    /// console arrives as the two characters `\` and `n` and would render
    /// literally. Decode the escapes an author reasonably expects to work —
    /// `\n`, `\t`, `\r`, and `\\` for a literal backslash — here, at the one
    /// point every config string passes through. Any other `\x` sequence is
    /// left untouched so paths and regexes in config values survive intact.
    nonisolated static func decodingEscapes(_ value: String) -> String {
        guard value.contains("\\") else { return value }

        var decoded = ""
        var isEscaping = false
        for character in value {
            if isEscaping {
                switch character {
                case "n": decoded.append("\n")
                case "t": decoded.append("\t")
                case "r": decoded.append("\r")
                case "\\": decoded.append("\\")
                default:
                    decoded.append("\\")
                    decoded.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                decoded.append(character)
            }
        }
        if isEscaping {
            decoded.append("\\")
        }
        return decoded
    }

    func getNumber(_ key: String) -> Double {
        Double(getString(key)) ?? 0
    }

    func getBool(_ key: String) -> Bool {
        #if !os(Android)
        guard FirebaseApp.app() != nil else { return false }
        #endif
        return RemoteConfig.remoteConfig().configValue(forKey: key).boolValue
    }

    /// Like `getBool(_:)` but returns `defaultValue` when Remote Config has no
    /// value for the key at all (neither fetched from the server nor a local
    /// default) — i.e. the key has never been configured. Use this for
    /// feature-style flags that should default on/off client-side until
    /// someone explicitly sets them remotely.
    func getBool(_ key: String, default defaultValue: Bool) -> Bool {
        #if !os(Android)
        guard FirebaseApp.app() != nil else { return defaultValue }
        #endif
        let value = RemoteConfig.remoteConfig().configValue(forKey: key)
        guard value.source != .static else { return defaultValue }
        return value.boolValue
    }

    func getURL(_ key: String) -> URL? {
        let value = getString(key)
        guard !value.isEmpty,
              let url = URL(string: value),
              url.scheme != nil else { return nil }
        return url
    }

    func getStringArray(_ key: String) -> [String] {
        #if !os(Android)
        guard FirebaseApp.app() != nil else { return [] }
        #endif
        let value = RemoteConfig.remoteConfig().configValue(forKey: key)
        #if os(Android)
        logger.info("[RemoteConfig][Android] read array key='\(key)' source=\(Self.debugSourceName(value.source)) rawLength=\(value.stringValue.count)")
        #endif
        if let array = value.jsonValue as? [String] {
            return array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    #if os(Android)
    private static func logFetchState(
        _ remoteConfig: RemoteConfig,
        context: String,
        fetchStatus: RemoteConfigFetchStatus? = nil,
        activateStatus: RemoteConfigFetchAndActivateStatus? = nil,
        activated: Bool? = nil
    ) {
        let keys = remoteConfig.allKeys(from: .remote).sorted()
        let sampleKeys = keys.prefix(12).joined(separator: ",")
        let fetchStatusText = fetchStatus.map { debugFetchStatusName($0) } ?? "nil"
        let activateStatusText = activateStatus.map { debugActivateStatusName($0) } ?? "nil"
        let activatedText = activated.map { String($0) } ?? "nil"
        let lastFetchTime = remoteConfig.lastFetchTime?.description ?? "nil"
        logger.info("[RemoteConfig][Android] \(context); fetchStatus=\(fetchStatusText) activateStatus=\(activateStatusText) activated=\(activatedText) lastFetchStatus=\(debugFetchStatusName(remoteConfig.lastFetchStatus)) lastFetchTime=\(lastFetchTime) keyCount=\(keys.count) sampleKeys=\(sampleKeys)")
    }

    nonisolated private static func debugSourceName(_ source: RemoteConfigSource) -> String {
        switch source {
        case .remote: return "remote"
        case .default: return "default"
        case .static: return "static"
        }
    }

    private static func debugFetchStatusName(_ status: RemoteConfigFetchStatus) -> String {
        switch status {
        case .noFetchYet: return "noFetchYet"
        case .success: return "success"
        case .failure: return "failure"
        case .throttled: return "throttled"
        }
    }

    private static func debugActivateStatusName(_ status: RemoteConfigFetchAndActivateStatus) -> String {
        switch status {
        case .successFetchedFromRemote: return "successFetchedFromRemote"
        case .successUsingPreFetchedData: return "successUsingPreFetchedData"
        case .error: return "error"
        }
    }
    #endif
}
