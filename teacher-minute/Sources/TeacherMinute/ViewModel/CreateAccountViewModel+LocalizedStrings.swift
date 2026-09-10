//
//  CreateAccountViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the sign-up screen, so the view renders text it is handed
//  rather than resolving it itself.
//

import Foundation

extension CreateAccountViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Create Account") }
    var signUpDialogTitle: String { LocalizationSupport.localized("Sign Up") }
    var okLabel: String { LocalizationSupport.localized("OK") }

    // MARK: Legal documents
    var eulaTitle: String { LocalizationSupport.localized("EULA") }
    var privacyPolicyTitle: String { LocalizationSupport.localized("Privacy Policy") }
    var termsOfServiceTitle: String { LocalizationSupport.localized("Terms of Service") }
    var agreementMarkdown: String {
        LocalizationSupport.localized("I agree to the [Terms of Service](teacherminute://terms) and [Privacy Policy.](teacherminute://privacy)")
    }

    // MARK: Email field
    var emailFieldTitle: String { LocalizationSupport.localized("Email") }
    var emailPlaceholder: String { LocalizationSupport.localized("Enter your email") }
    var emailErrorMessage: String { LocalizationSupport.localized("Enter a valid email address.") }

    // MARK: Password fields
    var passwordFieldTitle: String { LocalizationSupport.localized("Password") }
    var passwordPlaceholder: String { LocalizationSupport.localized("Min. 6 characters") }
    var passwordErrorMessage: String { LocalizationSupport.localized("Must be at least 6 characters.") }
    var confirmPasswordFieldTitle: String { LocalizationSupport.localized("Confirm Password") }
    var confirmPasswordPlaceholder: String { LocalizationSupport.localized("Re-enter your password") }
    var confirmPasswordErrorMessage: String { LocalizationSupport.localized("Passwords do not match.") }

    // MARK: Marketing opt-in
    var marketingOptInText: String {
        LocalizationSupport.localized("Send me occasional updates and tips about\nTeacher in a Minute.")
    }

    // MARK: Actions
    var continueToRoleSelectionLabel: String {
        LocalizationSupport.localized("Continue to Role Selection")
    }
    var orContinueWithLabel: String { LocalizationSupport.localized("Or continue with") }
    var googleLabel: String { LocalizationSupport.localized("Google") }
    var appleLabel: String { LocalizationSupport.localized("Apple") }
    var alreadyHaveAccountText: String { LocalizationSupport.localized("Already have an account?") }
    var logInLabel: String { LocalizationSupport.localized("Log In") }
}
