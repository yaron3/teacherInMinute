//
//  CreateAccountViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

// MARK: - Validation errors

enum SignupValidationError: LocalizedError {
  case invalidEmail
  case passwordTooShort
  case passwordsDoNotMatch
  case termsNotAccepted
  
  
  
  var errorDescription: String? {
	switch self {
	  case .invalidEmail:         return LocalizationSupport.localized("Please enter a valid email address.")
	  case .passwordTooShort:     return LocalizationSupport.localized("Password must be at least 6 characters.")
	  case .passwordsDoNotMatch:  return LocalizationSupport.localized("Passwords do not match.")
	  case .termsNotAccepted:     return LocalizationSupport.localized("You must agree to the Terms of Service and Privacy Policy to continue.")
	}
  }
  
  /// The reason reported to analytics for a failed sign-up.
  var analyticsReason: String {
	switch self {
	  case .invalidEmail:         return "invalid_email"
	  case .passwordTooShort:     return "password_too_short"
	  case .passwordsDoNotMatch:  return "passwords_do_not_match"
	  case .termsNotAccepted:     return "terms_not_accepted"
	}
  }

  /// Which field to focus after showing the alert
  var focusField: SignupField? {
	switch self {
	  case .invalidEmail:        return .email
	  case .passwordTooShort:    return .password
	  // Focus the confirmation, not the password: the first entry is the one
	  // they meant, so that is the field to correct.
	  case .passwordsDoNotMatch: return .confirmPassword
	  case .termsNotAccepted:    return nil
	}
  }
}

enum SignupField: Hashable {
  case email, password, confirmPassword
}

// MARK: - ViewModel

@Observable
@MainActor
final class CreateAccountViewModel {
  var emailOrPhone    = ""
  var password        = ""
  var confirmPassword = ""
  var agreedToTerms   = false
  var sendUpdates     = false
  var isLoading       = false

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
  
  /// The two entries agree. Compared verbatim — a password's leading or
  /// trailing spaces are part of it, so trimming here would let a genuine
  /// mismatch through.
  var doPasswordsMatch: Bool {
	!confirmPassword.isEmpty && confirmPassword == password
  }
  
  /// True only when ALL rules pass — used to enable/disable the button
  var canSubmit: Bool {
	isEmailValid && isPasswordValid && doPasswordsMatch && agreedToTerms && !isLoading
  }

  /// The fields are right and only the terms are missing: the one reason the
  /// disabled Continue has that no field already shows.
  var showsAcceptTermsHint: Bool {
	isEmailValid && isPasswordValid && doPasswordsMatch && !agreedToTerms
  }

  func openTerms() {
	Task {
	  termsURL = await legalURL(for: .eulaURL, page: "eula")
	  showingTerms = true
	}
  }

  func openPrivacy() {
	Task {
	  privacyURL = await legalURL(for: .privacyPolicyURL, page: "privacypolicy")
	  showingPrivacy = true
	}
  }

  /// The published page for `key`. On a first launch whose Remote Config
  /// fetch outlasted the launch gate the value is not there yet, so the link
  /// waits for the fetch, and failing that opens the page on the site, which
  /// is where Remote Config points anyway (`<page>.html`, `<page>_he.html`).
  private func legalURL(for key: RemoteConfigKey, page: String) async -> URL {
	if let url = URL(string: RemoteConfigService.getLocalizedString(for: key)) { return url }
	await RemoteConfigService.shared.ready()
	if let url = URL(string: RemoteConfigService.getLocalizedString(for: key)) { return url }
	logger.info("[CreateAccount] no Remote Config value for \(key.rawValue); opening the site's page")
	let suffix = LocalizationSupport.currentLanguageCode == "he" ? "_he" : ""
	return URL(string: "https://teacher-in-a-moment.web.app/\(page)\(suffix).html")!
  }
  // MARK: - Signup
  
  func signup() async {
	// A second tap queued before the first got here.
	guard !isLoading else { return }
	// Report every failing rule at once, so the user fixes them in one pass.
	let errors = validationErrors()
	if let first = errors.first {
	  for error in errors {
		AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": error.analyticsReason])
	  }
	  present(errors: errors, first: first)
	  return
	}

	isLoading = true
	defer { isLoading = false }

	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "email", "send_updates": sendUpdates])

	do {
	  let anonymousSession = await authService.currentAnonymousSession()
	  _ = try await authService.createUser(email: emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines),
										   password: password)
	  await authService.finishReplacingAnonymousSession(anonymousSession)
	  if let uid = Auth.auth().currentUser?.uid {
		AnalyticsService.shared.setUser(uid: uid)
	  }
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpSuccess, parameters: ["method": "email"])
	  sendVerificationEmail()
	  // A brand-new account has no profile yet, so it starts at the first
	  // onboarding step for this app's role.
	  destination = UserService.shared.onboardingStart
	} catch {
	  logger.error("[CreateAccount] email sign-up failed: \(String(describing: error))")
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "email", "reason": error.localizedDescription])
	  AnalyticsService.shared.recordError(error, context: "signup")
	  alertMessage = localizedAuthErrorMessage(error)
	  showAlert = true
	}
  }
  
  /// Fired off without waiting: signup is already done, and a failed send can
  /// be retried from the home screen's verify-email banner.
  func sendVerificationEmail() {
	Task { @MainActor in
	  do {
		try await FunctionsService.shared.sendVerificationEmail()
		AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerificationSent, parameters: ["source": "signup"])
	  } catch {
		AnalyticsService.shared.recordError(error, context: "signup_email_verification")
	  }
	}
  }

  // MARK: - Social
  
  func signupWithGoogle() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "google"])
	Task { await signupWithGoogle(replacing: authService.currentAnonymousSession()) }
  }

  private func signupWithGoogle(replacing anonymousSession: AnonymousSession?) {
#if os(iOS)
	iOSGoogleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			await self?.resolveRouteAfterSocialSignIn(method: "google", replacing: anonymousSession)
		  }
		case .failure(let error):
		  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "google", "reason": error.localizedDescription])
		  Task { @MainActor in
			self?.alertMessage = localizedAuthErrorMessage(error)
			self?.showAlert = true
		  }
	  }
	}
#endif
#if os(Android)
	logger.info("Android Google sign-up tapped")
	Task {
	  do {
		let signInResult = try await AndroidGoogleAuth().signIn()
		await resolveRouteAfterSocialSignIn(method: "google", replacing: anonymousSession, uidOverride: AndroidGoogleAuth.uid(from: signInResult))
	  } catch {
		logger.error("[CreateAccountViewModel] \(error.localizedDescription)")
		AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "google", "reason": error.localizedDescription])
		alertMessage = localizedAuthErrorMessage(error)
		showAlert = true
	  }
	}
#endif
  }

  func signupWithApple() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpStart, parameters: ["method": "apple"])
	Task { await signupWithApple(replacing: authService.currentAnonymousSession()) }
  }

  private func signupWithApple(replacing anonymousSession: AnonymousSession?) {
#if os(iOS)
	iOSAppleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			await self?.resolveRouteAfterSocialSignIn(method: "apple", replacing: anonymousSession)
		  }
		case .failure(let error):
		  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": "apple", "reason": error.localizedDescription])
		  Task { @MainActor in
			self?.alertMessage = localizedAuthErrorMessage(error)
			self?.showAlert = true
		  }
	  }
	}
#endif
  }

  private func resolveRouteAfterSocialSignIn(method: String, replacing anonymousSession: AnonymousSession?, uidOverride: String? = nil) async {
	guard let uid = Auth.auth().currentUser?.uid ?? uidOverride else {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.signUpFailure, parameters: ["method": method, "reason": "no_session"])
	  alertMessage = LocalizationSupport.localized("Could not retrieve user session. Please try again.")
	  showAlert = true
	  return
	}
	AnalyticsService.shared.setUser(uid: uid)
	AnalyticsService.shared.logEvent(AnalyticsEvent.signUpSuccess, parameters: ["method": method])
	await authService.finishReplacingAnonymousSession(anonymousSession)
	do {
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  // Signing up with Google or Apple can land on an existing account,
	  // which may be the other app's. It is signed back out, and its route
	  // leads to the welcome screen, which says which app it belongs to.
	  if case .otherApp(let role) = resume {
		UserService.shared.signOutOtherAppAccount(role: role)
	  }
	  destination = resume
	} catch {
	  logger.error("[CreateAccountViewModel] \(error.localizedDescription)")
	  alertMessage = localizedAuthErrorMessage(error)
	  showAlert = true
	}
  }
  
  // MARK: - Helpers
  
  /// Every rule the form currently breaks, in the order the fields appear.
  func validationErrors() -> [SignupValidationError] {
	var errors: [SignupValidationError] = []
	if !isEmailValid { errors.append(.invalidEmail) }
	if !isPasswordValid { errors.append(.passwordTooShort) }
	if !doPasswordsMatch { errors.append(.passwordsDoNotMatch) }
	if !agreedToTerms { errors.append(.termsNotAccepted) }
	return errors
  }

  /// One alert listing every failing rule; focus goes to the first field
  /// that is wrong.
  private func present(errors: [SignupValidationError], first: SignupValidationError) {
	alertMessage = errors.compactMap(\.errorDescription).joined(separator: "\n")
	showAlert    = true
	focusField   = first.focusField
  }
}
