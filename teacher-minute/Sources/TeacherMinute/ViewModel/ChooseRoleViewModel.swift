//
//  ChooseRoleViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation
import SkipFuse

@Observable
@MainActor
final class ChooseRoleViewModel {
    var selectedRole: AuthRole = .student

    var onContinue: ((AuthRole) -> Void)?

    var teacherDescriptionLines: [String] {
        RemoteConfigService.getLocalizedStringArray(for: .teacherDescription)
    }

    var studentDescriptionLines: [String] {
        RemoteConfigService.getLocalizedStringArray(for: .studentDescription)
    }

    // MARK: - How it works (teacher)

    var howItWorksTeacherTitle: String { LocalizationSupport.localized("How it works") }
    /// The panel's steps in order; the view renders whatever is in the array.
    var howItWorksTeacherSteps: [HowItWorksStep] {
        [
            HowItWorksStep(
                title: LocalizationSupport.localized("Complete your profile"),
                subtitle: LocalizationSupport.localized("Add your subjects, bio, and verification documents")
            ),
            HowItWorksStep(
                title: LocalizationSupport.localized("A student requests help"),
                subtitle: LocalizationSupport.localized("Get matched to students who need your subject")
            ),
            HowItWorksStep(
                title: LocalizationSupport.localized("Teach live"),
                subtitle: LocalizationSupport.localized("Chat, whiteboard, voice messages – real time")
            ),
			HowItWorksStep(
			  title: LocalizationSupport.localized("Get paid for the time you taught."),
			  // The live rate when Remote Config has one, and a rate-free
			  // reassurance when it does not.
			  subtitle: LocalizationSupport.localized("Paid once a month")
			),
        ]
    }

    func continueFlow() {
        let role = String(describing: selectedRole)
        AnalyticsService.shared.logEvent(AnalyticsEvent.roleSelected, parameters: ["role": role])
        AnalyticsService.shared.setRole(role)
        onContinue?(selectedRole)
    }
}
