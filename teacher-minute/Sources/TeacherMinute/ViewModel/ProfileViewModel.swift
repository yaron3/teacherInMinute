//
//  ProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation
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
    var isVerified = false
    var memberSince = "Member"
    var email = ""
    var phoneNumber = ""
    var grade = ""
    var subjects: [String] = []
    var profileImageURL = ""
    var roleType: AuthRole
    var isLoading = false
    var isEditing = false
    var isUploadingPhoto = false
    var errorMessage: String?
    var microphoneState: PermissionState = .notDetermined
    var cameraState: PermissionState = .notDetermined
    var notificationsState: PermissionState = .notDetermined
    var contactRows: [Parameter] = []

    var shouldShowTeachingDetails: Bool {
        roleType == .teacher
    }

    var gradeLevels: [String] {
        grade.isEmpty ? [] : [grade]
    }

    var subjectsOrPlaceholder: [String] {
        subjects.isEmpty ? ["No subjects added yet"] : subjects
    }

    init(roleType: AuthRole = .student) {
        self.roleType = roleType
        role = roleType == .teacher ? "Math Teacher" : "Student"
        isVerified = roleType == .teacher
        rebuildContactRows()
    }

    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        await refreshPermissions()

        do {
            guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else { return }
            apply(profile)
        } catch {
            errorMessage = "Could not load profile."
            logger.error("[Profile] failed loading profile: \(error.localizedDescription)")
        }
    }

    func editProfile() {
        if isEditing {
            Task { await saveProfileEdits() }
        } else {
            isEditing = true
        }
    }

    func uploadProfileImage(data: Data) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isUploadingPhoto = true
        errorMessage = nil

        Task {
            do {
                let url = try await StorageService.shared.uploadProfileImage(data: data, uid: uid)
                try await UserService.shared.updateProfileFields(uid: uid, fields: [
                    "profileImageURL": url,
                    "updatedAt": ISO8601DateFormatter().string(from: Date())
                ])
                profileImageURL = url
            } catch {
                errorMessage = "Could not upload profile photo."
                logger.error("[Profile] failed uploading profile image: \(error.localizedDescription)")
            }
            isUploadingPhoto = false
        }
    }

    func requestMicrophonePermission() {
        Task {
            if microphoneState == .denied {
                PermissionService.shared.openAppSettings()
            } else {
                microphoneState = await PermissionService.shared.requestCapturePermission(for: .microphone)
            }
        }
    }

    func requestCameraPermission() {
        Task {
            if cameraState == .denied {
                PermissionService.shared.openAppSettings()
            } else {
                cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
            }
        }
    }

    func manageNotifications() {
        Task {
            if notificationsState == .denied {
                PermissionService.shared.openAppSettings()
            } else {
                notificationsState = await PermissionService.shared.requestNotifications()
            }
        }
    }

    func editGradeLevels() {
        isEditing = true
    }

    func editSubjects() {
        // Subject editing is handled by the dedicated teacher-subjects flow.
    }

    func addGradeLevel() {
        isEditing = true
    }

    func logout() {
        // Settings owns logout confirmation and routing.
    }

    private func saveProfileEdits() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        syncFieldsFromRows()

        do {
            try await UserService.shared.updateProfileFields(uid: uid, fields: [
                "fullName": name,
                "email": email,
                "phoneNumber": phoneNumber,
                "grade": grade,
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ])
            isEditing = false
            rebuildContactRows()
        } catch {
            errorMessage = "Could not save profile."
            logger.error("[Profile] failed saving profile edits: \(error.localizedDescription)")
        }
    }

    private func refreshPermissions() async {
        microphoneState = PermissionService.shared.captureStatus(for: .microphone)
        cameraState = PermissionService.shared.captureStatus(for: .camera)
        notificationsState = await PermissionService.shared.notificationStatus()
    }

    private func apply(_ profile: UserProfileSummary) {
        name = profile.fullName.isEmpty ? (profile.role == .teacher ? "Teacher" : "Student") : profile.fullName
        role = profile.roleLabel
        memberSince = profile.memberSinceText
        email = profile.email
        phoneNumber = profile.phoneNumber
        grade = profile.grade
        subjects = profile.subjects
        profileImageURL = profile.profileImageURL
        roleType = profile.role
        isVerified = profile.role == .teacher
        rebuildContactRows()
    }

    private func rebuildContactRows() {
        var rows = [
            Parameter(description: "Full Name", value: name, image: "person.fill"),
            Parameter(description: "Email", value: email, image: "envelope.fill"),
            Parameter(description: "Phone", value: phoneNumber, image: "phone.fill")
        ]

        if roleType == .student {
            rows.append(Parameter(description: "Grade", value: grade, image: "graduationcap.fill"))
        }

        contactRows = rows
    }

    private func syncFieldsFromRows() {
        for row in contactRows {
            let value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch row.description {
            case "Full Name":
                name = value
            case "Email":
                email = value
            case "Phone":
                phoneNumber = value
            case "Grade":
                grade = value
            default:
                break
            }
        }
    }
}
