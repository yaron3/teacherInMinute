//
//  ResetPasswordViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation

@Observable
final class ResetPasswordViewModel {
    enum ResetMethod {
        case email
        case phone
    }

    var method: ResetMethod = .email
    var email = ""
    var phone = ""

    var canSubmit: Bool {
        switch method {
        case .email:
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .phone:
            !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func sendResetLink() {
        // TODO: call auth service
    }
}

@Observable
final class ChooseRoleViewModel {
    var selectedRole: AuthRole = .student

    func continueFlow() {
        // TODO: route based on selectedRole
    }
}

@Observable
final class TeacherIdentityVerificationViewModel {
    var hasTeachingCredentials = false
    var hasGovernmentIDFront = false
    var hasGovernmentIDBack = false
    var hasSelfie = false
    var acceptedTerms = false

    var canSubmit: Bool {
        hasTeachingCredentials &&
        hasGovernmentIDFront &&
        hasGovernmentIDBack &&
        hasSelfie &&
        acceptedTerms
    }

    func uploadTeachingCredentials() {
        // TODO: show document picker
    }

    func uploadGovernmentIDFront() {
        // TODO: show image picker
    }

    func uploadGovernmentIDBack() {
        // TODO: show image picker
    }

    func takeSelfie() {
        // TODO: open camera
    }

    func submitForReview() {
        // TODO: submit verification
    }
}

@Observable
final class TeacherSubjectsViewModel {
    var searchText = ""
    var selectedSubjects: Set<SubjectOption> = []

    let popularSubjects = [
        SubjectOption(title: "General Math", systemImage: "function"),
        SubjectOption(title: "Algebra", systemImage: "x.squareroot"),
        SubjectOption(title: "Geometry", systemImage: "triangle"),
        SubjectOption(title: "Calculus", systemImage: "chart.xyaxis.line"),
        SubjectOption(title: "Statistics", systemImage: "chart.pie"),
        SubjectOption(title: "Trigonometry", systemImage: "angle"),
        SubjectOption(title: "Physics Math", systemImage: "waveform.path.ecg")
    ]

    let advancedSubjects = [
        SubjectOption(title: "Linear Algebra", systemImage: "square.grid.3x3"),
        SubjectOption(title: "Discrete Math", systemImage: "point.3.connected.trianglepath.dotted"),
        SubjectOption(title: "Number Theory", systemImage: "number")
    ]

    var selectedCountText: String {
        "\(selectedSubjects.count)/3 selected"
    }

    var canContinue: Bool {
        !selectedSubjects.isEmpty
    }

    func toggle(_ subject: SubjectOption) {
        if selectedSubjects.contains(subject) {
            selectedSubjects.remove(subject)
        } else if selectedSubjects.count < 3 {
            selectedSubjects.insert(subject)
        }
    }

    func continueOnboarding() {
        // TODO: save subjects
    }

    func skip() {
        // TODO: skip for now
    }
}

@Observable
final class CompleteProfileViewModel {
    var selectedRole: AuthRole = .student
    var fullName = ""
    var phoneNumber = ""
    var age = ""
    var grade = ""

    let grades = [
        "6th Grade",
        "7th Grade",
        "8th Grade",
        "9th Grade",
        "10th Grade",
        "11th Grade",
        "12th Grade"
    ]

    var canContinue: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !grade.isEmpty
    }

    func continueFlow() {
        // TODO: save profile
    }
}

@Observable
final class VerifyPhoneViewModel {
    var phoneNumber = "+1 (555) 000-0000"
    var digits = Array(repeating: "", count: 4)

    var code: String {
        digits.joined()
    }

    var canVerify: Bool {
        code.count == 4
    }

    func resendCode() {
        // TODO: resend SMS
    }

    func changeContactInfo() {
        // TODO: navigate back to edit phone
    }

    func contactSupport() {
        // TODO: open support
    }
}

@Observable
final class PermissionsSetupViewModel {
    var microphoneEnabled = true
    var notificationsEnabled = true

    func continueSetup() {
        // TODO: request permissions
    }

    func limitedMode() {
        // TODO: continue without permissions
    }
}