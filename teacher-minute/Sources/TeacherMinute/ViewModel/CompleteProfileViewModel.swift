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
  var grade = ""
  var paypalEmail = ""
  
  var isLoading = false
  var isCheckingCompletion = true
  var showMissingPayoutInfoConfirmation = false
  var errorMessage: String?
  var shouldShowPermissionsOnContinue = true
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
				: hasName
	  if hasProfile {
			fullName    = savedName
			phoneNumber = savedPhone
			grade       = data["grade"]       as? String ?? ""
			paypalEmail = data["paypalEmail"] as? String ?? ""
				shouldShowPermissionsOnContinue = false
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
			  dateOfBirth: nil,
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
			shouldShowPermissionsOnContinue = true
			onContinue?()
	  } catch {
		AnalyticsService.shared.recordError(error, context: "saveProfile")
		errorMessage = error.localizedDescription
		isLoading = false
	  }
	}
  }
}
