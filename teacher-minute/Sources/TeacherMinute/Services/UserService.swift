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
	  .setData(profile.firestoreData)
	logger.info("Saved profile for uid: \(profile.uid)")
  }
  
  // MARK: - Fetch raw Firestore document
  
  func fetchRaw(uid: String) async throws -> [String: Any]? {
	let db = Firestore.firestore()
	let snap = try await db.collection("users").document(uid).getDocument()
	guard snap.exists else { return nil }
	return snap.data()
  }
  
  // MARK: - Determine where to resume onboarding
  
  func resumeRoute(uid: String) async throws -> OnboardingResume {
	guard let data = try await fetchRaw(uid: uid) else {
	  return .chooseRole
	}
	
	let roleString = data["role"] as? String ?? ""
	let role: AuthRole = roleString == "teacher" ? .teacher : .student
	
	// Profile completeness: fullName + phoneNumber + dateOfBirth required for both roles
	let hasProfile = !(data["fullName"] as? String ?? "").isEmpty
	&& !(data["phoneNumber"] as? String ?? "").isEmpty
	&& data["dateOfBirth"] != nil
	
	if role == .teacher {
	  // Docs: check uploadedDocuments array has at least 4 entries
	  let docs = data["uploadedDocuments"] as? [String] ?? []
	  let hasIdentityDocs = docs.count >= 4
	  
	  // Subjects: check subjects array is non-empty
	  let subjects = data["subjects"] as? [String] ?? []
	  let hasSubjects = !subjects.isEmpty
	  
	  if !hasIdentityDocs { return .teacherIdentityVerification }
	  if !hasSubjects      { return .teacherSubjects }
	  if !hasProfile       { return .completeProfile(role: .teacher) }
	  return .home(role: .teacher)
	} else {
	  if !hasProfile { return .completeProfile(role: .student) }
	  return .home(role: .student)
	}
  }
}
