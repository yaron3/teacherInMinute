//
//  SettingsViewModeling.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

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
