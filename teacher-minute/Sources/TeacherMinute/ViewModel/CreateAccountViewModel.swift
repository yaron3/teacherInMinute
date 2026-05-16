//
//  CreateAccountViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation

// MARK: - Validation errors

enum SignupValidationError: LocalizedError {
  case invalidEmail
  case passwordTooShort
  case termsNotAccepted
  
  var errorDescription: String? {
	switch self {
	  case .invalidEmail:       return "Please enter a valid email address."
	  case .passwordTooShort:   return "Password must be at least 6 characters."
	  case .termsNotAccepted:   return "You must agree to the Terms of Service and Privacy Policy to continue."
	}
  }
  
  /// Which field to focus after showing the alert
  var focusField: SignupField? {
	switch self {
	  case .invalidEmail:     return .email
	  case .passwordTooShort: return .password
	  case .termsNotAccepted: return nil
	}
  }
}

enum SignupField: Hashable {
  case email, password
}

// MARK: - ViewModel

@Observable
@MainActor
final class CreateAccountViewModel {
  var emailOrPhone    = ""
  var password        = ""
  var agreedToTerms   = true
  var sendUpdates     = false
  var isLoading       = false
  var navigateToChooseRole = false
  
  // Alert state
  var alertMessage: String?
  var showAlert       = false
  var focusField: SignupField?
  
  let authService = AuthService()
  
  // MARK: - Derived
  
  var isEmailValid: Bool {
	emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmail
  }
  
  var isPasswordValid: Bool {
	password.count >= 6
  }
  
  /// True only when ALL rules pass — used to enable/disable the button
  var canSubmit: Bool {
	isEmailValid && isPasswordValid && agreedToTerms && !isLoading
  }
  
  // MARK: - Signup
  
  func signup() async {
	// Validate in order and surface first failure
	if !isEmailValid {
	  present(error: .invalidEmail)
	  return
	}
	if !isPasswordValid {
	  present(error: .passwordTooShort)
	  return
	}
	if !agreedToTerms {
	  present(error: .termsNotAccepted)
	  return
	}
	
	isLoading = true
	defer { isLoading = false }
	
	do {
	  _ = try await authService.createUser(email: emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines),
										   password: password)
	  navigateToChooseRole = true
	} catch {
	  alertMessage = error.localizedDescription
	  showAlert = true
	}
  }
  
  // MARK: - Social
  
  func signupWithGoogle() {
#if canImport(UIKit)
	iOSGoogleSignInProvider().signIn { result in
	  switch result {
		case .success(let credential):
		  print("Google sign up successful: \(credential)")
		case .failure(let error):
		  print("Google sign up failed: \(error)")
	  }
	}
#endif
#if os(Android)
		print("Android Google sign-up tapped")
		Task {
		  do {
			_ = try await AndroidGoogleAuth().signIn()
			navigateToChooseRole = true
		  } catch {
			alertMessage = error.localizedDescription
			showAlert = true
		  }
		}
#endif
  }
  
  func signupWithApple() {
#if canImport(UIKit)
		iOSAppleSignInProvider().signIn { [weak self] result in
		  switch result {
			case .success:
			  Task { @MainActor in self?.navigateToChooseRole = true }
			case .failure(let error):
			  Task { @MainActor in
				self?.alertMessage = error.localizedDescription
				self?.showAlert = true
			  }
		  }
		}
#elseif os(Android)
		print("Android Apple sign-up tapped")
		Task {
		  do {
			_ = try await AndroidAppleAuth().signIn()
			navigateToChooseRole = true
		  } catch {
			alertMessage = error.localizedDescription
			showAlert = true
		  }
		}
#endif
  }
  
  // MARK: - Helpers
  
  private func present(error: SignupValidationError) {
	alertMessage = error.errorDescription
	showAlert    = true
	focusField   = error.focusField
  }
}
