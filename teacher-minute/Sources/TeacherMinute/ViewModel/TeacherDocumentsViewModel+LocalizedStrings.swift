//
//  TeacherDocumentsViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the uploaded-documents screen.
//

import Foundation

extension TeacherDocumentsViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Documents Uploaded") }
    var introText: String {
        LocalizationSupport.localized("These are the verification documents you uploaded.")
    }
    var closeLabel: String { LocalizationSupport.localized("Close") }
    var retryLabel: String { LocalizationSupport.localized("Retry") }

    // MARK: States
    var loadingText: String { LocalizationSupport.localized("Loading documents...") }
    var emptyStateText: String { LocalizationSupport.localized("No documents uploaded yet.") }
    var documentLoadFailedText: String { LocalizationSupport.localized("Could not load this document.") }

    // MARK: Missing documents
    var addMissingDocumentsTitle: String { LocalizationSupport.localized("Add missing documents") }
    var addMissingDocumentsHint: String {
        LocalizationSupport.localized("Uploading the remaining documents helps us verify you as a teacher faster.")
    }
    var uploadingLabel: String { LocalizationSupport.localized("Uploading…") }
    var notUploadedYetLabel: String { LocalizationSupport.localized("Not uploaded yet") }
    var uploadLabel: String { LocalizationSupport.localized("Upload") }

    // MARK: Photo source
    var addPhotoDialogTitle: String { LocalizationSupport.localized("Add a photo") }
    var takePhotoLabel: String { LocalizationSupport.localized("Take Photo") }
    var chooseFromLibraryLabel: String { LocalizationSupport.localized("Choose from Library") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }
    var cameraAccessRequiredMessage: String {
        LocalizationSupport.localized("Camera access is required to take a photo.")
    }
}
