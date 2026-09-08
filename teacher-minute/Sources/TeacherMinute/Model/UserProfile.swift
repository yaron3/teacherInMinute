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
  let rawSubjectKeys: [String]   // English normalized, e.g. ["algebra", "geometry"] — used for RTDB matching
  /// The subject areas as stored (English titles, e.g. ["Math", "Physics"]),
  /// without their subtopics — what a teacher is introduced as.
  let subjectAreaTitles: [String]
  let createdAt: Date?
  let profileImageURL: String
  let remainingMinutes: Int
  let totalMinutes: Int
  let currency: String
  /// Email of the student's vaulted PayPal account, empty when none is saved.
  /// Read from the same document rather than re-fetched, so showing it costs
  /// no extra round trip.
  let savedPayPalEmail: String

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
		let areaTitle = LocalizationSupport.localized(SubjectPresentation.displayTitle(for: subject))
		return subtopics.sorted().map { "\(areaTitle): \(LocalizationSupport.localized($0))" }
	  }
	// English normalized keys for RTDB: stored subtopic values are English (e.g. "Algebra"),
	// so normalizing them always produces locale-independent keys (e.g. "algebra").
	self.rawSubjectKeys = subjectSelections
	  .flatMap { _, subtopics in subtopics }
	  .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
	self.subjectAreaTitles = subjectSelections.keys.sorted()

	if let createdAtString = data["createdAt"] as? String {
	  self.createdAt = ISO8601DateFormatter().date(from: createdAtString)
	} else {
	  self.createdAt = nil
	}

	self.remainingMinutes = Self.intValue(data["remainingMinutes"]) ?? 0
	self.totalMinutes = Self.intValue(data["totalMinutes"]) ?? 0
	let rawCurrency = (data["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
	self.currency = rawCurrency.count == 3 ? rawCurrency : LessonFormatting.defaultCurrencyCode

	let savedPayPal = data["savedPayPal"] as? [String: Any]
	self.savedPayPalEmail = (savedPayPal?["email"] as? String) ?? ""
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
  
  /// How the user is introduced. A teacher is named by the subjects they
  /// actually chose rather than assumed to teach maths.
  var roleLabel: String {
	guard role == .teacher else { return LocalizationSupport.localized("Student") }
	let areas = subjectAreaTitles.map { LocalizationSupport.localized(SubjectPresentation.displayTitle(for: $0)) }
	guard !areas.isEmpty else { return LocalizationSupport.localized("Teacher") }
	return String(format: LocalizationSupport.localized("%@ Teacher"), areas.joined(separator: ", "))
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
