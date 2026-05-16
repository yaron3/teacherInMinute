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
		case .success:
		  Task { @MainActor in
			guard let uid = Auth.auth().currentUser?.uid else {
			  self?.present(message: "Could not retrieve user session. Please try again.")
			  return
			}
			do {
			  let resume = try await UserService.shared.resumeRoute(uid: uid)
			  self?.destination = AppRoute.resumeDestination(for: resume)
			} catch {
			  self?.present(message: error.localizedDescription)
			}
		  }
		case .failure(let error):
		  Task { @MainActor in self?.present(message: error.localizedDescription) }
	  }
	}
#endif
#if os(Android)
		print("Android Google login tapped")
		Task {
		  do {
			_ = try await AndroidGoogleAuth().signIn()
			guard let uid = Auth.auth().currentUser?.uid else {
			  present(message: "Could not retrieve user session. Please try again.")
			  return
			}
			let resume = try await UserService.shared.resumeRoute(uid: uid)
			destination = AppRoute.resumeDestination(for: resume)
		  } catch {
			present(message: error.localizedDescription)
		  }
		}
#endif
  }
  
  func loginWithApple() {
#if canImport(UIKit)
	iOSAppleSignInProvider().signIn { [weak self] result in
	  switch result {
		case .success:
		  Task { @MainActor in
			guard let uid = Auth.auth().currentUser?.uid else {
			  self?.present(message: "Could not retrieve user session. Please try again.")
			  return
			}
			do {
			  let resume = try await UserService.shared.resumeRoute(uid: uid)
			  self?.destination = AppRoute.resumeDestination(for: resume)
			} catch {
			  self?.present(message: error.localizedDescription)
			}
		  }
		case .failure(let error):
		  Task { @MainActor in self?.present(message: error.localizedDescription) }
	  }
	}
#elseif os(Android)
	print("Android Apple login tapped")
	Task {
	  do {
		_ = try await AndroidAppleAuth().signIn()
		guard let uid = Auth.auth().currentUser?.uid else {
		  present(message: "Could not retrieve user session. Please try again.")
		  return
		}
		let resume = try await UserService.shared.resumeRoute(uid: uid)
		destination = AppRoute.resumeDestination(for: resume)
	  } catch {
		present(message: error.localizedDescription)
	  }
	}
#endif
  }
  func forgotPassword()  { /* TODO */ }
  func back()            { /* TODO */ }
  
  // MARK: - Helpers
  
  private func present(message: String) {
	alertMessage = message
	showAlert    = true
  }
}
