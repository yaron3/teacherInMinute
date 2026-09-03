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
        case .appPreferences:  self.destination = .appPreferences
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
        #if DEBUG
        case .forceReloadRemoteConfig:
            self.destination = nil
        case .testCrashlyticsCrash:
            self.destination = nil
        #endif
        case .logOut, .deleteAccount:
            // Destructive actions handled via confirmation; no navigation
            self.destination = nil
        }
    }
}

enum SettingsAction: Equatable {
    case accountSecurity
    case appPreferences
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
    #if DEBUG
    case forceReloadRemoteConfig
    case testCrashlyticsCrash
    #endif
    
    var id: String {
        switch self {
        case .accountSecurity: "accountSecurity"
        case .appPreferences: "appPreferences"
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
        #if DEBUG
        case .forceReloadRemoteConfig: "forceReloadRemoteConfig"
        case .testCrashlyticsCrash: "testCrashlyticsCrash"
        #endif
        }
    }
}

enum SettingsDestination: Hashable {
    case accountSecurity
    case appPreferences
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
        case .appPreferences: LocalizationSupport.localized("Preferences")
        case .changePassword: LocalizationSupport.localized("Change Password")
        case .teacherPayouts: LocalizationSupport.localized("Teacher Payout Settings")
        case .studentPayments: LocalizationSupport.localized("Payment History")
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
        case .accountSecurity, .appPreferences, .language, .about, .contactUs, .webPage:
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

// MARK: - ViewModel Protocol

@MainActor
protocol SettingsViewModeling: AnyObject {
    var role: AppUserMode { get }

    var navigationPath: [SettingsDestination] { get set }
    var activeConfirmation: SettingsConfirmation? { get set }
    var externalURL: URL? { get set }
    var showAlert: Bool { get set }
    var alertTitle: String { get set }
    var alertMessage: String? { get set }
    var isLoading: Bool { get set }
    var showReauthPasswordPrompt: Bool { get set }
    var reauthPassword: String { get set }
    var isOpeningPaymentSettings: Bool { get set }
    var isSubmittingContactSupport: Bool { get set }
    var contactSupportTitle: String { get set }
    var contactSupportDescription: String { get set }
    var contactSupportTitleMaxLength: Int { get set }
    var contactSupportDescriptionMaxLength: Int { get set }
    var contactSupportPreview: ContactSupportRequest? { get set }
    var selectedLanguage: SettingsLanguageChoice { get set }

    func select(_ row: SettingsRow)
    func confirm(_ confirmation: SettingsConfirmation) async -> Bool
    func updateLanguage(_ language: SettingsLanguageChoice)
    func sendPasswordReset()
    func openPaymentSettings()
    func deleteAccount() async -> Bool
    func completeAccountDeletion(withPassword password: String) async -> Bool
    func logOut() -> Bool
    func contactSupportAppeared()
    func updateContactSupportTitle(_ value: String)
    func updateContactSupportDescription(_ value: String)
    func loadContactSupportLimits() async
    func previewContactSupport()
    func cancelContactSupportPreview()
    func submitContactSupport()
    func openEULA() async
    func openPrivacyPolicy() async
    func openAbout() async
    func present(title: String, message: String)
    func consumeExternalURL()

    #if DEBUG
    func forceReloadRemoteConfig() async
    #endif
}

// MARK: - Default Sections & Navigation

extension SettingsViewModeling {

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

    var preferenceRows: [SettingsRow] {
        var rows = [
            SettingsRow(
                title: LocalizationSupport.localized("Preferences"),
                subtitle: role == .teacher
                    ? LocalizationSupport.localized("Currency")
                    : LocalizationSupport.localized("Default session type and currency"),
                systemImage: "slider.horizontal.3",
                iconColor: .primary,
                isDestructive: false,
                action: .appPreferences
            ),
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

        #if DEBUG
        rows.append(
            SettingsRow(
                title: LocalizationSupport.localized("Force Reload Remote Config"),
                subtitle: LocalizationSupport.localized("Debug builds only"),
                systemImage: "arrow.clockwise",
                iconColor: .primary,
                isDestructive: false,
                action: .forceReloadRemoteConfig
            )
        )
        rows.append(
            SettingsRow(
                title: LocalizationSupport.localized("Test Crashlytics Crash"),
                subtitle: LocalizationSupport.localized("Debug builds only"),
                systemImage: "exclamationmark.triangle.fill",
                iconColor: .red,
                isDestructive: true,
                action: .testCrashlyticsCrash
            )
        )
        #endif

        return rows
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
                        title: LocalizationSupport.localized("Payment History"),
                        subtitle: LocalizationSupport.localized("View your lesson payment history"),
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false,
                        action: .studentPayments
                    )
                ]
            ),
            SettingsSection(
                title: LocalizationSupport.localized("PREFERENCES"),
                rows: preferenceRows
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

    /// Row routing is identical for the live and mock view models — only the
    /// handlers they land on differ — so it lives here and both inherit it.
    func select(_ row: SettingsRow) {
        switch row.action {
        case .accountSecurity:
            navigationPath.append(.accountSecurity)
        case .appPreferences:
            navigationPath.append(.appPreferences)
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
        #if DEBUG
        case .forceReloadRemoteConfig:
            Task { await forceReloadRemoteConfig() }
        case .testCrashlyticsCrash:
            AnalyticsService.shared.triggerCrashlyticsTestCrash()
        #endif
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

    func present(message: String) {
        present(title: settingsTitle, message: message)
    }
}

// MARK: - Default Localized Strings

extension SettingsViewModeling {

    // MARK: Screen titles
    var settingsTitle: String { LocalizationSupport.localized("Settings") }
    var previewTitle: String { LocalizationSupport.localized("Preview") }

    // MARK: Generic button labels
    var okLabel: String { LocalizationSupport.localized("OK") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }
    var deleteLabel: String { LocalizationSupport.localized("Delete") }
    var sendLabel: String { LocalizationSupport.localized("Send") }

    // MARK: Account deletion
    var deleteAccountTitle: String { LocalizationSupport.localized("Delete Account") }
    var passwordPlaceholder: String { LocalizationSupport.localized("Password") }
    var reauthPasswordMessage: String {
        LocalizationSupport.localized("Enter your password to confirm account deletion.")
    }
    var previewOnlyDeleteMessage: String {
        LocalizationSupport.localized("Preview only. No account was deleted.")
    }

    // MARK: Contact support
    var contactSupportIntroText: String {
        LocalizationSupport.localized("Send a message to support. You will preview the data before it is sent.")
    }
    var contactSupportTitleSectionTitle: String { LocalizationSupport.localized("Title") }
    var contactSupportTitlePlaceholder: String { LocalizationSupport.localized("What can we help with?") }
    var contactSupportDescriptionSectionTitle: String { LocalizationSupport.localized("Description") }
    var contactSupportSubmitLabel: String { LocalizationSupport.localized("Preview and Submit") }
    var contactSupportPreviewSectionTitle: String { LocalizationSupport.localized("Data to be sent") }
    var contactSupportTitleCounterText: String {
        "\(contactSupportTitle.count)/\(contactSupportTitleMaxLength)"
    }
    var contactSupportDescriptionCounterText: String {
        "\(contactSupportDescription.count)/\(contactSupportDescriptionMaxLength)"
    }

    // MARK: Payment history
    var noPaymentsTitle: String { LocalizationSupport.localized("No payments yet") }
    var noPaymentsSubtitle: String { LocalizationSupport.localized("Your lesson payments will appear here.") }

    // MARK: Change password
    var changePasswordIntroText: String {
        LocalizationSupport.localized("Send a password reset email to the email address on this account.")
    }
    var sendResetEmailLabel: String { LocalizationSupport.localized("Send Reset Email") }

    // MARK: Notification preferences
    var systemPermissionSectionTitle: String { LocalizationSupport.localized("System Permission") }
    var pushNotificationsLabel: String { LocalizationSupport.localized("Push Notifications") }
    var notificationsSectionTitle: String { LocalizationSupport.localized("Notifications") }
    var incomingMessageNotificationLabel: String {
        role == .student
            ? LocalizationSupport.localized("Notify me when a teacher sends an incoming message")
            : LocalizationSupport.localized("Notify me when a student sends an incoming message")
    }
    var generalAnnouncementsNotificationLabel: String {
        LocalizationSupport.localized("Notify me about general announcements")
    }
    var enableNotificationsLabel: String { LocalizationSupport.localized("Enable Notifications") }
    var openSystemSettingsLabel: String { LocalizationSupport.localized("Open System Settings") }

    // MARK: App preferences
    var defaultSessionTypeSectionTitle: String { LocalizationSupport.localized("Default Session Type") }
    var defaultSessionTypeFooterText: String {
        LocalizationSupport.localized("This session type is preselected when you ask a teacher a question. You can still change it for each question.")
    }
    var currencySectionTitle: String { LocalizationSupport.localized("Currency") }
    var currencyFooterText: String {
        LocalizationSupport.localized("Your currency is set to Israeli Shekel (ILS) and cannot be changed for now.")
    }
    var currencyValueLabel: String { LocalizationSupport.localized("ILS") }
    var appearanceSectionTitle: String { LocalizationSupport.localized("Appearance") }
    var appearanceSystemLabel: String { LocalizationSupport.localized("System") }
    var appearanceLightLabel: String { LocalizationSupport.localized("Light") }
    var appearanceDarkLabel: String { LocalizationSupport.localized("Dark") }

    // MARK: Privacy controls
    var privacySectionTitle: String { LocalizationSupport.localized("Privacy") }
    var privacyFooterText: String {
        LocalizationSupport.localized("When turned off, your profile photo won't be shared with the other participant during a session.")
    }
    var showProfileImageLabel: String { LocalizationSupport.localized("Show my profile image") }
    var allowMessagesOutsideCallsLabel: String {
        LocalizationSupport.localized("Allow incoming messages from a teacher while not in a call")
    }

    // MARK: Language
    var languageSectionTitle: String { LocalizationSupport.localized("Language") }
    var systemLanguageTitle: String { LocalizationSupport.localized("System Language") }
    var systemLanguageSubtitle: String { LocalizationSupport.localized("Use the device language") }
}

@Observable
@MainActor
class SettingsViewModel: SettingsViewModeling {
    var navigationPath: [SettingsDestination] = []
    var activeConfirmation: SettingsConfirmation?
    var externalURL: URL?
    var showAlert = false
    var alertTitle = LocalizationSupport.localized("Settings")
    var alertMessage: String?
    var isLoading = false
    var showReauthPasswordPrompt = false
    var reauthPassword = ""
    var isOpeningPaymentSettings = false
    var isSubmittingContactSupport = false
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

    #if DEBUG
    /// Remote Config holds a fetched template for `minimumFetchInterval` (an
    /// hour), so a value edited in the console does not reach a running debug
    /// build until that expires or the app is reinstalled. `refresh()` fetches
    /// with a zero expiration and activates, and the localization flags are
    /// cycled around it in the same order as a language switch so views reading
    /// `dataFetched` re-read their strings against the template that just
    /// landed rather than the one they were rendered from.
    func forceReloadRemoteConfig() async {
        let localization = LocalizationManager.shared
        localization.isLoading = true
        localization.dataFetched = false
        await RemoteConfigService.shared.refresh()
        localization.dataFetched = true
        localization.isLoading = false
        present(
            title: LocalizationSupport.localized("Remote Config"),
            message: LocalizationSupport.localized("Reloaded from Remote Config.")
        )
    }
    #endif

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

    func deleteAccount() async -> Bool {
        // Email/password users can't be re-authenticated silently — prompt for the
        // password first, then finish the deletion in `completeAccountDeletion(withPassword:)`.
        if authService.requiresPasswordForReauth {
            reauthPassword = ""
            showReauthPasswordPrompt = true
            return false
        }
        return await performAccountDeletion()
    }

    /// Finishes account deletion for email/password users after they supply their password.
    func completeAccountDeletion(withPassword password: String) async -> Bool {
        return await performAccountDeletion(password: password)
    }

    /// Re-authenticates the user, then deletes their profile data and Firebase account.
    /// Deleting the profile data must happen while still authenticated (Firestore rules),
    /// so re-authentication comes first to guarantee a fresh session for the account deletion.
    private func performAccountDeletion(password: String? = nil) async -> Bool {
        guard let uid = authService.currentUserID else {
            present(message: SettingsError.missingUser.localizedDescription)
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await authService.reauthenticate(password: password)
            try await UserService.shared.deleteUserData(uid: uid)
            try await authService.deleteCurrentUser()
            return true
        } catch (let error){
            present(
                title: LocalizationSupport.localized("Delete Account"),
                message: error.localizedDescription
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
    
    func present(title: String, message: String) {
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

/// Preview / test double for `SettingsViewModeling`. It keeps the same state as
/// the live view model but never touches Firebase, so previews render every
/// settings screen and destructive actions stay inert.
@Observable
@MainActor
final class MockSettingsViewModel: SettingsViewModeling {
    let role: AppUserMode

    var navigationPath: [SettingsDestination] = []
    var activeConfirmation: SettingsConfirmation?
    var externalURL: URL?
    var showAlert = false
    var alertTitle = LocalizationSupport.localized("Settings")
    var alertMessage: String?
    var isLoading = false
    var showReauthPasswordPrompt = false
    var reauthPassword = ""
    var isOpeningPaymentSettings = false
    var isSubmittingContactSupport = false
    var contactSupportTitle = ""
    var contactSupportDescription = ""
    var contactSupportTitleMaxLength = 50
    var contactSupportDescriptionMaxLength = 1024
    var contactSupportPreview: ContactSupportRequest?
    var selectedLanguage: SettingsLanguageChoice

    init(
        role: AppUserMode = .student,
        selectedLanguage: SettingsLanguageChoice = .system
    ) {
        self.role = role
        self.selectedLanguage = selectedLanguage
    }

    func updateLanguage(_ language: SettingsLanguageChoice) {
        selectedLanguage = language
    }

    func sendPasswordReset() {
        present(
            title: LocalizationSupport.localized("Change Password"),
            message: LocalizationSupport.localized("Password reset email sent.")
        )
    }

    func openPaymentSettings() {
        externalURL = previewURL(path: "payment-settings")
    }

    func deleteAccount() async -> Bool {
        present(title: deleteAccountTitle, message: previewOnlyDeleteMessage)
        return false
    }

    func completeAccountDeletion(withPassword password: String) async -> Bool {
        present(title: deleteAccountTitle, message: previewOnlyDeleteMessage)
        return false
    }

    func logOut() -> Bool { true }

    func contactSupportAppeared() {}

    func updateContactSupportTitle(_ value: String) {
        contactSupportTitle = String(value.prefix(contactSupportTitleMaxLength))
    }

    func updateContactSupportDescription(_ value: String) {
        contactSupportDescription = String(value.prefix(contactSupportDescriptionMaxLength))
    }

    func loadContactSupportLimits() async {}

    func previewContactSupport() {
        contactSupportPreview = ContactSupportService.shared.makeRequest(
            title: contactSupportTitle,
            description: contactSupportDescription,
            userID: "mock-user",
            userName: "Sarah Jenkins",
            userEmail: "sarah@example.com",
            role: role
        )
    }

    func cancelContactSupportPreview() {
        contactSupportPreview = nil
    }

    func submitContactSupport() {
        contactSupportPreview = nil
        contactSupportTitle = ""
        contactSupportDescription = ""
        if navigationPath.last == .contactUs {
            navigationPath.removeLast()
        }
        present(
            title: LocalizationSupport.localized("Contact Us"),
            message: LocalizationSupport.localized("Your message was sent.")
        )
    }

    func openEULA() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("EULA"), url: previewURL(path: "eula")))
    }

    func openPrivacyPolicy() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("Privacy Policy"), url: previewURL(path: "privacy")))
    }

    func openAbout() async {
        navigationPath.append(.webPage(title: LocalizationSupport.localized("About"), url: previewURL(path: "about")))
    }

    func present(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    func consumeExternalURL() {
        externalURL = nil
    }

    #if DEBUG
    func forceReloadRemoteConfig() async {
        present(
            title: LocalizationSupport.localized("Remote Config"),
            message: LocalizationSupport.localized("Reloaded from Remote Config.")
        )
    }
    #endif

    private func previewURL(path: String) -> URL {
        URL(string: "https://example.com/\(path)") ?? URL(fileURLWithPath: "/")
    }
}
