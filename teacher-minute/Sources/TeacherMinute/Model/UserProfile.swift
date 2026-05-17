//
//  UserProfile.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import Foundation

struct UserProfile: Codable {
  let uid: String
  let email: String
  let fullName: String
  let phoneNumber: String
  let dateOfBirth: Date
  let grade: String
  let role: String   // "student" | "teacher"
  let createdAt: Date
  
  var firestoreData: [String: Any] {
	let iso = ISO8601DateFormatter()
	return [
	  "uid":         uid,
	  "email":       email,
	  "fullName":    fullName,
	  "phoneNumber": phoneNumber,
	  "dateOfBirth": iso.string(from: dateOfBirth),
	  "grade":       grade,
	  "role":        role,
	  "createdAt":   iso.string(from: createdAt),
	]
  }
}

struct UserProfileSummary {
  let uid: String
  let email: String
  let fullName: String
  let phoneNumber: String
  let grade: String
  let role: AuthRole
  let subjects: [String]
  let createdAt: Date?
  let profileImageURL: String
  
  init?(uid: String, data: [String: Any]) {
	let roleString = data["role"] as? String ?? ""
	self.uid = uid
	self.email = data["email"] as? String ?? ""
	self.fullName = data["fullName"] as? String ?? ""
	self.phoneNumber = data["phoneNumber"] as? String ?? ""
	self.grade = data["grade"] as? String ?? ""
	self.profileImageURL = data["profileImageURL"] as? String
	?? data["profilePhotoURL"] as? String
	?? data["photoURL"] as? String
	?? ""
	self.role = roleString == AuthRole.teacher.rawValue ? .teacher : .student
	let subjectSelections = data["subjectSelections"] as? [String: [String]] ?? [:]
	self.subjects = subjectSelections
	  .sorted { $0.key < $1.key }
	  .flatMap { subject, subtopics in
		subtopics.sorted().map { "\(subject): \($0)" }
	  }
	
	if let createdAtString = data["createdAt"] as? String {
	  self.createdAt = ISO8601DateFormatter().date(from: createdAtString)
	} else {
	  self.createdAt = nil
	}
  }
  
  var displayName: String {
	fullName.isEmpty ? LocalizationSupport.localized("Teacher") : fullName
  }
  
  var roleLabel: String {
	role == .teacher ? LocalizationSupport.localized("Math Teacher") : LocalizationSupport.localized("Student")
  }
  
  var memberSinceText: String {
	guard let createdAt else { return LocalizationSupport.localized("Member") }
	let formatter = DateFormatter()
	formatter.dateFormat = "MMM yyyy"
	formatter.locale = LocalizationSupport.currentLocale
	return String(format: LocalizationSupport.localized("Member since %@"), formatter.string(from: createdAt))
  }
}
