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
    var isProfileLoaded = false
    var isEditing = false
    var isUploadingPhoto = false
    var errorMessage: String?
    var microphoneState: PermissionState = .notDetermined
    var cameraState: PermissionState = .notDetermined
    var notificationsState: PermissionState = .notDetermined
    var contactRows: [Parameter] = []
    var currency: String = LessonFormatting.defaultCurrencyCode

    static let availableCurrencies: [String] = ["ILS", "USD"]

    var shouldShowTeachingDetails: Bool {
        roleType == .teacher
    }

    var gradeLevels: [String] {
        teacherGradeLevels(from: grade)
    }

    var selectedTeachingGrades: Set<String> {
        get {
            Set(gradeLevels)
        }
        set {
            grade = Self.availableTeachingGrades
                .filter { newValue.contains($0) }
                .joined(separator: ", ")
        }
    }

    static let availableTeachingGrades: [String] = (1...12).map { "Grade \($0)" }

    var subjectsOrPlaceholder: [String] {
        subjects.isEmpty ? ["No subjects added yet"] : subjects
    }

    var hasDisplayableProfileData: Bool {
        name != "Profile" && role != "User" && !contactRows.isEmpty
    }

    init(roleType: AuthRole = .student) {
        self.roleType = roleType
        role = roleType == .teacher ? "Math Teacher" : "Student"
        isVerified = false
        rebuildContactRows()
    }

    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Could not load profile."
            isProfileLoaded = false
			isLoading = false
            return
        }
        isLoading = true
        isProfileLoaded = false
        errorMessage = nil
        defer { isLoading = false }

        await refreshPermissions()

        do {
		  logger.info("[Profile] loading profile")
		  isProfileLoaded = false
            guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else {
                errorMessage = "Could not load profile."
                return
            }
            apply(profile)
            if profile.role == .teacher {
                isVerified = (try? await UserService.shared.isTeacherVerified(uid: uid)) ?? false
            }
            isProfileLoaded = true
        } catch {
            errorMessage = "Could not load profile."
            isProfileLoaded = false
            logger.error("[Profile] failed loading profile: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.loadProfile")
        }
    }

    func editProfile() {
        isEditing = true
        rebuildContactRows()
    }

    func cancelProfileEditing() {
        isEditing = false
        errorMessage = nil
        rebuildContactRows()
    }

    func saveProfileEdits() {
        Task { await persistProfileEdits() }
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
                AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.uploadProfileImage")
            }
            isUploadingPhoto = false
        }
    }

    func requestMicrophonePermission() {
        Task {
            if microphoneState == .notDetermined {
                microphoneState = await PermissionService.shared.requestCapturePermission(for: .microphone)
            } else {
                PermissionService.shared.openAppSettings()
            }
        }
    }

    func requestCameraPermission() {
        Task {
            if cameraState == .notDetermined {
                cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
            } else {
                PermissionService.shared.openAppSettings()
            }
        }
    }

    func manageNotifications() {
        Task {
            if notificationsState == .notDetermined {
                notificationsState = await PermissionService.shared.requestNotifications()
            } else {
                PermissionService.shared.openAppSettings()
            }
        }
    }

    func editGradeLevels() {
        editProfile()
    }

    func editSubjects() {
        // Subject editing is handled by the dedicated teacher-subjects flow.
    }

    func addGradeLevel() {
        editProfile()
    }

    func logout() {
        // Settings owns logout confirmation and routing.
    }

    private func persistProfileEdits() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        syncFieldsFromRows()
        isLoading = true
        defer { isLoading = false }

        do {
            try await UserService.shared.updateProfileFields(uid: uid, fields: [
                "fullName": name,
                "email": email,
                "phoneNumber": phoneNumber,
                "grade": grade,
                "currency": currency,
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ])
            isEditing = false
            rebuildContactRows()
        } catch {
            errorMessage = "Could not save profile."
            logger.error("[Profile] failed saving profile edits: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.saveProfileEdits")
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
        currency = profile.currency
        isVerified = false
        rebuildContactRows()
    }

    private func rebuildContactRows() {
        var rows = [
            Parameter(description: LocalizationSupport.localized("Full Name"), value: name, image: "person.fill"),
            Parameter(description: LocalizationSupport.localized("Email"), value: email, image: "envelope.fill"),
            Parameter(description: LocalizationSupport.localized("Phone"), value: phoneNumber, image: "phone.fill")
        ]

        if roleType == .student {
            rows.append(Parameter(description: LocalizationSupport.localized("Grade"), value: LocalizationSupport.localized(grade), image: "graduationcap.fill"))
        }

        contactRows = rows
    }

    private func syncFieldsFromRows() {
        for row in contactRows {
            let value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = row.description
            if description == "Full Name" || description == LocalizationSupport.localized("Full Name") {
                name = value
            } else if description == "Email" || description == LocalizationSupport.localized("Email") {
                email = value
            } else if description == "Phone" || description == LocalizationSupport.localized("Phone") {
                phoneNumber = value
            } else if description == "Grade" || description == LocalizationSupport.localized("Grade") {
                grade = value
            }
        }
    }

    private func teacherGradeLevels(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
