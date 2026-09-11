//
//  ProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation
import Observation
// Required for @Observable state tracking on Android: without it Skip does
// not wire the class into Compose's reactive state, so mutations never
// invalidate the views reading them. See skip-fuse-ui's README.
import SkipFuse

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
    /// Star average and review count for a teacher, from the backend. Both stay
    /// zero for students and for a teacher nobody has rated yet — `hasRating`
    /// is what the view checks before drawing stars.
    var rating: Double = 0.0
    var reviewCount: Int = 0
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

    // MARK: - Saved PayPal (student payment method)

    /// The email of the student's vaulted PayPal account, or `nil` if none is
    /// saved yet.
    var savedPayPalEmail: String?
    var isSavingPayPal = false
    var payPalVaultErrorMessage: String?

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

    var hasRating: Bool { reviewCount > 0 && rating > 0 }

    var reviewCountText: String { LessonFormatting.reviewCountText(reviewCount) }

    // MARK: - Payout method (teachers)

    /// Where this teacher's payout is sent, loaded from their own user
    /// document. `nil` until it loads, and while none has been set up.
    var payoutMethod: TeacherPayoutMethod?

    var hasPayoutMethod: Bool { payoutMethod != nil }

    /// The method's name — "Bit", "PayPal", "Bank Account".
    var payoutMethodTitle: String {
        payoutMethod?.type.displayName ?? LocalizationSupport.localized("Not set up yet")
    }

    /// The masked destination, e.g. a Bit phone number or a bank account's
    /// last 4 digits.
    var payoutMethodDetail: String {
        payoutMethod?.displaySummary ?? LocalizationSupport.localized("Add where your payouts should be sent")
    }

    var payoutMethodSystemImage: String {
        payoutMethod?.type.systemImage ?? "creditcard"
    }

    var subjectsOrPlaceholder: [String] {
        subjects.isEmpty ? ["No subjects added yet"] : subjects
    }

    var hasDisplayableProfileData: Bool {
        name != "Profile" && role != "User" && !contactRows.isEmpty
    }

    init(roleType: AuthRole = .student, repository: ProfileRepository = FirebaseProfileRepository()) {
        self.roleType = roleType
        self.repository = repository
        // A placeholder only: `apply` replaces it with the label the profile
        // itself implies (which names the teacher's real subjects).
        role = roleType == .teacher
            ? LocalizationSupport.localized("Teacher")
            : LocalizationSupport.localized("Student")
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
                logger.error("[Profile] profile summary was nil uid=\(uid)")
                errorMessage = "Could not load profile."
                return
            }
            logger.info("[Profile] summary fetched role=\(profile.role == .teacher ? "teacher" : "student")")
            apply(profile)
            if profile.role == .teacher {
                isVerified = try await repository.isTeacherVerified(uid: uid)
                let docs = (try? await repository.fetchUploadedDocuments(uid: uid)) ?? []
                hasMissingDocuments = TeacherDocumentsPromptStore.hasMissingDocuments(docs)
                await loadTeacherRating(uid: uid)
                await loadPayoutMethod(uid: uid)
            } else {
                // Comes from the profile document already fetched above — no
                // second round trip just to read one field.
                savedPayPalEmail = profile.savedPayPalEmail.isEmpty ? nil : profile.savedPayPalEmail
            }
            isProfileLoaded = true
            logger.info("[Profile] loaded name=\(self.name) rows=\(self.contactRows.count) displayable=\(self.hasDisplayableProfileData)")
        } catch {
            errorMessage = "Could not load profile."
            isProfileLoaded = false
            logger.error("[Profile] failed loading profile: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.loadProfile")
        }
    }

    /// The teacher's real reputation. A failure leaves it at zero rather than
    /// blocking the profile — the rating row simply does not appear.
    private func loadTeacherRating(uid: String) async {
        do {
            guard let summary = try await repository.fetchTeacherRating(uid: uid) else { return }
            rating = summary.averageRating
            reviewCount = summary.ratingCount
        } catch {
            logger.error("[Profile] failed loading teacher rating: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.loadTeacherRating")
        }
    }

    private func loadPayoutMethod(uid: String) async {
        do {
            payoutMethod = try await repository.fetchPayoutMethod(uid: uid)
        } catch {
            logger.error("[Profile] failed loading payout method: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.loadPayoutMethod")
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

    // MARK: - Edit-form validation

    /// The description carries the localized label, so both spellings are
    /// matched here for the same reason `syncFieldsFromRows` matches both.
    func isPhoneRow(_ row: Parameter) -> Bool {
        row.description == "Phone" || row.description == LocalizationSupport.localized("Phone")
    }

    func isNameRow(_ row: Parameter) -> Bool {
        row.description == "Full Name" || row.description == LocalizationSupport.localized("Full Name")
    }

    private var editedName: String {
        contactRows.first(where: isNameRow)?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// A name is how everyone else identifies this person — in the teacher
    /// list, on an invite, in a lesson header — so an empty one is never a
    /// valid answer. Saving one used to be possible by clearing the field,
    /// which left the app substituting the word "Teacher" or "Student".
    var isNameRowValid: Bool {
        !editedName.isEmpty
    }

    var showsNameRowError: Bool {
        !isNameRowValid
    }

    var nameErrorMessage: String {
        LocalizationSupport.localized("Enter your full name.")
    }

    private var editedPhoneNumber: String {
        contactRows.first(where: isPhoneRow)?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Teachers are paid through this number, so it stays mandatory for them;
    /// for students it is optional, but a number that was typed has to be real.
    var isPhoneRowValid: Bool {
        if editedPhoneNumber.isEmpty {
            return roleType != .teacher
        }
        return editedPhoneNumber.isValidPhoneNumber
    }

    /// Unlike the onboarding form, this one opens on saved data with Save as
    /// its only affordance, so a teacher who has cleared the field is told why
    /// Save is greyed out rather than being left to guess.
    var showsPhoneRowError: Bool {
        !isPhoneRowValid
    }

    var phoneErrorMessage: String {
        LocalizationSupport.localized("Enter a valid phone number.")
    }

    /// Per-row validity, so the edit form does not have to know which fields
    /// are checked or which message belongs to which one.
    func isRowValid(_ row: Parameter) -> Bool {
        if isNameRow(row) { return isNameRowValid }
        if isPhoneRow(row) { return isPhoneRowValid }
        return true
    }

    func rowErrorMessage(for row: Parameter) -> String {
        isNameRow(row) ? nameErrorMessage : phoneErrorMessage
    }

    var canSaveProfileEdits: Bool {
        !isLoading && isNameRowValid && isPhoneRowValid
    }

    func saveProfileEdits() {
        guard isNameRowValid else {
            errorMessage = nameErrorMessage
            return
        }
        guard isPhoneRowValid else {
            errorMessage = phoneErrorMessage
            return
        }
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
                UserPhotoStore.shared.profileImageURL = url
            } catch {
                errorMessage = "Could not upload profile photo."
                logger.error("[Profile] failed uploading profile image: \(error.localizedDescription)")
                AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.uploadProfileImage")
            }
            isUploadingPhoto = false
        }
    }

    func requestMicrophonePermission() {
        // Deferred to the service so this row and the teacher dashboard's
        // readiness row answer a tap the same way. Android needs more than the
        // "not determined, so ask" rule this used to apply: a first denial
        // there can still be re-asked, and only the OS knows when it cannot.
        Task {
            microphoneState = await PermissionService.shared.resolveCapturePermission(for: .microphone)
        }
    }

    func requestCameraPermission() {
        Task {
            cameraState = await PermissionService.shared.resolveCapturePermission(for: .camera)
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

    // MARK: - Saved PayPal

#if canImport(UIKit)
    /// Runs PayPal's login/consent flow and vaults the resulting account, so
    /// future purchases can charge it directly with no PayPal login.
    func addSavedPayPal() async {
        guard !isSavingPayPal else { return }
        isSavingPayPal = true
        payPalVaultErrorMessage = nil
        defer { isSavingPayPal = false }

        do {
            let session = try await FunctionsService.shared.createPayPalVaultClientToken()
            let nonce = try await PayPalVaultService.shared.vaultPayPalAccount(clientToken: session.clientToken)
            let email = try await FunctionsService.shared.savePayPalVault(nonce: nonce)
            savedPayPalEmail = email
            logger.info("[Profile] saved PayPal vault")
        } catch let error as PayPalVaultService.PayPalVaultServiceError {
            if case .cancelled = error {
                logger.info("[Profile] saving PayPal cancelled")
            } else {
                payPalVaultErrorMessage = error.localizedDescription
                logger.error("[Profile] failed saving PayPal: \(error.localizedDescription)")
            }
        } catch {
            payPalVaultErrorMessage = LocalizationSupport.localized("Could not save your PayPal account. Please try again.")
            logger.error("[Profile] failed saving PayPal: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.addSavedPayPal")
        }
    }
#endif

    func removeSavedPayPal() async {
        let previousEmail = savedPayPalEmail
        savedPayPalEmail = nil
        do {
            try await FunctionsService.shared.removeSavedPayPal()
            logger.info("[Profile] removed saved PayPal vault")
        } catch {
            savedPayPalEmail = previousEmail
            payPalVaultErrorMessage = LocalizationSupport.localized("Could not remove your saved PayPal account. Please try again.")
            logger.error("[Profile] failed removing saved PayPal: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "Profile.removeSavedPayPal")
        }
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
        // The real rating arrives from the backend in loadTeacherRating; nothing
        // about a profile document implies a score.
        if profile.role != .teacher {
            rating = 0
            reviewCount = 0
        }
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
                // Stored in the canonical local form so it matches what the
                // payout backend accepts, whatever spelling was typed.
                phoneNumber = value.normalizedPhoneNumber
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
