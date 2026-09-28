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

/// What the welcome screen says to an account it just turned away because the
/// account belongs to the other app (`AppRouter.otherAppAccountRole`).
struct OtherAppNotice {
    /// The store page of the app the account belongs to, and the button that
    /// opens it.
    struct Download {
        let url: URL
        let label: String
    }

    let accountRole: AuthRole
    let title: String
    let message: String
    /// `nil` when there is no store page to offer, which leaves the notice
    /// saying only where to go.
    let download: Download?
}

@Observable
@MainActor
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

    // MARK: An account for the other app

    var notNowLabel: String { LocalizationSupport.localized("Not now") }
    var okLabel: String { LocalizationSupport.localized("OK") }

    /// A student in Pro Teacher is, above all, someone whose app has just
    /// updated into it, so they are offered Instant Teacher. The copy and the
    /// store link are all in Remote Config, to be reworded or pointed elsewhere
    /// without a release. A teacher in Instant Teacher is only told where to
    /// sign in.
    func otherAppNotice(for role: AuthRole) -> OtherAppNotice {
        switch role {
        case .student:
            let storePage = RemoteConfigService.shared.getURL(RemoteConfigKey.studentAppURL.rawValue)
            return OtherAppNotice(
                accountRole: role,
                title: LocalizationSupport.localized("Students have a new app"),
                message: LocalizationSupport.localized("Pro Teacher is now our app for teachers only. To keep learning, download Instant Teacher, our new app for students, and sign in there with the same account."),
                download: storePage.map {
                    OtherAppNotice.Download(url: $0, label: LocalizationSupport.localized("Download Instant Teacher"))
                }
            )
        case .teacher:
            return OtherAppNotice(
                accountRole: role,
                title: LocalizationSupport.localized("Sign In Error"),
                message: String(format: LocalizationSupport.localized("This is a teacher account. Please sign in to %@, our app for teachers."), role.appName),
                download: nil
            )
        }
    }

    /// Records that a notice's download button was tapped; the view opens the
    /// page.
    func downloadTapped(for notice: OtherAppNotice) {
        AnalyticsService.shared.logEvent(AnalyticsEvent.otherAppDownloadOpened, parameters: [
            "account_role": notice.accountRole.rawValue,
            "app_role": AuthRole.appRole.rawValue,
        ])
    }
}
