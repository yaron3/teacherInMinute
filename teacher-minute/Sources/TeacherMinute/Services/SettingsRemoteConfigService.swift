//
//  SettingsRemoteConfigService.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import Foundation

#if !os(Android)
import FirebaseRemoteConfig
#else
import SkipFirebaseRemoteConfig
#endif

struct RemoteTeachingSubject {
    let title: String
    let subtopics: [String]
}

@MainActor
final class SettingsRemoteConfigService {
    static let shared = SettingsRemoteConfigService()
    
    private enum Key {
        static let aboutURL = "settings_about_url"
        static let subjects = "subjects"
        static let baseURL = "baseURL"
    }
    
    private let defaultBaseURL = "https://us-central1-teacher-in-a-moment.cloudfunctions.net"
    
    private init() {}
    
    func fetchAboutURL() async throws -> URL {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 15
        remoteConfig.configSettings = settings
        
        _ = try await remoteConfig.fetchAndActivate()
        let rawValue = remoteConfig
            .configValue(forKey: Key.aboutURL)
            .stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: rawValue), url.scheme != nil else {
            throw SettingsError.missingAboutURL
        }
        
        return url
    }
    
    func fetchTeachingSubjects() async throws -> [RemoteTeachingSubject] {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 15
        remoteConfig.configSettings = settings
        
        _ = try await remoteConfig.fetchAndActivate()
        
        let subjects = stringArray(from: remoteConfig.configValue(forKey: Key.subjects))
        return subjects.map { subject in
            RemoteTeachingSubject(
                title: subject,
                subtopics: stringArray(from: remoteConfig.configValue(forKey: subtopicKey(for: subject)))
            )
        }
    }
    
    func fetchBaseURL() async -> URL {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 15
        remoteConfig.configSettings = settings
        
        _ = try? await remoteConfig.fetchAndActivate()
        
        let rawValue = remoteConfig
            .configValue(forKey: Key.baseURL)
            .stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = rawValue.isEmpty ? defaultBaseURL : rawValue
        return URL(string: urlString) ?? URL(string: defaultBaseURL)!
    }
    
    private func subtopicKey(for subject: String) -> String {
        let normalizedSubject = subject
            .filter { $0.isLetter || $0.isNumber }
        return "subTask\(normalizedSubject)"
    }
    
    private func stringArray(from value: RemoteConfigValue) -> [String] {
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

enum SettingsError: LocalizedError {
    case missingAboutURL
    case missingUser
    
    var errorDescription: String? {
        switch self {
        case .missingAboutURL:
            return "About page is not configured yet."
        case .missingUser:
            return "No signed-in user was found."
        }
    }
}
