//
//  ResetPasswordViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation

@Observable
final class ResetPasswordViewModel {
  enum ResetMethod {
	case email
	case phone
  }
  
  var method: ResetMethod = .email
  var email = ""
  var phone = ""
  
  var canSubmit: Bool {
	switch method {
	  case .email:
		!email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	  case .phone:
		phone.trimmingCharacters(in: .whitespacesAndNewlines).isValidPhoneNumber
	}
  }

  /// Quiet until something has been typed, so the field does not open in red.
  var showsPhoneError: Bool {
	let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
	return !trimmedPhone.isEmpty && !trimmedPhone.isValidPhoneNumber
  }

  var phoneErrorMessage: String {
	LocalizationSupport.localized("Enter a valid phone number.")
  }
  
  func sendResetLink() {
	let typeRest = method == .email ? "email" : "phone"
	Task { @MainActor in
	  AnalyticsService.shared.logEvent(AnalyticsEvent.passwordResetSent, parameters: ["method": typeRest])
	}
	// TODO: call auth service
  }
}
