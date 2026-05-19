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
		!phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
  }
  
  func sendResetLink() {
	let typeRest = method == .email ? "email" : "phone"
	Task { @MainActor in
	  AnalyticsService.shared.logEvent(AnalyticsEvent.passwordResetSent, parameters: ["method": typeRest])
	}
	// TODO: call auth service
  }
}
