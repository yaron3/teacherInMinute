//
//  CreateAccountViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


//
//  LoginViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation

@Observable
@MainActor
final class CreateAccountViewModel {
  var emailOrPhone = ""
  var password = ""
  var isPasswordVisible = false
  var isLoading = false
  var navigateToChooseRole = false
  let authService = AuthService()
  var canSubmit: Bool {
	!emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
	!password.isEmpty &&
	!isLoading
  }
  
  var isValid: Bool { canSubmit }
  
  func signup() async {
	guard canSubmit else { return }
	
	isLoading = true
	defer { isLoading = false }
	do {
	  if emailOrPhone.isEmail {
		let result = try await authService.createUser(email: emailOrPhone, password: password)
		print("result: \(result)")
		isLoading = false
		navigateToChooseRole = true
	  }
	} catch {
	  print("Login error: \(error)")
	  isLoading = false
	}
  }
  
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
#if skip
	AndroidGoogleAuth().signIn()
#endif
	
  }
  
  func signupWithApple() {
	print("not implemented yet")
  }
  
  func forgotPassword() {
	// TODO: Navigate to forgot-password flow
  }
  
  func signUp() {
	// TODO: Navigate to sign-up flow
  }
  
  func back() {
	// TODO: Dismiss / navigate back
  }
}
