//
//  ChooseRoleViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class ChooseRoleViewModel {
    var selectedRole: AuthRole = .student

    var onContinue: ((AuthRole) -> Void)?

    func continueFlow() {
        let role = String(describing: selectedRole)
        AnalyticsService.shared.logEvent(AnalyticsEvent.roleSelected, parameters: ["role": role])
        AnalyticsService.shared.setRole(role)
        onContinue?(selectedRole)
    }
}
