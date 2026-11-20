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
    case teacherPayouts
    case studentPayments
    case notifications
    case privacyControls
    case language
    case about
    case contactUs
    case webPage(title: String, url: URL)

    /// The page's `screen` for Analytics; none for a web page, whose view
    /// tracks itself.
    var analyticsScreen: String? {
        switch self {
        case .accountSecurity: "settings_account_security"
        case .appPreferences: "settings_preferences"
        case .teacherPayouts: "settings_teacher_payouts"
        case .studentPayments: "settings_student_payments"
        case .notifications: "settings_notifications"
        case .privacyControls: "settings_privacy"
        case .language: "settings_language"
        case .about: "settings_about"
        case .contactUs: "settings_contact_us"
        case .webPage: nil
        }
    }

    var title: String {
        switch self {
        case .accountSecurity: LocalizationSupport.localized("Account & Security")
        case .appPreferences: LocalizationSupport.localized("Preferences")
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
}
