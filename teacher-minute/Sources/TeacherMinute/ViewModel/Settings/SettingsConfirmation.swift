//
//  SettingsConfirmation.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

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
