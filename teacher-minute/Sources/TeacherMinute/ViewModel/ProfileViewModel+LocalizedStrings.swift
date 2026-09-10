//
//  ProfileViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Every string the profile screens render. Views ask the view model for
//  copy instead of calling `LocalizationSupport.localized` themselves, so
//  the screens stay free of localization logic and every label is reachable
//  from a test through the same surface the view uses.
//

import Foundation

extension ProfileViewModel {

    // MARK: Contact fields
    var fullNameFieldLabel: String { LocalizationSupport.localized("Full Name") }
    var emailFieldLabel: String { LocalizationSupport.localized("Email") }
    var phoneFieldLabel: String { LocalizationSupport.localized("Phone") }
    var gradeFieldLabel: String { LocalizationSupport.localized("Grade") }
    var dateOfBirthFieldLabel: String { LocalizationSupport.localized("Date of Birth") }

    // MARK: Generic controls
    var editLabel: String { LocalizationSupport.localized("Edit") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }
    var clearLabel: String { LocalizationSupport.localized("Clear") }
    var selectLabel: String { LocalizationSupport.localized("Select") }
    var changeLabel: String { LocalizationSupport.localized("Change") }
    var retryLabel: String { LocalizationSupport.localized("Retry") }
    var addChipLabel: String { LocalizationSupport.localized("+ Add") }
    var saveChangesLabel: String { LocalizationSupport.localized("Save Changes") }
    var savingLabel: String { LocalizationSupport.localized("Saving...") }

    /// Label for the save button, which reports progress while a save is in flight.
    var saveButtonLabel: String { isLoading ? savingLabel : saveChangesLabel }

    // MARK: Sections
    var paymentMethodLabel: String { LocalizationSupport.localized("Payment Method") }
    var teachingDetailsSectionTitle: String { LocalizationSupport.localized("Teaching Details") }
    var gradeLevelsTaughtTitle: String { LocalizationSupport.localized("Grade Levels Taught") }
    var subjectsSectionTitle: String { LocalizationSupport.localized("Subjects") }
    var devicePermissionsSectionTitle: String { LocalizationSupport.localized("Device Permissions") }
    var microphoneLabel: String { LocalizationSupport.localized("Microphone") }
    var cameraLabel: String { LocalizationSupport.localized("Camera") }
    var notificationsLabel: String { LocalizationSupport.localized("Notifications") }

    // MARK: Profile photo
    var addPhotoDialogTitle: String { LocalizationSupport.localized("Add a photo") }
    var takePhotoLabel: String { LocalizationSupport.localized("Take Photo") }
    var chooseFromLibraryLabel: String { LocalizationSupport.localized("Choose from Library") }
    var cameraAccessRequiredMessage: String {
        LocalizationSupport.localized("Camera access is required to take a photo.")
    }

    // MARK: Saved PayPal
    var savedPayPalSectionTitle: String { LocalizationSupport.localized("Saved PayPal") }
    var payPalLabel: String { LocalizationSupport.localized("PayPal") }
    var noSavedPayPalText: String {
        LocalizationSupport.localized("No saved PayPal account. Tap \"+ Add\" to save one.")
    }
    var whereYouGetPaidTitle: String { LocalizationSupport.localized("Where you get paid") }
    var payoutEmailExplanation: String {
        LocalizationSupport.localized("Your monthly payout is sent to this address, so it must be the email on your PayPal account.")
    }
    var payPalEmailFieldTitle: String { LocalizationSupport.localized("PayPal Email") }
    var emailPlaceholder: String { LocalizationSupport.localized("name@example.com") }

    // MARK: Verification documents
    var completeDocumentsTitle: String { LocalizationSupport.localized("Complete Your Documents") }
    var documentsUploadedTitle: String { LocalizationSupport.localized("Documents Uploaded") }
    var uploadRemainingDocumentsSubtitle: String {
        LocalizationSupport.localized("Upload your remaining verification documents")
    }
    var viewUploadedDocumentsSubtitle: String {
        LocalizationSupport.localized("View the verification documents you uploaded")
    }

    // MARK: Edit profile
    var editProfileTitle: String { LocalizationSupport.localized("Edit Profile") }
    var editProfileSubtitle: String {
        LocalizationSupport.localized("Update the details students and teachers use to recognize and contact you.")
    }

    // MARK: Grade pickers
    var chooseGradesLabel: String { LocalizationSupport.localized("Choose grades") }
    var setDateOfBirthLabel: String { LocalizationSupport.localized("Set date of birth") }

    func selectedGradesCountText(_ count: Int) -> String {
        String(format: LocalizationSupport.localized("%d selected"), count)
    }

    /// Display form of a canonical grade value such as `"Grade 7"`, which is
    /// stored in English so a saved profile survives a language switch.
    func gradeLabel(for canonicalGrade: String) -> String {
        LocalizationSupport.localized(canonicalGrade)
    }
}
