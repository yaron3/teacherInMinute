//
//  SettingsDestination.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

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
