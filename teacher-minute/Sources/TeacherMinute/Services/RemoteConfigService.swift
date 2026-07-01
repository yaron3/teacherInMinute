//
//  RemoteConfigService.swift
//  teacher-minute
//

import Foundation

#if !os(Android)
import FirebaseRemoteConfig
#else
import SkipFirebaseRemoteConfig
#endif

enum RemoteConfigKey: String {
    case eulaURL = "eula_url"
    case privacyPolicyURL = "privacy_policy"
    case teacherIdGovIdDescription = "teacher_id_govid_description"
    case teacherIdCredentialsDescription = "teacher_id_credentials_description"
    case teacherIdSelfieDescription = "teacher_id_selfie_description"
}

@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    private var firstFetch: Task<Void, Never>?

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
                #if os(Android)
                Self.logFetchState(remoteConfig, context: "initial fetchAndActivate", activateStatus: status)
                #endif
            } catch {
                logger.error("[RemoteConfig] initial fetchAndActivate failed: \(error.localizedDescription)")
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
    func refresh() async {
        LocalizationManager.applyRemoteConfigLanguageSignal()
        #if os(Android)
        AndroidLocaleBridge.applyLanguageCode(LocalizationSupport.currentLanguageCode)
        #endif
        let remoteConfig = RemoteConfig.remoteConfig()
        #if os(Android)
        logger.info("[RemoteConfig][Android] refresh; language=\(LocalizationSupport.currentLanguageCode) locale=\(LocalizationSupport.currentLocale.identifier)")
        #endif
        do {
            let fetchStatus = try await remoteConfig.fetch(withExpirationDuration: 0)
            let activated = try await remoteConfig.activate()
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
        settings.fetchTimeout = 15
        remoteConfig.configSettings = settings
        #if os(Android)
        logger.info("[RemoteConfig][Android] configured; minimumFetchInterval=\(settings.minimumFetchInterval) fetchTimeout=\(settings.fetchTimeout)")
        #endif
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

    func getLocalizedString(_ key: String) -> String {
        let localizedKey = "\(key)_\(LocalizationSupport.currentLanguageCode)"
        return getString(localizedKey)
    }

    func getString(_ key: String) -> String {
        Self.readString(key)
    }

    /// Non-isolated read for callers (e.g. `LocalizationSupport.localized`) that
    /// run outside the main actor. Firebase Remote Config reads are thread-safe
    /// once `start()` has activated the initial fetch.
    nonisolated static func readString(_ key: String) -> String {
        let value = RemoteConfig.remoteConfig().configValue(forKey: key)
        let stringValue = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(Android)
        let source = Self.debugSourceName(value.source)
        logger.info("[RemoteConfig][Android] read key='\(key)' source=\(source) empty=\(stringValue.isEmpty) length=\(stringValue.count)")
        #endif
        return stringValue
    }

    func getNumber(_ key: String) -> Double {
        Double(getString(key)) ?? 0
    }

    func getBool(_ key: String) -> Bool {
        RemoteConfig.remoteConfig().configValue(forKey: key).boolValue
    }

    func getURL(_ key: String) -> URL? {
        let value = getString(key)
        guard !value.isEmpty,
              let url = URL(string: value),
              url.scheme != nil else { return nil }
        return url
    }

    func getStringArray(_ key: String) -> [String] {
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
