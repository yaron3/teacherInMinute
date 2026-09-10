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
        LocalizationSupport.localized("Tell us a bit about yourself to get started with\nTeacher in a Minute.")
    }
    var loadingText: String { LocalizationSupport.localized("Loading your profile…") }
    var continueLabel: String { LocalizationSupport.localized("Continue") }

    // MARK: Name
    var fullNameFieldTitle: String { LocalizationSupport.localized("Full Name") }
    var fullNamePlaceholder: String { LocalizationSupport.localized("place holder name") }

    // MARK: Phone
    var phoneRequiredFieldTitle: String { LocalizationSupport.localized("Phone Number") }
    var phoneOptionalFieldTitle: String { LocalizationSupport.localized("Phone Number (Optional)") }
    var phonePlaceholder: String { LocalizationSupport.localized("place holder phone number") }

    /// The phone field is only mandatory for teachers, and its title says so.
    func phoneFieldTitle(isOptional: Bool) -> String {
        isOptional ? phoneOptionalFieldTitle : phoneRequiredFieldTitle
    }

    // MARK: PayPal
    var payPalEmailFieldTitle: String { LocalizationSupport.localized("PayPal Email") }
    var optionalPlaceholder: String { LocalizationSupport.localized("Optional") }

    // MARK: Missing-payout warning
    var payoutMissingDialogTitle: String { LocalizationSupport.localized("Payout Details Missing") }
    var payoutMissingDialogMessage: String {
        LocalizationSupport.localized("You will not receive money until you provide bank account details or PayPal info.")
    }
    var addNowLabel: String { LocalizationSupport.localized("Add Now") }
    var continueAnywayLabel: String { LocalizationSupport.localized("Continue Anyway") }

    // MARK: Grade
    var gradeSectionTitle: String { LocalizationSupport.localized("Your Grade") }
    var selectLabel: String { LocalizationSupport.localized("Select") }

    /// The chosen grade, or the placeholder while nothing is chosen yet.
    var gradeSelectionLabel: String { grade.isEmpty ? selectLabel : grade }
}
