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
}

@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    private var firstFetch: Task<Void, Never>?

    private init() {}

    /// Configure Remote Config and kick off the first fetch.
    /// Call once at app launch. Subsequent reads are served from memory.
    func start() {
        guard firstFetch == nil else { return }
        configureRemoteConfig()
        firstFetch = Task { @MainActor in
            _ = try? await RemoteConfig.remoteConfig().fetchAndActivate()
        }
    }

    /// Await this when a caller needs to be sure the first fetch has completed.
    func ready() async {
        await firstFetch?.value
    }

    /// Force a refresh, ignoring the minimum fetch interval.
    func refresh() async {
        _ = try? await RemoteConfig.remoteConfig().fetchAndActivate()
    }

    private func configureRemoteConfig() {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 15
        remoteConfig.configSettings = settings
    }

    // MARK: - Sync accessors

    static func getLocalizedString(for key: RemoteConfigKey) -> String {
        shared.getLocalizedString(key.rawValue)
    }

    func getLocalizedString(_ key: String) -> String {
        let localizedKey = "\(key)_\(LocalizationSupport.currentLanguageCode)"
        return getString(localizedKey)
    }

    func getString(_ key: String) -> String {
        RemoteConfig.remoteConfig()
            .configValue(forKey: key)
            .stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}
