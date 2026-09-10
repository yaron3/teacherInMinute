//
//  TeacherEarningsViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the earnings screen and for the payout-method editor, which both
//  Earnings and Settings drive from this same view model.
//

import Foundation

extension TeacherEarningsViewModel {

    // MARK: Earnings screen
    var earningsScreenTitle: String { LocalizationSupport.localized("Income and Payments") }
    var nextPaymentTitle: String { LocalizationSupport.localized("Next Payment") }
    var inProgressLabel: String { LocalizationSupport.localized("In progress") }
    var weeklyBreakdownTitle: String { LocalizationSupport.localized("Weekly Breakdown") }
    var minutesUnitLabel: String { LocalizationSupport.localized("min") }
    var lessonsLabel: String { LocalizationSupport.localized("Lessons") }

    /// A month's one-line summary, e.g. "120 min · 8 Lessons".
    func monthSummaryText(minutes: Int, lessons: Int) -> String {
        "\(minutes) \(minutesUnitLabel) · \(lessons) \(lessonsLabel)"
    }

    func weekLessonsText(_ lessons: Int) -> String {
        "\(lessons) \(lessonsLabel)"
    }

    // MARK: Profile phone offer
    var updateProfileDialogTitle: String { LocalizationSupport.localized("Update your profile?") }
    var updateProfileDialogMessage: String {
        LocalizationSupport.localized("Save this number as your profile phone number too?")
    }
    var updateLabel: String { LocalizationSupport.localized("Update") }
    var notNowLabel: String { LocalizationSupport.localized("Not now") }

    // MARK: Payout method editor
    var payoutMethodSheetSubtitle: String {
        LocalizationSupport.localized("Choose where we should send your monthly payout.")
    }
    var saveChangesLabel: String { LocalizationSupport.localized("Save Changes") }
    var savingLabel: String { LocalizationSupport.localized("Saving...") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }

    /// Label for the payout editor's save button, which reports progress
    /// while the save is in flight.
    var payoutSaveButtonLabel: String { isSavingPayoutMethod ? savingLabel : saveChangesLabel }

    // MARK: Bank fields
    var bankFieldTitle: String { LocalizationSupport.localized("Bank") }
    var branchNumberFieldTitle: String { LocalizationSupport.localized("Branch Number") }
    var branchNumberPlaceholder: String { LocalizationSupport.localized("e.g. 123") }
    var accountNumberFieldTitle: String { LocalizationSupport.localized("Account Number") }
    var accountNumberPlaceholder: String { LocalizationSupport.localized("e.g. 45678901") }
    var accountHolderFieldTitle: String { LocalizationSupport.localized("Account Holder Name") }
    var accountHolderPlaceholder: String {
        LocalizationSupport.localized("Full name as it appears at the bank")
    }

    // MARK: Bit fields
    var bitPhoneFieldTitle: String { LocalizationSupport.localized("Bit Phone Number") }
    var bitPhonePlaceholder: String { LocalizationSupport.localized("place holder phone number") }
    var phoneErrorMessage: String { LocalizationSupport.localized("Enter a valid phone number.") }
    var bitPhoneHint: String {
        LocalizationSupport.localized("Use the phone number registered with your Bit account.")
    }

    func useProfileNumberText(_ phone: String) -> String {
        String(format: LocalizationSupport.localized("Use my profile number (%@)"), phone)
    }

    // MARK: PayPal fields
    var payPalEmailFieldTitle: String { LocalizationSupport.localized("PayPal Email") }
    var emailPlaceholder: String { LocalizationSupport.localized("name@example.com") }
    var payPalEmailErrorMessage: String {
        LocalizationSupport.localized("Enter a valid PayPal email address.")
    }
}
