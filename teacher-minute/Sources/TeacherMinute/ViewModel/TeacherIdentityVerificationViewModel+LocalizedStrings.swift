//
//  TeacherIdentityVerificationViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the identity-verification step. The screen and its upload
//  components read every label from here rather than calling
//  `LocalizationSupport.localized` themselves.
//

import Foundation

extension TeacherIdentityVerificationViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Verify Your Identity") }
    var stepIndicatorText: String { LocalizationSupport.localized("Step 1 of 2") }
    var checkingLabel: String { LocalizationSupport.localized("Checking…") }

    // MARK: Government ID section
    var governmentIDSectionTitle: String { LocalizationSupport.localized("Government ID") }
    var governmentIDDescriptionFallback: String {
        LocalizationSupport.localized("Upload a clear photo of your passport, driver's license,\nor national ID. A valid government ID is required to\nbecome a verified teacher.")
    }
    var frontSideLabel: String { LocalizationSupport.localized("Front Side") }
    var backSideLabel: String { LocalizationSupport.localized("Back Side") }
    var governmentIDFrontStatusTitle: String { LocalizationSupport.localized("Government ID – Front") }

    // MARK: Upload boxes
    var tapToUploadDocumentLabel: String { LocalizationSupport.localized("Tap to upload document") }
    var uploadFormatsHint: String { LocalizationSupport.localized("PDF, JPG or PNG (Max 5MB)") }
    var uploadingLabel: String { LocalizationSupport.localized("Uploading…") }
    var uploadingSelfieLabel: String { LocalizationSupport.localized("Uploading selfie…") }
    var takeSelfieLabel: String { LocalizationSupport.localized("Take Selfie") }
    var ensureGoodLightingHint: String { LocalizationSupport.localized("Ensure good lighting") }
    var requiredLowercaseLabel: String { LocalizationSupport.localized("required") }

    // MARK: Verification status
    var verificationStatusSectionTitle: String { LocalizationSupport.localized("VERIFICATION STATUS") }
    var readyLabel: String { LocalizationSupport.localized("Ready") }
    var incompleteLabel: String { LocalizationSupport.localized("Incomplete") }
    var verificationStatusLabel: String { canSubmit ? readyLabel : incompleteLabel }
    var requiredLabel: String { LocalizationSupport.localized("Required") }
    var optionalLabel: String { LocalizationSupport.localized("Optional") }
    var alertMark: String { LocalizationSupport.localized("!") }

    /// Requirement badge for a status row, which reads "Required" only for
    /// documents the teacher cannot skip.
    func requirementLabel(isMandatory: Bool) -> String {
        isMandatory ? requiredLabel : optionalLabel
    }

    // MARK: Submission
    var submitForReviewLabel: String { LocalizationSupport.localized("Submit for Review") }
    var continueUploadLaterLabel: String { LocalizationSupport.localized("Continue - upload later") }
    var acceptTermsHint: String { LocalizationSupport.localized("Accept the terms to continue") }
    var uploadFrontSideHint: String {
        LocalizationSupport.localized("Upload the front side of your ID to continue")
    }

    /// Why the submit button is still disabled: the front of the ID is the
    /// first thing missing, and the terms checkbox is the last.
    var submitBlockedHint: String {
        hasGovernmentIDFront ? acceptTermsHint : uploadFrontSideHint
    }

    var confirmDocumentsText: String {
        LocalizationSupport.localized("I confirm that the uploaded documents are authentic and belong to me. I agree to the Verification Terms.")
    }

    // MARK: Privacy note
    var privacyTitle: String { LocalizationSupport.localized("Your Privacy Matters") }
    var privacyText: String {
        LocalizationSupport.localized("Your documents are securely encrypted and\nonly used for verification purposes. They will\nnot be shared publicly on your profile.")
    }

    // MARK: Photo source
    var addPhotoDialogTitle: String { LocalizationSupport.localized("Add a photo") }
    var takePhotoLabel: String { LocalizationSupport.localized("Take Photo") }
    var chooseFromLibraryLabel: String { LocalizationSupport.localized("Choose from Library") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }

    // MARK: Errors
    var cameraAccessRequiredMessage: String {
        LocalizationSupport.localized("Camera access is required to take a photo.")
    }
    var couldNotReadImageMessage: String {
        LocalizationSupport.localized("Could not read selected image")
    }
}
