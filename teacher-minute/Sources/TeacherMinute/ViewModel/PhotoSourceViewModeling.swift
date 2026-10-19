//
//  PhotoSourceViewModeling.swift
//  teacher-minute
//
//  `PhotoSourceButton` is shared by every screen that lets the user attach an
//  image — profile photo, verification documents, and a question's
//  attachment. Each of those screens has a different view model, so this is
//  the surface the button reads its copy from, and the one place the wording
//  of the picker is defined.
//

import Foundation

protocol PhotoSourceViewModeling: AnyObject {}

extension PhotoSourceViewModeling {
    var photoSourceDialogTitle: String { LocalizationSupport.localized("Add a photo") }
    var photoSourceTakePhotoLabel: String { LocalizationSupport.localized("Take Photo") }
    var photoSourceLibraryLabel: String { LocalizationSupport.localized("Choose from Library") }
    var photoSourceCancelLabel: String { LocalizationSupport.localized("Cancel") }

    var cameraDisabledTitle: String { LocalizationSupport.localized("Camera disabled") }
    var cameraDisabledMessage: String {
        LocalizationSupport.localized("Camera access is disabled. Open Settings and enable camera access to take a photo.")
    }
    var openSettingsLabel: String { LocalizationSupport.localized("Open Settings") }

    var photoSourceCameraDeniedTitle: String { LocalizationSupport.localized("Camera access required") }
    var photoSourceCameraDeniedMessage: String {
        LocalizationSupport.localized("Enable camera access in Settings to take photos.")
    }
    var photoSourceNotNowLabel: String { LocalizationSupport.localized("Not now") }
}

extension ProfileViewModel: PhotoSourceViewModeling {}
extension TeacherIdentityVerificationViewModel: PhotoSourceViewModeling {}
extension TeacherDocumentsViewModel: PhotoSourceViewModeling {}
