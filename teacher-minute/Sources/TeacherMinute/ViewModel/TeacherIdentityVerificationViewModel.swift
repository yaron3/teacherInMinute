//
//  TeacherIdentityVerificationViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class TeacherIdentityVerificationViewModel {
    var hasTeachingCredentials = false
    var hasGovernmentIDFront = false
    var hasGovernmentIDBack = false
    var hasSelfie = false
    var acceptedTerms = false

    var onSubmit: (() -> Void)?

    var canSubmit: Bool {
        hasTeachingCredentials &&
        hasGovernmentIDFront &&
        hasGovernmentIDBack &&
        hasSelfie &&
        acceptedTerms
    }

    func uploadTeachingCredentials() { hasTeachingCredentials = true }
    func uploadGovernmentIDFront()   { hasGovernmentIDFront = true }
    func uploadGovernmentIDBack()    { hasGovernmentIDBack = true }
    func takeSelfie()                { hasSelfie = true }

    func submitForReview() {
        guard canSubmit else { return }
        onSubmit?()
    }
}
