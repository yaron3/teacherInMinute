//
//  MainTabViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the main screen's side menus and the log-out confirmation.
//

import Foundation

extension MainTabViewModel {
    var openMenuLabel: String { LocalizationSupport.localized("Open menu") }
    var closeMenuLabel: String { LocalizationSupport.localized("Close menu") }
    var logOutLabel: String { SettingsConfirmation.logOut.title }
    var logOutConfirmMessage: String { SettingsConfirmation.logOut.message }
    var logOutConfirmLabel: String { SettingsConfirmation.logOut.confirmTitle }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }

    // Instant Teacher's menu.
    var menuTitle: String { LocalizationSupport.localized("Menu") }
    var emailLabel: String { LocalizationSupport.localized("Email") }
    var phoneLabel: String { LocalizationSupport.localized("Phone") }
    var alreadyHaveAccountText: String { LocalizationSupport.localized("Already have an account?") }
    var logInLabel: String { LocalizationSupport.localized("Log In") }
}
