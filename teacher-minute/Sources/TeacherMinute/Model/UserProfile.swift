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
  /// Optional: date of birth is collected only from the Profile screen, never
  /// during onboarding, so a brand-new profile has none until the user sets it.
  let dateOfBirth: Date?
  let grade: String
  let paypalEmail: String
  let role: String   // "student" | "teacher"
  let createdAt: Date
  var currency: String = LessonFormatting.defaultCurrencyCode

  var firestoreData: [String: Any] {
	let iso = ISO8601DateFormatter()
	var data: [String: Any] = [
	  "uid":         uid,
	  "email":       email,
	  "fullName":    fullName,
		  "phoneNumber": phoneNumber,
		  "grade":       grade,
		  "paypalEmail": paypalEmail,
		  "role":        role,
		  "createdAt":   iso.string(from: createdAt),
		  "currency":    currency,
		]
	// Only persist a date of birth once the user has actually provided one.
	if let dateOfBirth {
	  data["dateOfBirth"] = iso.string(from: dateOfBirth)
	}
	return data
  }
}

struct UserProfileSummary {
  let uid: String
  let email: String
  let fullName: String
  let phoneNumber: String
  let dateOfBirth: Date?
  let grade: String
  let paypalEmail: String
  let role: AuthRole
  let subjects: [String]
  let createdAt: Date?
  let profileImageURL: String
  let remainingMinutes: Int
  let totalMinutes: Int
  let currency: String

  init?(uid: String, data: [String: Any]) {
	let roleString = data["role"] as? String ?? ""
	self.uid = uid
	self.email = data["email"] as? String ?? ""
		self.fullName = data["fullName"] as? String ?? ""
		self.phoneNumber = data["phoneNumber"] as? String ?? ""
		if let dobString = data["dateOfBirth"] as? String {
		  self.dateOfBirth = ISO8601DateFormatter().date(from: dobString)
		} else {
		  self.dateOfBirth = nil
		}
		self.grade = data["grade"] as? String ?? ""
		self.paypalEmail = data["paypalEmail"] as? String ?? ""
		self.profileImageURL = data["profileImageURL"] as? String
	?? data["profilePhotoURL"] as? String
	?? data["photoURL"] as? String
	?? ""
	self.role = roleString == AuthRole.teacher.rawValue ? .teacher : .student
	let subjectSelections = data["subjectSelections"] as? [String: [String]] ?? [:]
	self.subjects = subjectSelections
	  .sorted { $0.key < $1.key }
	  .flatMap { subject, subtopics in
		subtopics.sorted().map { "\(LocalizationSupport.localized(subject)): \(LocalizationSupport.localized($0))" }
	  }

	if let createdAtString = data["createdAt"] as? String {
	  self.createdAt = ISO8601DateFormatter().date(from: createdAtString)
	} else {
	  self.createdAt = nil
	}

	self.remainingMinutes = Self.intValue(data["remainingMinutes"]) ?? 0
	self.totalMinutes = Self.intValue(data["totalMinutes"]) ?? 0
	let rawCurrency = (data["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
	self.currency = rawCurrency.count == 3 ? rawCurrency : LessonFormatting.defaultCurrencyCode
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Int64 { return Int(value) }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    if let value = value as? Double { return Int(value) }
    return nil
  }
  
  var displayName: String {
	fullName.isEmpty ? LocalizationSupport.localized("Teacher") : fullName
  }
  
  var roleLabel: String {
	role == .teacher ? LocalizationSupport.localized("Math Teacher") : LocalizationSupport.localized("Student")
  }
  
  var dateOfBirthText: String {
	guard let dateOfBirth else { return "" }
	let formatter = DateFormatter()
	formatter.dateStyle = .medium
	formatter.locale = LocalizationSupport.currentLocale
	return formatter.string(from: dateOfBirth)
  }

  var memberSinceText: String {
	guard let createdAt else { return LocalizationSupport.localized("Member") }
	let formatter = DateFormatter()
	formatter.dateFormat = "MMM yyyy"
	formatter.locale = LocalizationSupport.currentLocale
	return String(format: LocalizationSupport.localized("Member since %@"), formatter.string(from: createdAt))
  }
}
