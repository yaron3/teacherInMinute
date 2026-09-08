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
    var howItWorksTeacherStep1Title: String { LocalizationSupport.localized("Complete your profile") }
    var howItWorksStep1Subtitle: String { LocalizationSupport.localized("Add your subjects, bio, and verification documents") }
    var connectTeacherStepTitle: String { LocalizationSupport.localized("A student requests help") }
    var howItWorksStep2Subtitle: String { LocalizationSupport.localized("Get matched to students who need your subject") }
    var howItWorksTeacherStep3Title: String { LocalizationSupport.localized("Teach live") }
    var howItWorksStep3Subtitle: String { LocalizationSupport.localized("Chat, whiteboard, voice messages – real time") }

    func continueFlow() {
        let role = String(describing: selectedRole)
        AnalyticsService.shared.logEvent(AnalyticsEvent.roleSelected, parameters: ["role": role])
        AnalyticsService.shared.setRole(role)
        onContinue?(selectedRole)
    }
}
