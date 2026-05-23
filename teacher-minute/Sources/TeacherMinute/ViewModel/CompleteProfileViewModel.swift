//
//  CompleteProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
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
final class CompleteProfileViewModel {
  let role: AuthRole
  var fullName = ""
  var phoneNumber = ""
  /// Default start = 15 years ago
  var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -15, to: Date()) ?? Date()
  var grade = ""
  var paypalEmail = ""
  
  var isLoading = false
  var isCheckingCompletion = true
  var showMissingPayoutInfoConfirmation = false
  var errorMessage: String?
  var onContinue: (() -> Void)?
  
  let grades: [String] = (1...12).map { LocalizationSupport.localized("Grade \($0)") } + [LocalizationSupport.localized("College"), LocalizationSupport.localized("Adult Learner")]
  
  var canContinue: Bool {
	let hasName = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	guard !isLoading, hasName else { return false }
	if role == .student {
	  // Phone is optional for students.
	  return true
	}
	guard !phoneNumber.isEmpty else { return false }
	let trimmedPayPalEmail = paypalEmail.trimmingCharacters(in: .whitespacesAndNewlines)
	return trimmedPayPalEmail.isEmpty || trimmedPayPalEmail.isEmail
  }
  
  init(role: AuthRole) {
	self.role = role
  }
  
  // MARK: - Auto-advance
  
  func checkAndAutoAdvance() {
	Task {
	  defer { isCheckingCompletion = false }
	  guard let uid = Auth.auth().currentUser?.uid else { return }
	  let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
	  let savedName  = data["fullName"]    as? String ?? ""
	  let savedPhone = data["phoneNumber"] as? String ?? ""
	  let hasName  = !savedName.isEmpty
	  let hasPhone = !savedPhone.isEmpty
	  let hasProfile = role == .teacher
				? (hasName && hasPhone)
				: (hasName && data["dateOfBirth"] != nil)
	  if hasProfile {
			fullName    = savedName
			phoneNumber = savedPhone
			grade       = data["grade"]       as? String ?? ""
			paypalEmail = data["paypalEmail"] as? String ?? ""
			onContinue?()
	  } else {
			if fullName.isEmpty {
			  if hasName {
				fullName = savedName
			  } else {
				let providerName = (Auth.auth().currentUser?.displayName ?? "")
				  .trimmingCharacters(in: .whitespacesAndNewlines)
				if !providerName.isEmpty {
				  fullName = providerName
				}
			  }
			}
			if phoneNumber.isEmpty && hasPhone {
			  phoneNumber = savedPhone
			}
			if grade.isEmpty {
			  let savedGrade = data["grade"] as? String ?? ""
			  if !savedGrade.isEmpty {
				grade = savedGrade
			  }
			}
			if paypalEmail.isEmpty {
			  let savedPayPal = data["paypalEmail"] as? String ?? ""
			  if !savedPayPal.isEmpty {
				paypalEmail = savedPayPal
			  }
			}
	  }
	}
  }
  
  // MARK: - Save & continue
  
  func continueFlow() {
	guard canContinue else { return }
	if role == .teacher && paypalEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
	  showMissingPayoutInfoConfirmation = true
	  return
	}
	saveAndContinue()
  }

  func continueWithoutPayoutInfo() {
	showMissingPayoutInfoConfirmation = false
	saveAndContinue()
  }

  // MARK: - Grade ⇄ Date of Birth suggestion
  //
  // First grade starts when a student is at least 5 years 10 months old
  // on September 1 of the academic year. We use that cutoff to map between
  // DOB and grade in both directions.

  /// Latest allowed DOB: must be at least 5y10m old on Sept 1 of the current
  /// academic year (i.e. eligible for 1st grade).
  var maxDateOfBirth: Date {
	let cal = Calendar.current
	let sept1 = currentAcademicYearStart()
	return cal.date(byAdding: .month, value: -70, to: sept1) ?? sept1
  }

  func suggestGradeFromDOB() {
	guard role == .student else { return }
	guard let suggested = suggestedGrade(for: dateOfBirth) else { return }
	if grade != suggested {
	  grade = suggested
	}
  }

  func suggestDOBFromGrade() {
	guard role == .student else { return }
	// If current DOB already maps to this grade, leave it — the user may
	// have entered a more specific birthday.
	if let mapped = suggestedGrade(for: dateOfBirth), mapped == grade {
	  return
	}
	guard let suggested = suggestedDOB(for: grade) else { return }
	dateOfBirth = suggested
  }

  private func currentAcademicYearStart(now: Date = Date()) -> Date {
	let cal = Calendar.current
	let comps = cal.dateComponents([.year, .month], from: now)
	let year = comps.year ?? 2026
	let month = comps.month ?? 1
	let academicYear = month >= 9 ? year : year - 1
	return cal.date(from: DateComponents(year: academicYear, month: 9, day: 1)) ?? now
  }

  private func suggestedGrade(for dob: Date) -> String? {
	let cal = Calendar.current
	let sept1 = currentAcademicYearStart()
	let comps = cal.dateComponents([.month], from: dob, to: sept1)
	let months = comps.month ?? 0
	// Minimum age for 1st grade: 5y10m = 70 months on Sept 1.
	if months < 70 { return nil }
	let gradeNum = (months - 70) / 12 + 1
	if gradeNum >= 1 && gradeNum <= 12 {
	  let idx = gradeNum - 1
	  if idx < grades.count { return grades[idx] }
	} else if gradeNum >= 13 && gradeNum <= 16 {
	  // Roughly ages 17–20 → College
	  if grades.count > 12 { return grades[12] }
	} else if gradeNum > 16 {
	  if grades.count > 13 { return grades[13] }
	}
	return nil
  }

  private func suggestedDOB(for grade: String) -> Date? {
	guard let idx = grades.firstIndex(of: grade) else { return nil }
	// Only suggest a DOB for numeric grades 1–12.
	if idx > 11 { return nil }
	let gradeNum = idx + 1
	let cal = Calendar.current
	let sept1 = currentAcademicYearStart()
	// Middle of the age range for the grade: 5y10m + (G-1) years + 6 months
	let monthsBack = (gradeNum - 1) * 12 + 76
	return cal.date(byAdding: .month, value: -monthsBack, to: sept1)
  }

  private func saveAndContinue() {
	isLoading = true
	
	Task {
	  do {
		guard let user = Auth.auth().currentUser else {
		  errorMessage = "No authenticated user found."
		  isLoading = false
		  return
		}
		
		let profile = UserProfile(
		  uid:         user.uid,
		  email:       user.email ?? "",
		  fullName:    fullName,
			  phoneNumber: phoneNumber,
			  dateOfBirth: dateOfBirth,
			  grade:       grade,
			  paypalEmail: paypalEmail.trimmingCharacters(in: .whitespacesAndNewlines),
			  role:        role.rawValue,
			  createdAt:   Date()
			)
		
		try await UserService.shared.saveProfile(profile)
		AnalyticsService.shared.logEvent(AnalyticsEvent.profileCompleted, parameters: [
		  "role": role.rawValue,
		  "has_grade": !grade.isEmpty,
		  "has_paypal": !paypalEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		])
		isLoading = false
		onContinue?()
	  } catch {
		AnalyticsService.shared.recordError(error, context: "saveProfile")
		errorMessage = error.localizedDescription
		isLoading = false
	  }
	}
  }
}
