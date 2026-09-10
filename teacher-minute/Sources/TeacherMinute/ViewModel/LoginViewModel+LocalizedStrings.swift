//
//  LoginViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the sign-in screen.
//

import Foundation

extension LoginViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Welcome Back") }
    var subtitleText: String {
        LocalizationSupport.localized("Log in to Teacher in a Minute to continue your journey.")
    }

    // MARK: Errors
    var signInErrorTitle: String { LocalizationSupport.localized("Sign In Error") }
    var genericErrorMessage: String { LocalizationSupport.localized("An unexpected error occurred.") }
    var okLabel: String { LocalizationSupport.localized("OK") }

    // MARK: Fields
    var emailFieldTitle: String { LocalizationSupport.localized("Email") }
    var emailPlaceholder: String { LocalizationSupport.localized("Enter your email") }
    var passwordFieldTitle: String { LocalizationSupport.localized("Password") }
    var passwordPlaceholder: String { LocalizationSupport.localized("Enter your password") }
    var forgotPasswordLabel: String { LocalizationSupport.localized("Forgot Password?") }

    // MARK: Actions
    var logInLabel: String { LocalizationSupport.localized("Log In") }
    var signingInLabel: String { LocalizationSupport.localized("Signing In…") }
    var signingInProgressText: String { LocalizationSupport.localized("Signing in…") }

    /// Label for the submit button, which reports progress while signing in.
    var logInButtonLabel: String { isLoading ? signingInLabel : logInLabel }

    var orContinueWithLabel: String { LocalizationSupport.localized("Or continue with") }
    var googleLabel: String { LocalizationSupport.localized("Google") }
    var appleLabel: String { LocalizationSupport.localized("Apple") }
    var noAccountText: String { LocalizationSupport.localized("Don't have an account?") }
    var signUpLabel: String { LocalizationSupport.localized("Sign Up") }
}
