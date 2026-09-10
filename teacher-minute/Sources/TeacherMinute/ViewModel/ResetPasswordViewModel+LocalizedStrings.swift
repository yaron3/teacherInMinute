//
//  ResetPasswordViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the password-reset screen.
//

import Foundation

extension ResetPasswordViewModel {
    var screenTitle: String { LocalizationSupport.localized("Reset Password") }
    var introText: String {
        LocalizationSupport.localized("Enter your email or phone number and we'll\nsend you instructions to reset your password.")
    }
    var sendResetLinkLabel: String { LocalizationSupport.localized("Send Reset Link") }
    var backToLogInLabel: String { LocalizationSupport.localized("Back to Log In") }
    var emailTabLabel: String { LocalizationSupport.localized("Email") }
    var phoneTabLabel: String { LocalizationSupport.localized("Phone") }
}
