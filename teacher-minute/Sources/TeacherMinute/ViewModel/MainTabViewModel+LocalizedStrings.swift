//
//  MainTabViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the main screen's side menu and its log-out confirmation.
//

import Foundation

extension MainTabViewModel {
    var openMenuLabel: String { LocalizationSupport.localized("Open menu") }
    var closeMenuLabel: String { LocalizationSupport.localized("Close menu") }
    var logOutLabel: String { SettingsConfirmation.logOut.title }
    var logOutConfirmMessage: String { SettingsConfirmation.logOut.message }
    var logOutConfirmLabel: String { SettingsConfirmation.logOut.confirmTitle }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }
}
