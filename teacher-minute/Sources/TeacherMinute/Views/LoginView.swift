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
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  Color(.systemBackground)
		.ignoresSafeArea()
	  
	  ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
//		Text(LocalizationSupport.localized("Welcome Back"))
//		  .font(.system(size: 32, weight: .bold))
//		  .foregroundStyle(theme.authPrimaryText)
//		  .padding(.top, 28)
		
		Text(LocalizationSupport.localized("Log in to Math Connect to continue your\njourney."))
		  .font(.system(size: 16, weight: .regular))
		  .foregroundStyle(theme.authSecondaryText)
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
		  }
	  
	  // Full-screen loading overlay while checking Firestore
	  if viewModel.isLoading {
		theme.appPrimaryText.opacity(0.25).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(theme.appPrimaryText)
		  Text(LocalizationSupport.localized("Signing in…"))
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(theme.appPrimaryText)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	// Push the resolved destination when login completes
	.navigationTitle(LocalizationSupport.localized("Welcome Back"))
	.onChange(of: viewModel.destination) { _, resume in
	  guard let resume else { return }
	  router.resume(resume)
	  viewModel.destination = nil
	}
	.alert(LocalizationSupport.localized("Sign In Error"), isPresented: $viewModel.showAlert) {
	  Button(LocalizationSupport.localized("OK"), role: .cancel) { viewModel.showAlert = false }
	} message: {
	  Text(viewModel.alertMessage ?? LocalizationSupport.localized("An unexpected error occurred."))
	}
  }
  

  
  // MARK: - Form card (unchanged structure, UIKit types removed for Skip compat)
  
  var formCard: some View {
	VStack(alignment: .leading, spacing: 22) {
	  // Email field
	  VStack(alignment: .leading, spacing: 9) {
		Text(LocalizationSupport.localized("Email"))
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(theme.authPrimaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(
			systemName: "envelope",
			size: 15,
			color: theme.authIcon
		  )
		  
		  TextField(LocalizationSupport.localized("Enter your email"), text: $viewModel.emailOrPhone)
			.font(.system(size: 16))
			.foregroundStyle(theme.authPrimaryText)
			.keyboardType(.emailAddress)
			.textInputAutocapitalization(.never)
			.autocorrectionDisabled()
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(theme.authFieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(theme.authFieldBorder, lineWidth: 1)
		}
	  }
	  
	  // Password field
	  VStack(alignment: .leading, spacing: 9) {
		Text(LocalizationSupport.localized("Password"))
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(theme.authPrimaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(
			systemName: "lock.fill",
			size: 15,
			color: theme.authIcon
		  )
		  
		  Group {
			if viewModel.isPasswordVisible {
			  TextField(LocalizationSupport.localized("Enter your password"), text: $viewModel.password)
			} else {
			  SecureField(LocalizationSupport.localized("Enter your password"), text: $viewModel.password)
			}
		  }
		  .font(.system(size: 16))
		  .foregroundStyle(theme.authPrimaryText)
		  .textInputAutocapitalization(.never)
		  .autocorrectionDisabled()
		  
		  Button {
			viewModel.isPasswordVisible.toggle()
		  } label: {
			PlatformIcon(systemName: viewModel.isPasswordVisible ? "eye" : "eye.slash")
			  .font(.system(size: 17))
			  .foregroundStyle(theme.authIcon)
		  }
		  .buttonStyle(.plain)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(theme.authFieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(theme.authFieldBorder, lineWidth: 1)
		}
	  }
	  
	  Button {
		viewModel.forgotPassword()
	  } label: {
		Text(LocalizationSupport.localized("Forgot Password?"))
		  .font(.system(size: 14, weight: .medium))
		  .foregroundStyle(theme.authPink)
		  .frame(maxWidth: .infinity, alignment: .trailing)
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 2)
	}
	.padding(.horizontal, 24)
	.padding(.top, 26)
	.padding(.bottom, 24)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
	.shadow(color: theme.appPrimaryText.opacity(0.035), radius: 24, x: 0, y: 14)
  }
  
  var loginButton: some View {
	Button {
	  Task { await viewModel.login() }
	} label: {
	  HStack(spacing: 8) {
		if viewModel.isLoading {
		  ProgressView().tint(theme.appPrimaryText)
		}
		
		Text(viewModel.isLoading ? LocalizationSupport.localized("Signing In…") : LocalizationSupport.localized("Log In"))
		  .font(.system(size: 16, weight: .semibold))
	  }
	  .foregroundStyle(theme.appPrimaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 57)
	  .background(theme.authPink.opacity(viewModel.canSubmit ? 1 : 0.55))
	  .clipShape(Capsule())
	  .shadow(color: theme.authPink.opacity(viewModel.canSubmit ? 0.25 : 0), radius: 18, x: 0, y: 10)
	}
	.buttonStyle(.plain)
	.disabled(!viewModel.canSubmit)
  }
  
  var dividerTitle: some View {
	HStack(spacing: 17) {
	  Rectangle()
		.fill(theme.authDivider)
		.frame(height: 1)
	  
	  Text(LocalizationSupport.localized("Or continue with"))
		.font(.system(size: 14, weight: .regular))
		.foregroundStyle(theme.authSecondaryText)
		.lineLimit(1)
	  
	  Rectangle()
		.fill(theme.authDivider)
		.frame(height: 1)
	}
	.padding(.horizontal, 16)
  }
  
  var socialButtons: some View {
	HStack(spacing: 16) {
	  socialButton(title: LocalizationSupport.localized("Google"), systemImage: "g.circle.fill") { viewModel.loginWithGoogle() }
	  #if !os(Android)
		  socialButton(title: LocalizationSupport.localized("Apple"),  systemImage: "apple.logo")    { viewModel.loginWithApple() }
#endif
	}
  }
  
  func socialButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
	Button(action: action) {
	  HStack(spacing: 9) {
		PlatformIcon(systemName: systemImage).font(.system(size: 20, weight: .semibold))
		Text(title).font(.system(size: 15, weight: .semibold))
	  }
	  .foregroundStyle(theme.authPrimaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 56)
	  .background(theme.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	  .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.authSocialBorder, lineWidth: 1) }
	  .shadow(color: theme.appPrimaryText.opacity(0.04), radius: 10, x: 0, y: 5)
	}
	.buttonStyle(.plain)
  }
  
  var bottomSignUp: some View {
	HStack(spacing: 4) {
	  Text(LocalizationSupport.localized("Don't have an account?"))
		.foregroundStyle(theme.authSecondaryText)
	  
	  Button {
		router.push(.createAccount)
	  } label: {
		Text(LocalizationSupport.localized("Sign Up"))
		  .fontWeight(.semibold)
		  .foregroundStyle(theme.authPink)
	  }
	  .buttonStyle(.plain)
	}
	.font(.system(size: 14))
  }
}
#if os(iOS)
struct LoginView_Previews: PreviewProvider {
  
  static var previews: some View {
	
	LoginView()
	
  }
  
}
#endif
