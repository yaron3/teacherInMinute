//
//  WelcomeViewModel.swift
//  teacher-minute
//
//  The pre-auth landing screen holds no state of its own, but its copy still
//  belongs in a view model rather than in the view, so the screen is
//  consistent with every other one and its text is reachable from a test.
//

import Foundation
import SwiftUI
import Observation
import SkipFuse

@Observable
final class WelcomeViewModel {
    var appName: String { LocalizationSupport.localized("Teacher in a Minute") }
    var headline: String { LocalizationSupport.localized("Help you anywhere") }
    var subheadline: String {
        LocalizationSupport.localized("Connect instantly with verified math\nteachers for on-demand help, or share your\nexpertise.")
    }
    var appPreviewLabel: String { LocalizationSupport.localized("App Preview") }

    var verifiedTutorsBadge: String { LocalizationSupport.localized("Verified Tutors") }
    var privacyProtectedBadge: String { LocalizationSupport.localized("Privacy Protected") }

    var signUpLabel: String { LocalizationSupport.localized("Sign Up") }
    var logInLabel: String { LocalizationSupport.localized("Already have an account? Log In") }
}
