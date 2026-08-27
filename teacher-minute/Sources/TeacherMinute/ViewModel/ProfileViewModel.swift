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
    private let repository: ProfileRepository
    var name = "Profile"
    var role = "User"
    var isVerified = false
    var memberSince = "Member"
    var email = ""
    var phoneNumber = ""
    var username = ""
    var rating: Double = 0.0
    var grade = ""
    /// Date of birth is collected only here in Profile (never during onboarding).
    /// `nil` means the student has not provided one, so it is never shown to a teacher.
    var dateOfBirth: Date?
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
    /// Whether the teacher still has verification documents left to upload
    /// (only the front ID is mandatory during onboarding — bug #24).
    var hasMissingDocuments = false

    var nameInitial: String {
        name.first.map(String.init) ?? ""
    }

    /// Formatted date of birth for display, or empty when it has not been set.
    var dateOfBirthDisplay: String {
        guard let dateOfBirth else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = LocalizationSupport.currentLocale
        return formatter.string(from: dateOfBirth)
    }

  var availableCurrencies: [String] {
	[LocalizationSupport.localized("ils"), LocalizationSupport.localized("usd")]
  }

  var availableStudentGrades: [String] {
	(1...12).map { LocalizationSupport.localized("Grade \($0)") }
	  + [LocalizationSupport.localized("College"), LocalizationSupport.localized("Adult Learner")]
  }

    var shouldShowTeachingDetails: Bool {
        roleType == .teacher
    }
  
	var shouldShowTeacherPaymentsMethod: Bool {
		roleType == .teacher
	}
  var shouldShowStudentPaymentsMethod: Bool {
	roleType == .student
  }
    /// Canonical grade values, as stored on the profile. Selection and saving
    /// both key off these, so they stay English in every language.
    var gradeLevels: [String] {
        teacherGradeLevels(from: grade)
    }

    /// The same grades, translated for display only.
    var gradeLevelLabels: [String] {
        gradeLevels.map(LocalizationSupport.localizedGradeLabel)
    }
  var paymentsMethdsLabels: [String] {
	[LocalizationSupport.localized("PayPal")]
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

    init(roleType: AuthRole = .student, repository: ProfileRepository = FirebaseProfileRepository()) {
        self.roleType = roleType
        self.repository = repository
        role = roleType == .teacher ? "Math Teacher" : "Student"
        isVerified = false
        rebuildContactRows()
    }

    func loadProfile() async {
        guard let uid = repository.currentUserId else {
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
            guard let profile = try await repository.fetchProfileSummary(uid: uid) else {
                errorMessage = "Could not load profile."
                return
            }
            apply(profile)
            if profile.role == .teacher {
                isVerified = try await repository.isTeacherVerified(uid: uid)
                let docs = (try? await repository.fetchUploadedDocuments(uid: uid)) ?? []
                hasMissingDocuments = TeacherDocumentsPromptStore.hasMissingDocuments(docs)
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
            var fields: [String: String] = [
                "fullName": name,
                "email": email,
                "phoneNumber": phoneNumber,
                "grade": grade,
                "currency": currency,
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ]
            // Persist the date of birth only once the student has actually set one.
            if let dateOfBirth {
                fields["dateOfBirth"] = ISO8601DateFormatter().string(from: dateOfBirth)
            }
            try await UserService.shared.updateProfileFields(uid: uid, fields: fields)
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
        username = profile.email.components(separatedBy: "@").first ?? ""
        rating = profile.role == .teacher ? 4.9 : 0.0
        grade = profile.grade
        dateOfBirth = profile.dateOfBirth
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
            rows.append(Parameter(description: LocalizationSupport.localized("Date of Birth"), value: dateOfBirthDisplay, image: "calendar"))
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
