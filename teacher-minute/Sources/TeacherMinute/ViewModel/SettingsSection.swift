//
//  SettingsSection.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Observation
import Foundation
import SwiftUI

struct SettingsSection: Identifiable {
    let title: String
    let rows: [SettingsRow]
    
    var id: String { title }
}

struct SettingsRow: Identifiable {
    let title: String
    let subtitle: String?
    let systemImage: String
    let iconColor: Color
    let isDestructive: Bool
    let action: SettingsAction
    let destination: SettingsDestination?

    var id: String { "\(title)-\(action.id)" }

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconColor: Color,
        isDestructive: Bool = false,
        action: SettingsAction
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.isDestructive = isDestructive
        self.action = action
        // Map actions that have in-stack destinations to SettingsDestination
        switch action {
        case .accountSecurity:
			self.destination = .accountSecurity
			logger.info("\(#fileID) \(#function): \(#file): \(#line)")
        case .changePassword:  self.destination = .changePassword
        case .teacherPayouts:  self.destination = .teacherPayouts
        case .studentPayments: self.destination = .studentPayments
        case .notifications:   self.destination = .notifications
        case .privacyControls: self.destination = .privacyControls
        case .language:        self.destination = .language
        case .about:           self.destination = .about
        case .eula:
            // EULA/PrivacyPolicy are opened via remote URL; keep destination nil so viewModel handles it
            self.destination = nil
        case .privacyPolicy:
            self.destination = nil
        case .contactUs:
            self.destination = nil
        case .logOut, .deleteAccount:
            // Destructive actions handled via confirmation; no navigation
            self.destination = nil
        }
    }
}

enum SettingsAction: Equatable {
    case accountSecurity
    case changePassword
    case logOut
    case deleteAccount
    case teacherPayouts
    case studentPayments
    case notifications
    case privacyControls
    case language
    case about
    case contactUs
    case eula
    case privacyPolicy
    
    var id: String {
        switch self {
        case .accountSecurity: "accountSecurity"
        case .changePassword: "changePassword"
        case .logOut: "logOut"
        case .deleteAccount: "deleteAccount"
        case .teacherPayouts: "teacherPayouts"
        case .studentPayments: "studentPayments"
        case .notifications: "notifications"
        case .privacyControls: "privacyControls"
        case .language: "language"
        case .about: "about"
        case .contactUs: "contactUs"
        case .eula: "eula"
        case .privacyPolicy: "privacyPolicy"
        }
    }
}

enum SettingsDestination: Hashable {
    case accountSecurity
    case changePassword
    case teacherPayouts
    case studentPayments
    case notifications
    case privacyControls
    case language
    case about
    case webPage(title: String, url: URL)

    var title: String {
        switch self {
        case .accountSecurity: "Account & Security"
        case .changePassword: "Change Password"
        case .teacherPayouts: "Teacher Payout Settings"
        case .studentPayments: "Student Payment Methods"
        case .notifications: "Notification Preferences"
        case .privacyControls: "Privacy Controls"
        case .language: "Language"
        case .about: "About"
        case .webPage(let title, _): title
        }
    }

    var placeholderMessage: String {
        switch self {
        case .changePassword:
            "Password management will be available here."
        case .teacherPayouts:
            "Bank details and payout history will be available here."
        case .studentPayments:
            "Cards and billing history will be available here."
        case .notifications:
            "Notification preferences will be available here."
        case .privacyControls:
            "Privacy controls will be available here."
        case .accountSecurity, .language, .about, .webPage:
            ""
        }
    }
}

enum SettingsConfirmation: Identifiable {
    case logOut
    case deleteAccount

    var id: String {
        switch self {
        case .logOut: "logOut"
        case .deleteAccount: "deleteAccount"
        }
    }

    var title: String {
        switch self {
        case .logOut: "Log Out"
        case .deleteAccount: "Delete Account"
        }
    }

    var message: String {
        switch self {
        case .logOut:
            "Are you sure you want to log out?"
        case .deleteAccount:
            "This permanently deletes your account and profile data. This cannot be undone."
        }
    }

    var confirmTitle: String {
        switch self {
        case .logOut: "Log Out"
        case .deleteAccount: "Delete"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .logOut, .deleteAccount: true
        }
    }
}

enum SettingsLanguageChoice: String, CaseIterable, Identifiable {
    case system
    case english
    case hebrew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Language"
        case .english: "English"
        case .hebrew: "Hebrew"
        }
    }

    var subtitle: String? {
        switch self {
        case .system: "Use the device language"
        case .english, .hebrew: nil
        }
    }
}

//enum SettingsIconColor {
//    case primary
//    case pink
//    case purple
//    case red
//
//    var foregroundColor: Color {
//        switch self {
//        case .primary: .appPrimaryText
//        case .pink: .appPink
//        case .purple: .appPurple
//        case .red: .red
//        }
//    }
//
//    var backgroundColor: Color {
//        switch self {
//        case .primary: .appGrayBackground
//        case .pink: .appPinkSoft
//        case .purple: .appPurpleSoft
//        case .red: .red.opacity(0.08)
//        }
//    }
//}

@Observable
@MainActor
class SettingsViewModel {
    let appVersion = "Math Connect App v2.4.1"
    
    var navigationPath: [SettingsDestination] = []
    var activeConfirmation: SettingsConfirmation?
    var externalURL: URL?
    var showAlert = false
    var alertTitle = "Settings"
    var alertMessage: String?
    var isLoading = false
    var selectedLanguage: SettingsLanguageChoice {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: languagePreferenceKey)
        }
    }
    
    private let authService: AuthService
    private let remoteConfigService: SettingsRemoteConfigService
    private let languagePreferenceKey = "settings.language.preference"
    
    init(
        authService: AuthService = AuthService(),
        remoteConfigService: SettingsRemoteConfigService = .shared
    ) {
        self.authService = authService
        self.remoteConfigService = remoteConfigService
        let savedLanguage = UserDefaults.standard.string(forKey: languagePreferenceKey)
        self.selectedLanguage = savedLanguage.flatMap(SettingsLanguageChoice.init(rawValue:)) ?? .system
    }

    var sections: [SettingsSection] {
        [
            SettingsSection(
                title: "ACCOUNT",
                rows: [
                    SettingsRow(
                        title: "Account & Security",
                        subtitle: "Password, logout and account removal",
                        systemImage: "lock.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .accountSecurity
                    )
                ]
            ),
            SettingsSection(
                title: "PAYMENTS & PAYOUTS",
                rows: [
                    SettingsRow(
                        title: "Teacher Payout Settings",
                        subtitle: "Manage bank details & history",
                        systemImage: "banknote.fill",
                        iconColor: .purple,
                        isDestructive: false,
                        action: .teacherPayouts
                    ),
                    SettingsRow(
                        title: "Student Payment Methods",
                        subtitle: "Cards & billing history",
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false,
                        action: .studentPayments
                    )
                ]
            ),
            SettingsSection(
                title: "PREFERENCES",
                rows: [
                    SettingsRow(
                        title: "Language",
                        subtitle: selectedLanguage.title,
                        systemImage: "globe",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .language
                    ),
                    SettingsRow(
                        title: "Notification Preferences",
                        subtitle: nil,
                        systemImage: "bell.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .notifications
                    ),
                    SettingsRow(
                        title: "Privacy Controls",
                        subtitle: nil,
                        systemImage: "shield.lefthalf.filled",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .privacyControls
                    )
                ]
            ),
            SettingsSection(
                title: "ABOUT",
                rows: [
                    SettingsRow(
                        title: "About",
                        subtitle: nil,
                        systemImage: "doc.text.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .about
                    )
                ]
            )
        ]
    }

    var accountSecuritySection: SettingsSection {
        SettingsSection(
            title: "ACCOUNT & SECURITY",
            rows: [
                SettingsRow(
                    title: "Change Password",
                    subtitle: nil,
                    systemImage: "lock.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .changePassword
                ),
                SettingsRow(
                    title: "Log Out",
                    subtitle: nil,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    iconColor: .red,
                    isDestructive: true,
                    action: .logOut
                ),
                SettingsRow(
                    title: "Delete Account",
                    subtitle: "Permanently remove your account",
                    systemImage: "trash.fill",
                    iconColor: .red,
                    isDestructive: true,
                    action: .deleteAccount
                )
            ]
        )
    }

    var aboutSection: SettingsSection {
        SettingsSection(
            title: "ABOUT",
            rows: [
                SettingsRow(
                    title: "Contact Us",
                    subtitle: nil,
                    systemImage: "envelope.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .contactUs
                ),
                SettingsRow(
                    title: "EULA",
                    subtitle: nil,
                    systemImage: "doc.plaintext.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .eula
                ),
                SettingsRow(
                    title: "Privacy Policy",
                    subtitle: nil,
                    systemImage: "hand.raised.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .privacyPolicy
                )
            ]
        )
    }

    func select(_ row: SettingsRow) {
        switch row.action {
        case .accountSecurity:
            navigationPath.append(.accountSecurity)
        case .changePassword:
            navigationPath.append(.changePassword)
        case .teacherPayouts:
            navigationPath.append(.teacherPayouts)
        case .studentPayments:
            navigationPath.append(.studentPayments)
        case .notifications:
            navigationPath.append(.notifications)
        case .privacyControls:
            navigationPath.append(.privacyControls)
        case .language:
            navigationPath.append(.language)
        case .about:
            navigationPath.append(.about)
        case .contactUs:
            Task { await openContactSupport() }
        case .eula:
            Task { await openEULA() }
        case .privacyPolicy:
            Task { await openPrivacyPolicy() }
        case .logOut:
            activeConfirmation = .logOut
        case .deleteAccount:
            activeConfirmation = .deleteAccount
        }
    }
    
    func confirm(_ confirmation: SettingsConfirmation) async -> Bool {
        switch confirmation {
        case .logOut:
            return logOut()
        case .deleteAccount:
            return await deleteAccount()
        }
    }
    
    func deleteAccount() async -> Bool {
        guard let uid = authService.currentUserID else {
            present(message: SettingsError.missingUser.localizedDescription)
            return false
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await UserService.shared.deleteUserData(uid: uid)
            try await authService.deleteCurrentUser()
            return true
        } catch {
            present(
                title: "Delete Account",
                message: "\(error.localizedDescription) You may need to log in again before deleting your account."
            )
            return false
        }
    }
    
    func logOut() -> Bool {
        do {
            try authService.signOut()
            return true
        } catch {
            present(title: "Log Out", message: error.localizedDescription)
            return false
        }
    }
    
    func openContactSupport() async {
        isLoading = true
        defer { isLoading = false }

        let email = await remoteConfigService.fetchSupportEmail()
        guard let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "mailto:\(encodedEmail)") else {
            present(title: "Contact Us", message: "Support email is not configured correctly.")
            return
        }

        externalURL = url
    }

    func openEULA() async {
        await openRemoteWebPage(title: "EULA") {
            try await remoteConfigService.fetchEULAURL()
        }
    }

    func openPrivacyPolicy() async {
        await openRemoteWebPage(title: "Privacy Policy") {
            try await remoteConfigService.fetchPrivacyPolicyURL()
        }
    }

    func openAbout() async {
        await openRemoteWebPage(title: "About") {
            try await remoteConfigService.fetchAboutURL()
        }
    }
    
    func present(title: String = "Settings", message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    func consumeExternalURL() {
        externalURL = nil
    }

    private func openRemoteWebPage(title: String, fetchURL: () async throws -> URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            navigationPath.append(.webPage(title: title, url: try await fetchURL()))
        } catch {
            present(title: title, message: error.localizedDescription)
        }
    }
}

@MainActor
final class MockSettingsViewModel: SettingsViewModel {
    override init(
        authService: AuthService = AuthService(),
        remoteConfigService: SettingsRemoteConfigService = .shared
    ) {
        super.init(authService: authService, remoteConfigService: remoteConfigService)
    }

    override func confirm(_ confirmation: SettingsConfirmation) async -> Bool {
        switch confirmation {
        case .logOut:
            return true
        case .deleteAccount:
            present(title: "Delete Account", message: "Preview only. No account was deleted.")
            return false
        }
    }

    override func logOut() -> Bool {
        true
    }

    override func deleteAccount() async -> Bool {
        present(title: "Delete Account", message: "Preview only. No account was deleted.")
        return false
    }

    override func openContactSupport() async {
        externalURL = URL(string: "mailto:support@tim.app")
    }

    override func openEULA() async {
        navigationPath.append(.webPage(title: "EULA", url: previewURL(path: "eula")))
    }

    override func openPrivacyPolicy() async {
        navigationPath.append(.webPage(title: "Privacy Policy", url: previewURL(path: "privacy")))
    }

    override func openAbout() async {
        navigationPath.append(.webPage(title: "About", url: previewURL(path: "about")))
    }

    private func previewURL(path: String) -> URL {
        URL(string: "https://example.com/\(path)") ?? URL(fileURLWithPath: "/")
    }
}

