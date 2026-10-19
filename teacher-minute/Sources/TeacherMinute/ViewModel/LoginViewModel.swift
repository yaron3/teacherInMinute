//
//  LoginViewModel.swift
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

@Observable
@MainActor
final class LoginViewModel {
  var emailOrPhone = ""
  var password     = ""
  var isLoading    = false
  
  // Alert
  var alertMessage: String?
  var showAlert    = false
  
  // Navigation — set by login() after resolving onboarding state
  var destination: OnboardingResume?
  
  let authService = AuthService()
  
  var trimmedEmail: String {
	emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Checked here rather than left to Firebase, so a malformed address such
  /// as `name@example..com` is pointed out under the field as it is typed,
  /// with no sign-in attempt.
  var isEmailValid: Bool {
	trimmedEmail.isEmail
  }

  var showsEmailError: Bool {
	!trimmedEmail.isEmpty && !isEmailValid
  }

  var canSubmit: Bool {
	isEmailValid &&
	!password.isEmpty &&
	!isLoading
  }
  
  // MARK: - Login + route resolution
  
  func login() async {
	guard canSubmit else { return }

	isLoading = true
	defer { isLoading = false }

	AnalyticsService.shared.logEvent(AnalyticsEvent.loginStart, parameters: ["method": "email"])

	do {
	  // 1. Authenticate. An anonymous session it replaces is deleted once
	  //    this succeeds.
	  let anonymousSession = await authService.currentAnonymousSession()
	  _ = try await authService.signIn(
		email: emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines),
		password: password
	  )

	  // 2. Get the Firebase UID
	  guard let uid = Auth.auth().currentUser?.uid else {
		present(message: LocalizationSupport.localized("Could not retrieve user session. Please try again."))
		AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "email", "reason": "no_session"])
		return
	  }
	  AnalyticsService.shared.setUser(uid: uid)
	  AnalyticsService.shared.logEvent(AnalyticsEvent.loginSuccess, parameters: ["method": "email"])
	  await authService.finishReplacingAnonymousSession(anonymousSession)

	  // 3. Resolve where in onboarding this user should go
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  proceed(to: resume)

	} catch {
	  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "email", "reason": error.localizedDescription])
	  AnalyticsService.shared.recordError(error, context: "login")
	  present(message: localizedAuthErrorMessage(error))
	}
  }
  
  // MARK: - Social
  
  func loginWithGoogle() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.loginStart, parameters: ["method": "google"])
	Task { await loginWithGoogle(replacing: authService.currentAnonymousSession()) }
  }

  /// A Google account with no account of ours yet is linked to the anonymous
  /// session, as on sign-up; one that has an account replaces it.
  private func loginWithGoogle(replacing anonymousSession: AnonymousSession?) {
#if os(iOS)
	iOSGoogleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			guard let uid = Auth.auth().currentUser?.uid else {
			  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "google", "reason": "no_session"])
			  self?.present(message: LocalizationSupport.localized("Could not retrieve user session. Please try again."))
			  return
			}
			AnalyticsService.shared.setUser(uid: uid)
			AnalyticsService.shared.logEvent(AnalyticsEvent.loginSuccess, parameters: ["method": "google"])
			await self?.authService.finishReplacingAnonymousSession(anonymousSession)
			do {
			  let resume = try await UserService.shared.resumeRoute(uid: uid)
			  self?.proceed(to: resume)
			} catch {
			  logger.error("[LoginViewModel] \(error.localizedDescription)")
			  self?.present(message: localizedAuthErrorMessage(error))
			}
		  }
		case .failure(let error):
		  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "google", "reason": error.localizedDescription])
		  Task { @MainActor in self?.present(message: localizedAuthErrorMessage(error)) }
	  }
	}
#endif
#if os(Android)
	logger.info("Android Google login tapped")
	Task {
	  do {
		let signInResult = try await AndroidGoogleAuth().signIn()
		guard let uid = Auth.auth().currentUser?.uid ?? AndroidGoogleAuth.uid(from: signInResult) else {
		  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "google", "reason": "no_session"])
		  present(message: LocalizationSupport.localized("Could not retrieve user session. Please try again."))
		  return
		}
		AnalyticsService.shared.setUser(uid: uid)
		AnalyticsService.shared.logEvent(AnalyticsEvent.loginSuccess, parameters: ["method": "google"])
		await authService.finishReplacingAnonymousSession(anonymousSession)
		let resume = try await UserService.shared.resumeRoute(uid: uid)
		proceed(to: resume)
	  } catch {
		logger.error("[LoginViewModel] \(error.localizedDescription)")
		AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "google", "reason": error.localizedDescription])
		present(message: localizedAuthErrorMessage(error))
	  }
	}
#endif
  }

  func loginWithApple() {
	AnalyticsService.shared.logEvent(AnalyticsEvent.loginStart, parameters: ["method": "apple"])
	Task { await loginWithApple(replacing: authService.currentAnonymousSession()) }
  }

  private func loginWithApple(replacing anonymousSession: AnonymousSession?) {
#if os(iOS)
	iOSAppleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			guard let uid = Auth.auth().currentUser?.uid else {
			  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "apple", "reason": "no_session"])
			  self?.present(message: LocalizationSupport.localized("Could not retrieve user session. Please try again."))
			  return
			}
			AnalyticsService.shared.setUser(uid: uid)
			AnalyticsService.shared.logEvent(AnalyticsEvent.loginSuccess, parameters: ["method": "apple"])
			await self?.authService.finishReplacingAnonymousSession(anonymousSession)
			do {
			  let resume = try await UserService.shared.resumeRoute(uid: uid)
			  self?.proceed(to: resume)
			} catch {
			  logger.error("[LoginViewModel] \(error.localizedDescription)")
			  self?.present(message: localizedAuthErrorMessage(error))
			}
		  }
		case .failure(let error):
		  AnalyticsService.shared.logEvent(AnalyticsEvent.loginFailure, parameters: ["method": "apple", "reason": error.localizedDescription])
		  Task { @MainActor in self?.present(message: localizedAuthErrorMessage(error)) }
	  }
	}
#endif
  }

  func forgotPassword() {
    let email = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !email.isEmpty else {
      present(message: LocalizationSupport.localized("Enter your email address first."))
      return
    }

    Task {
      do {
        try await authService.sendPasswordReset(email: email)
        AnalyticsService.shared.logEvent(AnalyticsEvent.passwordResetSent, parameters: ["method": "email"])
        present(message: LocalizationSupport.localized("Password reset email sent."))
      } catch {
        AnalyticsService.shared.recordError(error, context: "forgotPassword")
        present(message: localizedAuthErrorMessage(error))
      }
    }
  }
  func back()            { /* TODO */ }
  
  // MARK: - Helpers

  /// Sends a signed-in user on to wherever their onboarding stands. An account
  /// of the other app's role is signed straight back out first; its route
  /// leads to the welcome screen, which says which app it belongs to.
  private func proceed(to resume: OnboardingResume) {
	if case .otherApp(let role) = resume {
	  UserService.shared.signOutOtherAppAccount(role: role)
	}
	destination = resume
  }

  private func present(message: String) {
	alertMessage = message
	showAlert    = true
  }
}
