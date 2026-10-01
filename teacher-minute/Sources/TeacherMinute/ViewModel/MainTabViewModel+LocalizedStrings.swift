//
//  MainTabViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the main screen's side menu.
//

import Foundation

extension MainTabViewModel {
    var openMenuLabel: String { LocalizationSupport.localized("Open menu") }
    var closeMenuLabel: String { LocalizationSupport.localized("Close menu") }
    var menuTitle: String { LocalizationSupport.localized("Menu") }
    var emailLabel: String { LocalizationSupport.localized("Email") }
    var phoneLabel: String { LocalizationSupport.localized("Phone") }
    var alreadyHaveAccountText: String { LocalizationSupport.localized("Already have an account?") }
    var logInLabel: String { LocalizationSupport.localized("Log In") }
}
