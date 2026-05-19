//
//  UserService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

// MARK: - Completion state returned after login

enum OnboardingResume {
  case chooseRole                     // no role set yet
  case teacherIdentityVerification    // teacher: docs not uploaded
  case teacherSubjects                // teacher: subjects not chosen
  case completeProfile(role: AuthRole)// profile fields missing
  case home(role: AuthRole)           // fully complete
}

@MainActor
final class UserService {
  static let shared = UserService()
  private init() {}
  
  // MARK: - Save
  
  func saveProfile(_ profile: UserProfile) async throws {
	let db = Firestore.firestore()
	try await db.collection("users")
	  .document(profile.uid)
	  .setData(profile.firestoreData, merge: true)
	logger.info("Saved profile for uid: \(profile.uid)")
  }
  
  // MARK: - Fetch raw Firestore document
  
  func fetchRaw(uid: String) async throws -> [String: Any]? {
	let db = Firestore.firestore()
	let snap = try await db.collection("users").document(uid).getDocument()
	guard snap.exists else { return nil }
	return snap.data()
  }
  
  func fetchProfileSummary(uid: String) async throws -> UserProfileSummary? {
		guard let data = try await fetchRaw(uid: uid) else { return nil }
		return UserProfileSummary(uid: uid, data: data)
  }

  func updateProfileFields(uid: String, fields: [String: String]) async throws {
    guard !fields.isEmpty else { return }
    let db = Firestore.firestore()
    try await db.collection("users").document(uid).setData(fields, merge: true)
    logger.info("Updated profile fields for uid: \(uid)")
  }
  
  func deleteUserData(uid: String) async throws {
	let db = Firestore.firestore()
	try await db.collection("users").document(uid).delete()
	logger.info("Deleted user profile for uid: \(uid)")
  }
  
  // MARK: - Unread messages

  func hasUnreadMessages(uid: String) async -> Bool {
    do {
      let messages = try await NotificationMessageService.shared.fetchMessages(uid: uid)
      return messages.contains { !$0.isRead }
    } catch {
      logger.error("[UserService] failed checking unread messages: \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "UserService.hasUnreadMessages")
      return false
    }
  }

  // MARK: - Determine where to resume onboarding
  
  func resumeRoute(uid: String) async throws -> OnboardingResume {
	guard let data = try await fetchRaw(uid: uid) else {
	  return .chooseRole
	}
	
	let roleString = data["role"] as? String ?? ""
	guard !roleString.isEmpty else { return .chooseRole }
	let role: AuthRole = roleString == "teacher" ? .teacher : .student
	
			let hasName  = !(data["fullName"] as? String ?? "").isEmpty
			let hasPhone = !(data["phoneNumber"] as? String ?? "").isEmpty

		if role == .teacher {
	  let docs = data["uploadedDocuments"] as? [String] ?? []
	  let hasIdentityDocs = docs.count >= 4

	  let subjectSelections = data["subjectSelections"] as? [String: [String]] ?? [:]
	  let hasSubjects = subjectSelections.values.contains { !$0.isEmpty }

	  if !hasIdentityDocs { return .teacherIdentityVerification }
	  if !hasSubjects      { return .teacherSubjects }
			  if !(hasName && hasPhone) { return .completeProfile(role: .teacher) }
		  return .home(role: .teacher)
	} else {
	  let hasProfile = hasName && hasPhone && data["dateOfBirth"] != nil
	  if !hasProfile { return .completeProfile(role: .student) }
	  return .home(role: .student)
	}
  }
}
