//
//  CompleteProfileViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the profile-completion onboarding step.
//

import Foundation

extension CompleteProfileViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Complete your profile") }
    var introText: String {
        String(format: LocalizationSupport.localized("Tell us a bit about yourself to get started with\n%@."), AuthRole.appRole.appName)
    }
    var loadingText: String { LocalizationSupport.localized("Loading your profile…") }
    var continueLabel: String { LocalizationSupport.localized("Continue") }
    /// A student's profile step leads on to the free minutes a verified
    /// account earns, and says so.
    var continueToMinutesLabel: String { LocalizationSupport.localized("Continue to get minutes") }
    var backLabel: String { LocalizationSupport.localized("Back") }

    // MARK: Name
    var fullNameFieldTitle: String { LocalizationSupport.localized("Full Name") }
    var fullNamePlaceholder: String { LocalizationSupport.localized("place holder name") }

    // MARK: Email
    var emailFieldTitle: String { LocalizationSupport.localized("Email") }
    var emailPlaceholder: String { LocalizationSupport.localized("Enter your email") }

    /// Why the link to a changed address could not be sent.
    func emailChangeErrorMessage(for error: Error) -> String {
        guard case .serverError(_, let status, _) = error as? FunctionsError else {
            return LocalizationSupport.localized("Couldn't send the email. Please try again later.")
        }
        switch status {
        case "ALREADY_EXISTS":
            return LocalizationSupport.localized("This email address is already in use.")
        case "INVALID_ARGUMENT":
            return LocalizationSupport.localized("Please enter a valid email address.")
        case "RESOURCE_EXHAUSTED":
            return LocalizationSupport.localized("Too many emails sent. Please try again in a few minutes.")
        default:
            return LocalizationSupport.localized("Couldn't send the email. Please try again later.")
        }
    }

    // MARK: Phone
    var phoneRequiredFieldTitle: String { LocalizationSupport.localized("Phone Number") }
    var phoneOptionalFieldTitle: String { LocalizationSupport.localized("Phone Number (Optional)") }
    var phonePlaceholder: String { LocalizationSupport.localized("place holder phone number") }

    /// The phone field is only mandatory for teachers, and its title says so.
    func phoneFieldTitle(isOptional: Bool) -> String {
        isOptional ? phoneOptionalFieldTitle : phoneRequiredFieldTitle
    }

    // MARK: Payout method
    var payoutMethodSectionTitle: String { LocalizationSupport.localized("How would you like to get paid?") }
    /// Says both that the question can be skipped and that tapping the chosen
    /// destination again is how it gets un-picked.
    var payoutMethodSectionHint: String {
        LocalizationSupport.localized("Optional — tap again to unpick. You will add the details later, under Earnings.")
    }

    // MARK: Missing-payout warning
    var payoutMissingDialogTitle: String { LocalizationSupport.localized("Payout Details Missing") }
    var payoutMissingDialogMessage: String {
        LocalizationSupport.localized("You will not receive money until you add your payout details.")
    }
    var addNowLabel: String { LocalizationSupport.localized("Add Now") }
    var continueAnywayLabel: String { LocalizationSupport.localized("Continue Anyway") }

    // MARK: Grade
    var gradeSectionTitle: String { LocalizationSupport.localized("Your Grade") }
    var selectLabel: String { LocalizationSupport.localized("Select") }

    /// The chosen grade, or the placeholder while nothing is chosen yet.
    var gradeSelectionLabel: String { grade.isEmpty ? selectLabel : grade }
}
