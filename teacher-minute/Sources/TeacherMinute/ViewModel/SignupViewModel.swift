//
//  SignupViewModel.swift
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
final class SignupViewModel {
    var emailOrPhone = ""
    var password = ""
    var isPasswordVisible = false
    var isLoading = false
    let authService = AuthService()
    var canSubmit: Bool {
        !emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isLoading
    }

    func signup() async {
        guard canSubmit else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            if emailOrPhone.isEmail {
              let result = try await authService.createUser(email: emailOrPhone, password: password)
              print("result: \(result)")
              isLoading = false
            }
        } catch {
            print("Login error: \(error)")
            isLoading = false
        }
    }

    func loginWithGoogle() {
        // TODO: Connect Google Sign-In
    }

    func loginWithApple() {
        // TODO: Connect Sign in with Apple
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
