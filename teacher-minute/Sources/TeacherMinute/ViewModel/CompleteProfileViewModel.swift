//
//  CompleteProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class CompleteProfileViewModel {
    let role: AuthRole
    var selectedRole: AuthRole
    var fullName = ""
    var phoneNumber = ""
    var age = ""
    var grade = ""

    var onContinue: (() -> Void)?

    let grades: [String] = (1...12).map { "Grade \($0)" } + ["College", "Adult Learner"]

    var canContinue: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phoneNumber.isEmpty
    }

    init(role: AuthRole) {
        self.role = role
        self.selectedRole = role
    }

    func continueFlow() {
        guard canContinue else { return }
        onContinue?()
    }
}
