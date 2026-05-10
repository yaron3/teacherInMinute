//
//  ProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@Observable
@MainActor
final class ProfileViewModel {
    var name = "Profile"
    var role = "User"
    var isVerified = true
    var memberSince = "Member"
    var email = ""
    var phoneNumber = ""
    var grade = ""
    var subjects: [String] = []
    var roleType: AuthRole = .student
    var isLoading = false

    var microphoneEnabled = true
    var notificationsEnabled = false
    
    var shouldShowTeachingDetails: Bool {
        roleType == .teacher
    }
    
    var gradeLevels: [String] {
        grade.isEmpty ? [] : [grade]
    }
    
    var subjectsOrPlaceholder: [String] {
        subjects.isEmpty ? ["No subjects added yet"] : subjects
    }
    
    var contactRows: [(title: String, value: String, icon: String)] {
        [
            ("Email", email.isEmpty ? "Not provided" : email, "envelope.fill"),
            ("Phone", phoneNumber.isEmpty ? "Not provided" : phoneNumber, "phone.fill")
        ]
    }
    
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else { return }
            name = profile.displayName
            role = profile.roleLabel
            memberSince = profile.memberSinceText
            email = profile.email
            phoneNumber = profile.phoneNumber
            grade = profile.grade
            subjects = profile.subjects
            roleType = profile.role
            isVerified = profile.role == .teacher
        } catch {
            logger.error("[Profile] failed loading profile: \(error.localizedDescription)")
        }
    }

    func editProfile() {
        // TODO: edit profile
    }

    func changePhoto() {
        // TODO: image picker
    }

    func editGradeLevels() {
        // TODO
    }

    func editSubjects() {
        // TODO
    }

    func addGradeLevel() {
        // TODO
    }

    func manageNotifications() {
        // TODO
    }

    func logout() {
        // TODO
    }
}
