//
//  SettingsViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Observation
import Foundation
import SwiftUI
import SkipFuse

#if !os(Android)
import FirebaseRemoteConfig
import FirebaseAnalytics

#else
import SkipFirebaseRemoteConfig
import SkipFirebaseAnalytics
#endif

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
