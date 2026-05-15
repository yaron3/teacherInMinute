//
//  LoginView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct LoginView: View {
  @State var viewModel = LoginViewModel()
  @Environment(\.appRouter) var router
  
  var body: some View {
	ZStack {
	  Color(.systemBackground)
		.ignoresSafeArea()
	  
	  VStack(alignment: .leading, spacing: 0) {
		backButton
		
		Text("Welcome Back")
		  .font(.system(size: 32, weight: .bold))
		  .foregroundStyle(Color.authPrimaryText)
		  .padding(.top, 28)
		
		Text("Log in to Math Connect to continue your\njourney.")
		  .font(.system(size: 16, weight: .regular))
		  .foregroundStyle(Color.authSecondaryText)
		  .lineSpacing(6)
		  .padding(.top, 10)
		
		formCard
		  .padding(.top, 38)
		
		loginButton
		  .padding(.top, 25)
		
		dividerTitle
		  .padding(.top, 28)
		
		socialButtons
		  .padding(.top, 25)
		
		Spacer()
		
		bottomSignUp
		  .frame(maxWidth: .infinity)
		  .padding(.bottom, 34)
	  }
	  .padding(.horizontal, 27)
	  .padding(.top, 8)
	  
	  // Full-screen loading overlay while checking Firestore
	  if viewModel.isLoading {
		Color.black.opacity(0.25).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(.white)
		  Text("Signing in…")
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(.white)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	// Push the resolved destination when login completes
	.onChange(of: viewModel.destination) { _, route in
	  guard let route else { return }
	  router.push(route)
	  viewModel.destination = nil
	}
	.alert("Sign In Error", isPresented: $viewModel.showAlert) {
	  Button("OK", role: .cancel) { viewModel.showAlert = false }
	} message: {
	  Text(viewModel.alertMessage ?? "An unexpected error occurred.")
	}
  }
  
  var backButton: some View {
	Button {
	  viewModel.back()
	} label: {
	  PlatformIcon(systemName: "arrow.left")
		.font(.system(size: 18, weight: .semibold))
		.foregroundStyle(Color.authPrimaryText)
		.frame(width: 42, height: 42)
		.background(Color.appCardBackground)
		.clipShape(Circle())
		.shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
	}
	.buttonStyle(.plain)
  }
  
  // MARK: - Form card (unchanged structure, UIKit types removed for Skip compat)
  
  var formCard: some View {
	VStack(alignment: .leading, spacing: 22) {
	  // Email field
	  VStack(alignment: .leading, spacing: 9) {
		Text("Email")
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(Color.authPrimaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(systemName: "envelope")
			.font(.system(size: 15))
			.foregroundStyle(Color.authIcon)
		  
		  TextField("Enter your email", text: $viewModel.emailOrPhone)
			.font(.system(size: 16))
			.foregroundStyle(Color.authPrimaryText)
			.keyboardType(.emailAddress)
			.textInputAutocapitalization(.never)
			.autocorrectionDisabled()
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(Color.authFieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(Color.authFieldBorder, lineWidth: 1)
		}
	  }
	  
	  // Password field
	  VStack(alignment: .leading, spacing: 9) {
		Text("Password")
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(Color.authPrimaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(systemName: "lock.fill")
			.font(.system(size: 15))
			.foregroundStyle(Color.authIcon)
		  
		  Group {
			if viewModel.isPasswordVisible {
			  TextField("Enter your password", text: $viewModel.password)
			} else {
			  SecureField("Enter your password", text: $viewModel.password)
			}
		  }
		  .font(.system(size: 16))
		  .foregroundStyle(Color.authPrimaryText)
		  .textInputAutocapitalization(.never)
		  .autocorrectionDisabled()
		  
		  Button {
			viewModel.isPasswordVisible.toggle()
		  } label: {
			PlatformIcon(systemName: viewModel.isPasswordVisible ? "eye" : "eye.slash")
			  .font(.system(size: 17))
			  .foregroundStyle(Color.authIcon)
		  }
		  .buttonStyle(.plain)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(Color.authFieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(Color.authFieldBorder, lineWidth: 1)
		}
	  }
	  
	  Button {
		viewModel.forgotPassword()
	  } label: {
		Text("Forgot Password?")
		  .font(.system(size: 14, weight: .medium))
		  .foregroundStyle(Color.authPink)
		  .frame(maxWidth: .infinity, alignment: .trailing)
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 2)
	}
	.padding(.horizontal, 24)
	.padding(.top, 26)
	.padding(.bottom, 24)
	.background(Color.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
	.shadow(color: .black.opacity(0.035), radius: 24, x: 0, y: 14)
  }
  
  var loginButton: some View {
	Button {
	  Task { await viewModel.login() }
	} label: {
	  HStack(spacing: 8) {
		if viewModel.isLoading {
		  ProgressView().tint(.white)
		}
		
		Text(viewModel.isLoading ? "Signing In…" : "Log In")
		  .font(.system(size: 16, weight: .semibold))
	  }
	  .foregroundStyle(.white)
	  .frame(maxWidth: .infinity)
	  .frame(height: 57)
	  .background(Color.authPink.opacity(viewModel.canSubmit ? 1 : 0.55))
	  .clipShape(Capsule())
	  .shadow(color: Color.authPink.opacity(viewModel.canSubmit ? 0.25 : 0), radius: 18, x: 0, y: 10)
	}
	.buttonStyle(.plain)
	.disabled(!viewModel.canSubmit)
  }
  
  var dividerTitle: some View {
	HStack(spacing: 17) {
	  Rectangle()
		.fill(Color.authDivider)
		.frame(height: 1)
	  
	  Text("Or continue with")
		.font(.system(size: 14, weight: .regular))
		.foregroundStyle(Color.authSecondaryText)
		.lineLimit(1)
	  
	  Rectangle()
		.fill(Color.authDivider)
		.frame(height: 1)
	}
	.padding(.horizontal, 16)
  }
  
  var socialButtons: some View {
	HStack(spacing: 16) {
	  socialButton(title: "Google", systemImage: "g.circle.fill") { viewModel.loginWithGoogle() }
	  socialButton(title: "Apple",  systemImage: "apple.logo")    { viewModel.loginWithApple() }
	}
  }
  
  func socialButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
	Button(action: action) {
	  HStack(spacing: 9) {
		PlatformIcon(systemName: systemImage).font(.system(size: 20, weight: .semibold))
		Text(title).font(.system(size: 15, weight: .semibold))
	  }
	  .foregroundStyle(Color.authPrimaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 56)
	  .background(Color.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	  .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.authSocialBorder, lineWidth: 1) }
	  .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
	}
	.buttonStyle(.plain)
  }
  
  var bottomSignUp: some View {
	HStack(spacing: 4) {
	  Text("Don't have an account?")
		.foregroundStyle(Color.authSecondaryText)
	  
	  Button {
		router.push(.createAccount)
	  } label: {
		Text("Sign Up")
		  .fontWeight(.semibold)
		  .foregroundStyle(Color.authPink)
	  }
	  .buttonStyle(.plain)
	}
	.font(.system(size: 14))
  }
}
