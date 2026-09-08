//
//  MockSettingsViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/09/2026.
//


/// Preview / test double for `SettingsViewModeling`. It keeps the same state as
/// the live view model but never touches Firebase, so previews render every
/// settings screen and destructive actions stay inert.
///
import SwiftUI
import SkipFuse
@Observable
@MainActor
final class MockSettingsViewModel: SettingsViewModeling {
  var externalURL: URL?
  
    let role: AppUserMode

    var navigationPath: [SettingsDestination] = []
    var activeConfirmation: SettingsConfirmation?
    var showAlert = false
    var alertTitle = "Settings"
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
            title: "Change Password",
            message: "Password reset email sent."
        )
    }

    func openPaymentSettings() {
	  print("openPaymentSettings")
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
            title: "Contact Us",
            message: "Your message was sent."
        )
    }

    func openEULA() async {
	  print("openEULA")
       // navigationPath.append(.webPage(title: "EULA", url: URL("eula")))
    }

    func openPrivacyPolicy() async {
	  print("openPrivacyPolicy")
     //   navigationPath.append(.webPage(title: "Privacy Policy", url: previewURL(path: "privacy")))
    }

    func openAbout() async {
	  print("openAbout")
      //  navigationPath.append(.webPage(title: "About", url: previewURL(path: "about")))
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
            title: "Remote Config",
            message: "Reloaded from Remote Config."
        )
    }
    #endif


}
