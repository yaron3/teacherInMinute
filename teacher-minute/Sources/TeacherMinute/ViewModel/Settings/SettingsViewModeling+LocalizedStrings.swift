//
//  SettingsViewModeling+LocalizedStrings.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

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
