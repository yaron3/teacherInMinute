//
//  LoginViewModel.swift
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

@Observable
@MainActor
final class LoginViewModel {
  var emailOrPhone = ""
  var password     = ""
  var isPasswordVisible = false
  var isLoading    = false
  
  // Alert
  var alertMessage: String?
  var showAlert    = false
  
  // Navigation — set by login() after resolving onboarding state
  var destination: AppRoute?
  
  let authService = AuthService()
  
  var canSubmit: Bool {
	!emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
	!password.isEmpty &&
	!isLoading
  }
  
  // MARK: - Login + route resolution
  
  func login() async {
	guard canSubmit else { return }
	
	isLoading = true
	defer { isLoading = false }
	
	do {
	  // 1. Authenticate
	  _ = try await authService.signIn(
		email: emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines),
		password: password
	  )
	  
	  // 2. Get the Firebase UID
	  guard let uid = Auth.auth().currentUser?.uid else {
		present(message: "Could not retrieve user session. Please try again.")
		return
	  }
	  
	  // 3. Resolve where in onboarding this user should go
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  destination = AppRoute.resumeDestination(for: resume)
	  
	} catch {
	  present(message: error.localizedDescription)
	}
  }
  
  // MARK: - Social
  
  func loginWithGoogle() {
#if canImport(UIKit)
	iOSGoogleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success: break   // TODO: resolve route the same way
		case .failure(let error):
		  Task { @MainActor in self?.present(message: error.localizedDescription) }
	  }
	}
#endif
#if skip
	AndroidGoogleAuth().signIn()
#endif
  }
  
  func loginWithApple() { /* TODO */ }
  func forgotPassword()  { /* TODO */ }
  func back()            { /* TODO */ }
  
  // MARK: - Helpers
  
  private func present(message: String) {
	alertMessage = message
	showAlert    = true
  }
}
