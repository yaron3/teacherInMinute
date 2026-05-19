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
  
  let grades: [String] = (1...12).map { "Grade \($0)" } + ["College", "Adult Learner"]
  
  var canContinue: Bool {
	let hasBaseProfile = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
	!phoneNumber.isEmpty &&
	!isLoading
	guard role == .teacher else { return hasBaseProfile }
	let trimmedPayPalEmail = paypalEmail.trimmingCharacters(in: .whitespacesAndNewlines)
	return hasBaseProfile && (trimmedPayPalEmail.isEmpty || trimmedPayPalEmail.isEmail)
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
	  let hasName  = !(data["fullName"] as? String ?? "").isEmpty
	  let hasPhone = !(data["phoneNumber"] as? String ?? "").isEmpty
	  let hasProfile = role == .teacher
				? (hasName && hasPhone)
				: (hasName && hasPhone && data["dateOfBirth"] != nil)
	  if hasProfile {
			fullName    = data["fullName"]    as? String ?? ""
			phoneNumber = data["phoneNumber"] as? String ?? ""
			grade       = data["grade"]       as? String ?? ""
			paypalEmail = data["paypalEmail"] as? String ?? ""
			onContinue?()
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
