//
//  SettingsRemoteConfigService.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import Foundation

struct RemoteTeachingSubject {
    let title: String
    let subtopics: [String]
}

@MainActor
final class SettingsRemoteConfigService {
    static let shared = SettingsRemoteConfigService()
    
    private enum Key {
        static let aboutURL = "settings_about_url"
        static let supportEmail = "support_email"
        static let eulaURL = "eula_url"
        static let privacyPolicyURL = "privacy_policy"
        static let subjects = "subjects"
        static let defaultCommission = "default_commission"
        static let contactSupportTitleMaxLength = "contact_support_title_max_length"
        static let contactSupportDescriptionMaxLength = "contact_support_description_max_length"
    }
    
    private let defaultSupportEmail = "support@tim.app"
    private let defaultTeacherCommission = 0.25
    private let defaultContactSupportTitleMaxLength = 50
    private let defaultContactSupportDescriptionMaxLength = 1024
    
    private init() {}
    
    func fetchAboutURL() async throws -> URL {
        try await fetchURL(forKey: localizedKey(Key.aboutURL), missingError: .missingAboutURL)
    }

    func fetchEULAURL() async throws -> URL {
        try await fetchURL(forKey: localizedKey(Key.eulaURL), missingError: .missingLegalURL("EULA"))
    }

    func fetchPrivacyPolicyURL() async throws -> URL {
        try await fetchURL(forKey: localizedKey(Key.privacyPolicyURL), missingError: .missingLegalURL("Privacy policy"))
    }

    private func localizedKey(_ base: String) -> String {
        "\(base)_\(LocalizationSupport.currentLanguageCode)"
    }
    
    func fetchSupportEmail() async -> String {
        await RemoteConfigService.shared.ready()
        let rawValue = RemoteConfigService.shared.getString(Key.supportEmail)
        return rawValue.isEmpty ? defaultSupportEmail : rawValue
    }
    
    func fetchTeachingSubjects() async throws -> [RemoteTeachingSubject] {
        await RemoteConfigService.shared.ready()
        let subjects = RemoteConfigService.shared.getStringArray(Key.subjects)
        return subjects.map { subject in
            RemoteTeachingSubject(
                title: subject,
                subtopics: RemoteConfigService.shared.getStringArray(subtopicKey(for: subject))
            )
        }
    }
    
    func fetchDefaultCommission() async -> Double {
        await RemoteConfigService.shared.ready()
        let commission = RemoteConfigService.shared.getNumber(Key.defaultCommission)
        guard commission > 0 else {
            return defaultTeacherCommission
        }
        
        return min(max(commission, 0), 1)
    }

    func fetchContactSupportTitleMaxLength() async -> Int {
        await RemoteConfigService.shared.ready()
        let limit = Int(RemoteConfigService.shared.getNumber(Key.contactSupportTitleMaxLength))
        return limit > 0 ? limit : defaultContactSupportTitleMaxLength
    }

    func fetchContactSupportDescriptionMaxLength() async -> Int {
        await RemoteConfigService.shared.ready()
        let limit = Int(RemoteConfigService.shared.getNumber(Key.contactSupportDescriptionMaxLength))
        return limit > 0 ? limit : defaultContactSupportDescriptionMaxLength
    }
    
    private func fetchURL(forKey key: String, missingError: SettingsError) async throws -> URL {
        await RemoteConfigService.shared.ready()
        guard let url = RemoteConfigService.shared.getURL(key) else {
            throw missingError
        }
        
        return url
    }
    
    private func subtopicKey(for subject: String) -> String {
        let normalizedSubject = subject
            .filter { $0.isLetter || $0.isNumber }
        return "subTask\(normalizedSubject)"
    }
}

enum SettingsError: LocalizedError {
    case missingAboutURL
    case missingLegalURL(String)
    case missingUser
    
    var errorDescription: String? {
        switch self {
        case .missingAboutURL:
            return "About page is not configured yet."
        case .missingLegalURL(let title):
            return "\(title) URL is not configured yet."
        case .missingUser:
            return "No signed-in user was found."
        }
    }
}
