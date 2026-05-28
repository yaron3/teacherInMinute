//
//  CreateAccountViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

// MARK: - Validation errors

enum SignupValidationError: LocalizedError {
  case invalidEmail
  case passwordTooShort
  case termsNotAccepted
  
  
  
  var errorDescription: String? {
	switch self {
	  case .invalidEmail:       return LocalizationSupport.localized("Please enter a valid email address.")
	  case .passwordTooShort:   return LocalizationSupport.localized("Password must be at least 6 characters.")
	  case .termsNotAccepted:   return LocalizationSupport.localized("You must agree to the Terms of Service and Privacy Policy to continue.")
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
  var agreedToTerms   = false
  var sendUpdates     = false
  var isLoading       = false
  var navigateToChooseRole = false

  var destination: OnboardingResume?

  var termsURL: URL?
  var privacyURL: URL?
  var showingTerms = false
  var showingPrivacy = false
  var showLegalAlert = false
  var legalAlertMessage = ""
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
  
  func openTerms() {
	termsURL = URL(string: RemoteConfigService.getLocalizedString(for: .eulaURL))
	if termsURL != nil {
	  showingTerms = true
	  return
	}
	
	legalAlertMessage = SettingsError.missingLegalURL("EULA").localizedDescription
	showLegalAlert = true
  }
  
   func openPrivacy() {
	privacyURL = URL(string: RemoteConfigService.getLocalizedString(for: .privacyPolicyURL))
	if privacyURL != nil {
	  showingPrivacy = true
	  return
	}
	
	legalAlertMessage = SettingsError.missingLegalURL(LocalizationSupport.localized("Privacy Policy")).localizedDescription
	showLegalAlert = true
  }
  // MARK: - Signup
  
  func signup() async {
	// Validate in order and surface first failure
	if !isEmailValid {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": "invalid_email"])
	  present(error: .invalidEmail)
	  return
	}
	if !isPasswordValid {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": "password_too_short"])
	  present(error: .passwordTooShort)
	  return
	}
	if !agreedToTerms {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": "terms_not_accepted"])
	  present(error: .termsNotAccepted)
	  return
	}

	isLoading = true
	defer { isLoading = false }

	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "email", "send_updates": sendUpdates])

	do {
	  _ = try await authService.createUser(email: emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines),
										   password: password)
	  if let uid = Auth.auth().currentUser?.uid {
		AnalyticsService.shared.setUser(uid: uid)
	  }
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpSuccess, parameters: ["method": "email"])
	  navigateToChooseRole = true
	} catch {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": error.localizedDescription])
	  AnalyticsService.shared.recordError(error, context: "signup")
	  alertMessage = error.localizedDescription
	  showAlert = true
	}
  }
  
  // MARK: - Social
  
  func signupWithGoogle() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "google"])
#if canImport(UIKit)
	iOSGoogleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			await self?.resolveRouteAfterSocialSignIn(method: "google")
		  }
		case .failure(let error):
		  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "google", "reason": error.localizedDescription])
		  Task { @MainActor in
			self?.alertMessage = error.localizedDescription
			self?.showAlert = true
		  }
	  }
	}
#endif
#if os(Android)
		logger.info("Android Google sign-up tapped")
		Task {
		  do {
			_ = try await AndroidGoogleAuth().signIn()
			await resolveRouteAfterSocialSignIn(method: "google")
		  } catch {
			AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "google", "reason": error.localizedDescription])
			alertMessage = error.localizedDescription
			showAlert = true
		  }
		}
#endif
  }

  func signupWithApple() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "apple"])
#if canImport(UIKit)
		iOSAppleSignInProvider().signIn { [weak self] result in
		  switch result {
			case .success:
			  Task { @MainActor in
				await self?.resolveRouteAfterSocialSignIn(method: "apple")
			  }
			case .failure(let error):
			  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "apple", "reason": error.localizedDescription])
			  Task { @MainActor in
				self?.alertMessage = error.localizedDescription
				self?.showAlert = true
			  }
		  }
		}
#elseif os(Android)
		logger.info("Android Apple sign-up tapped")
		Task {
		  do {
			_ = try await AndroidAppleAuth().signIn()
			await resolveRouteAfterSocialSignIn(method: "apple")
		  } catch {
			AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "apple", "reason": error.localizedDescription])
			alertMessage = error.localizedDescription
			showAlert = true
		  }
		}
#endif
  }

  private func resolveRouteAfterSocialSignIn(method: String) async {
	guard let uid = Auth.auth().currentUser?.uid else {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": method, "reason": "no_session"])
	  alertMessage = "Could not retrieve user session. Please try again."
	  showAlert = true
	  return
	}
	AnalyticsService.shared.setUser(uid: uid)
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpSuccess, parameters: ["method": method])
	do {
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  destination = resume
	} catch {
	  alertMessage = error.localizedDescription
	  showAlert = true
	}
  }
  
  // MARK: - Helpers
  
  private func present(error: SignupValidationError) {
	alertMessage = error.errorDescription
	showAlert    = true
	focusField   = error.focusField
  }
}
