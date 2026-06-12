//
//  SettingsSection.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Observation
import Foundation
import SwiftUI

#if !os(Android)
import FirebaseRemoteConfig
import FirebaseAnalytics

#else
import SkipFirebaseRemoteConfig
import SkipFirebaseAnalytics
#endif


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
            self.destination = .contactUs
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
    case contactUs
    case webPage(title: String, url: URL)

    var title: String {
        switch self {
        case .accountSecurity: LocalizationSupport.localized("Account & Security")
        case .changePassword: LocalizationSupport.localized("Change Password")
        case .teacherPayouts: LocalizationSupport.localized("Teacher Payout Settings")
        case .studentPayments: LocalizationSupport.localized("Student Payment Methods")
        case .notifications: LocalizationSupport.localized("Notification Preferences")
        case .privacyControls: LocalizationSupport.localized("Privacy Controls")
        case .language: LocalizationSupport.localized("Language")
        case .about: LocalizationSupport.localized("About")
        case .contactUs: LocalizationSupport.localized("Contact Us")
        case .webPage(let title, _): title
        }
    }

    var placeholderMessage: String {
        switch self {
        case .changePassword:
            LocalizationSupport.localized("Password management will be available here.")
        case .teacherPayouts:
            LocalizationSupport.localized("Bank details and payout history will be available here.")
        case .studentPayments:
            LocalizationSupport.localized("Cards and billing history will be available here.")
        case .notifications:
            LocalizationSupport.localized("Notification preferences will be available here.")
        case .privacyControls:
            LocalizationSupport.localized("Privacy controls will be available here.")
        case .accountSecurity, .language, .about, .contactUs, .webPage:
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
        case .logOut: LocalizationSupport.localized("Log Out")
        case .deleteAccount: LocalizationSupport.localized("Delete Account")
        }
    }

    var message: String {
        switch self {
        case .logOut:
            LocalizationSupport.localized("Are you sure you want to log out?")
        case .deleteAccount:
            LocalizationSupport.localized("This permanently deletes your account and profile data. This cannot be undone.")
        }
    }

    var confirmTitle: String {
        switch self {
        case .logOut: LocalizationSupport.localized("Log Out")
        case .deleteAccount: LocalizationSupport.localized("Delete")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .logOut, .deleteAccount: true
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
    var appVersion: String {
        let appName = LocalizationSupport.localized("Teacher in a Minute App")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(appName) - \(version) (\(build))"
        case let (.some(version), .none):
            return "\(appName) - \(version)"
        case let (.none, .some(build)):
            return "\(appName) - \(build)"
        case (.none, .none):
            return appName
        }
    }
    var navigationPath: [SettingsDestination] = []
    var activeConfirmation: SettingsConfirmation?
    var externalURL: URL?
    var showAlert = false
    var alertTitle = LocalizationSupport.localized("Settings")
    var alertMessage: String?
    var isLoading = false
    var isOpeningPaymentSettings = false
    var isSavingPayoutSettings = false
    var isSubmittingContactSupport = false
    var teacherPayPalEmail = ""
    var contactSupportTitle = ""
    var contactSupportDescription = ""
    var contactSupportTitleMaxLength = 50
    var contactSupportDescriptionMaxLength = 1024
    var contactSupportPreview: ContactSupportRequest?
    var selectedLanguage: SettingsLanguageChoice
    private let authService: AuthService
    private let remoteConfigService: SettingsRemoteConfigService
	let role:AppUserMode
    init(
        authService: AuthService = AuthService(),
        remoteConfigService: SettingsRemoteConfigService = .shared,
		role: AppUserMode
    ) {
        self.authService = authService
        self.remoteConfigService = remoteConfigService
        let savedLanguage = UserDefaults.standard.string(forKey: LocalizationSupport.languagePreferenceKey)
        self.selectedLanguage = savedLanguage.flatMap(SettingsLanguageChoice.init(rawValue:)) ?? .system
				self.role = role
    }

    var sections: [SettingsSection] {
        [
		  
		  role == .teacher ? SettingsSection(
                title: LocalizationSupport.localized("PAYOUTS"),
                rows: [
				  
                    SettingsRow(
                        title: LocalizationSupport.localized("Teacher Payout Settings"),
                        subtitle: LocalizationSupport.localized("Update PayPal payout email"),
                        systemImage: "banknote.fill",
                        iconColor: .purple,
                        isDestructive: false,
                        action: .teacherPayouts
					)
					]
		  ): SettingsSection(
			title: LocalizationSupport.localized("PAYMENTS"),
			rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("Student Payment Methods"),
                        subtitle: LocalizationSupport.localized("PayPal at checkout"),
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false,
                        action: .studentPayments
                    )
                ]
            ),
            SettingsSection(
                title: LocalizationSupport.localized("PREFERENCES"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("Language"),
                        subtitle: selectedLanguage.title,
                        systemImage: "globe",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .language
                    ),
                    SettingsRow(
                        title: LocalizationSupport.localized("Notification Preferences"),
                        subtitle: nil,
                        systemImage: "bell.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .notifications
                    ),
                    SettingsRow(
                        title: LocalizationSupport.localized("Privacy Controls"),
                        subtitle: nil,
                        systemImage: "shield.lefthalf.filled",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .privacyControls
                    )
                ]
            ),
            SettingsSection(
                title: LocalizationSupport.localized("ABOUT"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("About"),
                        subtitle: nil,
                        systemImage: "doc.text.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .about
                    )
                ]
            ),
			SettingsSection(
			  title: LocalizationSupport.localized("ACCOUNT"),
			  rows: [
				SettingsRow(
				  title: LocalizationSupport.localized("Account & Security"),
				  subtitle: LocalizationSupport.localized("Password, logout and account removal"),
				  systemImage: "lock.fill",
				  iconColor: .primary,
				  isDestructive: false,
				  action: .accountSecurity
				)
			  ]
			)
        ]
    }

    var accountSecuritySection: SettingsSection {
        SettingsSection(
            title: LocalizationSupport.localized("ACCOUNT & SECURITY"),
            rows: [
                SettingsRow(
                    title: LocalizationSupport.localized("Change Password"),
                    subtitle: nil,
                    systemImage: "lock.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .changePassword
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Log Out"),
                    subtitle: nil,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    iconColor: .red,
                    isDestructive: true,
                    action: .logOut
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Delete Account"),
                    subtitle: LocalizationSupport.localized("Permanently remove your account"),
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
            title: LocalizationSupport.localized("ABOUT"),
            rows: [
                SettingsRow(
                    title: LocalizationSupport.localized("Contact Us"),
                    subtitle: nil,
                    systemImage: "envelope.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .contactUs
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("EULA"),
                    subtitle: nil,
                    systemImage: "doc.plaintext.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .eula
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Privacy Policy"),
                    subtitle: nil,
                    systemImage: "hand.raised.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .privacyPolicy
                )
            ]
        )
    }
  
  func updateLanguage(_ language: SettingsLanguageChoice) {
    selectedLanguage = language
	Analytics.setUserProperty(language.remoteConfigLanguageCode, forName: "app_language")
    let managerCode = localizationManagerCode(for: language)
    Task {
      await LocalizationManager.shared.updateLanguageCode(to: managerCode)
      // Write the @AppStorage-observed key only after Remote Config has the
      // new translations cached, so the root view's locale/layout flip and
      // the localized text refresh happen in the same render pass.
      UserDefaults.standard.set(language.rawValue, forKey: LocalizationSupport.languagePreferenceKey)
    }
  }

  /// Bridges `SettingsLanguageChoice` to the `LocalizationManager` convention
  /// where empty string means "follow system" and an ISO code pins the
  /// language. Keeping it private to this view-model avoids leaking the new
  /// manager's vocabulary into the rest of the settings layer.
  private func localizationManagerCode(for language: SettingsLanguageChoice) -> String {
    switch language {
    case .system: return ""
    case .english: return "en"
    case .hebrew: return "he"
    }
  }

    func select(_ row: SettingsRow) {
        switch row.action {
        case .accountSecurity:
            navigationPath.append(.accountSecurity)
        case .changePassword:
            sendPasswordReset()
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
            navigationPath.append(.contactUs)
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

    func sendPasswordReset() {
        guard let email = authService.currentUserEmail, !email.isEmpty else {
            present(title: LocalizationSupport.localized("Change Password"), message: LocalizationSupport.localized("No email address is attached to this account."))
            return
        }
        Task {
            do {
                try await authService.sendPasswordReset(email: email)
                AnalyticsService.shared.logEvent(AnalyticsEvent.passwordResetSent, parameters: ["method": "email"])
                present(title: LocalizationSupport.localized("Change Password"), message: LocalizationSupport.localized("Password reset email sent."))
            } catch {
                present(title: LocalizationSupport.localized("Change Password"), message: error.localizedDescription)
            }
        }
    }

    func openPaymentSettings() {
        guard !isOpeningPaymentSettings else { return }
        isOpeningPaymentSettings = true

        Task {
            defer { isOpeningPaymentSettings = false }
            do {
                let result = try await FunctionsService.shared.createPaymentSettingsSession()
                externalURL = result.settingsURL
            } catch {
                alertTitle = LocalizationSupport.localized("Payments")
                alertMessage = LocalizationSupport.localized("Could not open payment settings.")
                showAlert = true
                logger.error("[Settings] failed creating payment settings session: \(error.localizedDescription)")
                AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Settings.createPaymentSettingsSession")
            }
        }
    }

    func loadTeacherPayoutSettings() async {
        guard role == .teacher, let uid = authService.currentUserID else { return }
        do {
            let data = try await UserService.shared.fetchRaw(uid: uid) ?? [:]
            teacherPayPalEmail = data["paypalEmail"] as? String ?? ""
        } catch {
            present(title: LocalizationSupport.localized("Teacher Payout Settings"), message: LocalizationSupport.localized("Could not load PayPal payout settings."))
            logger.error("[Settings] failed loading teacher payout settings: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Settings.loadTeacherPayoutSettings")
        }
    }

    func saveTeacherPayoutSettings() {
        guard !isSavingPayoutSettings else { return }
        let trimmedEmail = teacherPayPalEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.isEmail else {
            present(title: LocalizationSupport.localized("Teacher Payout Settings"), message: LocalizationSupport.localized("Enter a valid PayPal email address."))
            return
        }
        guard let uid = authService.currentUserID else {
            present(message: SettingsError.missingUser.localizedDescription)
            return
        }

        isSavingPayoutSettings = true
        Task {
            defer { isSavingPayoutSettings = false }
            do {
                try await UserService.shared.updateProfileFields(uid: uid, fields: [
                    "paypalEmail": trimmedEmail,
                    "updatedAt": ISO8601DateFormatter().string(from: Date())
                ])
                teacherPayPalEmail = trimmedEmail
                present(title: LocalizationSupport.localized("Teacher Payout Settings"), message: LocalizationSupport.localized("PayPal payout email updated."))
            } catch {
                present(title: LocalizationSupport.localized("Teacher Payout Settings"), message: LocalizationSupport.localized("Could not update PayPal payout settings."))
                logger.error("[Settings] failed saving teacher payout settings: \(error.localizedDescription)")
                AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Settings.saveTeacherPayoutSettings")
            }
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
        } catch (let error){
            present(
                title: LocalizationSupport.localized("Delete Account"),
                message: "\(error.localizedDescription) " + LocalizationSupport.localized("You may need to log in again before deleting your account.")
            )
			Analytics.logEvent("Delete Account error", parameters: ["error" : error])
            return false
        }
    }
    
    func logOut() -> Bool {
        do {
            try authService.signOut()
            return true
        } catch {
            present(title: LocalizationSupport.localized("Log Out"), message: error.localizedDescription)
            return false
        }
    }
    
    func contactSupportAppeared() {
        AnalyticsService.shared.logEvent(AnalyticsEvent.contactSupportOpened, parameters: ["role": roleAnalyticsValue])
        Task { await loadContactSupportLimits() }
    }

    func updateContactSupportTitle(_ value: String) {
        contactSupportTitle = String(value.prefix(contactSupportTitleMaxLength))
    }

    func updateContactSupportDescription(_ value: String) {
        contactSupportDescription = String(value.prefix(contactSupportDescriptionMaxLength))
    }

    func loadContactSupportLimits() async {
        let titleLimit = await remoteConfigService.fetchContactSupportTitleMaxLength()
        let descriptionLimit = await remoteConfigService.fetchContactSupportDescriptionMaxLength()
        contactSupportTitleMaxLength = titleLimit
        contactSupportDescriptionMaxLength = descriptionLimit
        updateContactSupportTitle(contactSupportTitle)
        updateContactSupportDescription(contactSupportDescription)
    }

    func previewContactSupport() {
        let title = contactSupportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = contactSupportDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !description.isEmpty else {
            present(title: LocalizationSupport.localized("Contact Us"), message: LocalizationSupport.localized("Add a title and description before submitting."))
            return
        }
        guard let uid = authService.currentUserID else {
            present(message: SettingsError.missingUser.localizedDescription)
            return
        }

        AnalyticsService.shared.logEvent(AnalyticsEvent.contactSupportPreview, parameters: ["role": roleAnalyticsValue])
        isLoading = true
        Task {
            defer { isLoading = false }
            let userData = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
            let name = userDisplayName(from: userData)
            contactSupportPreview = ContactSupportService.shared.makeRequest(
                title: title,
                description: description,
                userID: uid,
                userName: name,
                userEmail: authService.currentUserEmail ?? userData["email"] as? String ?? "",
                role: role
            )
        }
    }

    func cancelContactSupportPreview() {
        contactSupportPreview = nil
        AnalyticsService.shared.logEvent(AnalyticsEvent.contactSupportCancelled, parameters: ["role": roleAnalyticsValue])
    }

    func submitContactSupport() {
        guard let request = contactSupportPreview, !isSubmittingContactSupport else { return }
        isSubmittingContactSupport = true
        Task {
            defer { isSubmittingContactSupport = false }
            do {
                try await ContactSupportService.shared.save(request)
                AnalyticsService.shared.logEvent(AnalyticsEvent.contactSupportSubmitted, parameters: [
                    "role": roleAnalyticsValue,
                    "request_id": request.id
                ])
                contactSupportPreview = nil
                contactSupportTitle = ""
                contactSupportDescription = ""
                if navigationPath.last == .contactUs {
                    navigationPath.removeLast()
                }
                present(title: LocalizationSupport.localized("Contact Us"), message: LocalizationSupport.localized("Your message was sent."))
            } catch {
                AnalyticsService.shared.logEvent(AnalyticsEvent.contactSupportFailed, parameters: [
                    "role": roleAnalyticsValue,
                    "reason": error.localizedDescription
                ])
                AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Settings.submitContactSupport")
                present(title: LocalizationSupport.localized("Contact Us"), message: LocalizationSupport.localized("Could not send your message."))
            }
        }
    }

    func openEULA() async {
        let title = LocalizationSupport.localized("EULA")
        isLoading = true
        defer { isLoading = false }

        do {
            let url = try await remoteConfigService.fetchEULAURL()
            navigationPath.append(.webPage(title: title, url: url))
        } catch {
            present(title: title, message: error.localizedDescription)
        }
    }

    func openPrivacyPolicy() async {
        await openRemoteWebPage(title: LocalizationSupport.localized("Privacy Policy")) {
            try await remoteConfigService.fetchPrivacyPolicyURL()
        }
    }

    func openAbout() async {
        await openRemoteWebPage(title: LocalizationSupport.localized("About")) {
            try await remoteConfigService.fetchAboutURL()
        }
    }
    
    func present(title: String = LocalizationSupport.localized("Settings"), message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    func consumeExternalURL() {
        externalURL = nil
    }

    private var roleAnalyticsValue: String {
        role == .teacher ? "teacher" : "student"
    }

    private func userDisplayName(from data: [String: Any]) -> String {
        let fullName = data["fullName"] as? String ?? ""
        if !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fullName
        }
        return authService.currentUserEmail ?? LocalizationSupport.localized("Unknown")
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
        remoteConfigService: SettingsRemoteConfigService = .shared,
		role: AppUserMode
    ) {
	  super.init(authService: authService, remoteConfigService: remoteConfigService, role: role)
    }

    override func confirm(_ confirmation: SettingsConfirmation) async -> Bool {
        switch confirmation {
        case .logOut:
            return true
        case .deleteAccount:
            present(title: LocalizationSupport.localized("Delete Account"), message: LocalizationSupport.localized("Preview only. No account was deleted."))
            return false
        }
    }

    override func logOut() -> Bool {
        true
    }

    override func deleteAccount() async -> Bool {
        present(title: LocalizationSupport.localized("Delete Account"), message: LocalizationSupport.localized("Preview only. No account was deleted."))
        return false
    }

    override func openEULA() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("EULA"), url: previewURL(path: "eula")))
    }

    override func openPrivacyPolicy() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("Privacy Policy"), url: previewURL(path: "privacy")))
    }

    override func openAbout() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("About"), url: previewURL(path: "about")))
    }

    private func previewURL(path: String) -> URL {
        URL(string: "https://example.com/\(path)") ?? URL(fileURLWithPath: "/")
    }
}
