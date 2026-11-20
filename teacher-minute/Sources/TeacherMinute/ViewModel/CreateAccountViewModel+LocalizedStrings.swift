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

    // MARK: Signed up (IT-51)
    var signupSuccessTitle: String { LocalizationSupport.localized("Your account is ready") }
    func verificationSentText(email: String) -> String {
        String(
            format: LocalizationSupport.localized("We sent a verification link to %@. Open it on this phone to verify your email address."),
            email
        )
    }
    func studentRewardOfferText(minutes: Int) -> String {
        String(format: LocalizationSupport.localized("Verify your email address and get %d free minutes."), minutes)
    }
    func teacherRewardOfferText(percent: Int, minutes: Int) -> String {
        String(
            format: LocalizationSupport.localized("Verify your email address and keep %d%% of your earnings for your first %d minutes of teaching."),
            percent,
            minutes
        )
    }

    // MARK: Legal documents
    var eulaTitle: String { LocalizationSupport.localized("EULA") }
    var privacyPolicyTitle: String { LocalizationSupport.localized("Privacy Policy") }
    var termsOfServiceTitle: String { LocalizationSupport.localized("Terms of Service") }
    var acceptTermsHint: String { LocalizationSupport.localized("Accept the terms to continue") }
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
        String(format: LocalizationSupport.localized("Send me occasional updates and tips about\n%@."), AuthRole.appRole.appName)
    }

    // MARK: Actions
    var continueLabel: String { LocalizationSupport.localized("Continue") }
    var orContinueWithLabel: String { LocalizationSupport.localized("Or continue with") }
    var googleLabel: String { LocalizationSupport.localized("Google") }
    var appleLabel: String { LocalizationSupport.localized("Apple") }
    var alreadyHaveAccountText: String { LocalizationSupport.localized("Already have an account?") }
    var logInLabel: String { LocalizationSupport.localized("Log In") }

    // MARK: The sign-up header
    var signUpStepLabel: String { LocalizationSupport.localized("Registration") }
    var signUpStepTitle: String { LocalizationSupport.localized("Registration: Create an account") }
    var signUpSubtitle: String {
        LocalizationSupport.localized("Manage payments, preferences, notifications and device settings.")
    }
    var backLabel: String { LocalizationSupport.localized("Back") }
}
