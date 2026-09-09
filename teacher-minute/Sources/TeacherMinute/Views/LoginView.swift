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
	  theme.screenBackground
		.ignoresSafeArea()
	  
	  ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
//		Text(LocalizationSupport.localized("Welcome Back"))
//		  .font(.system(size: 32, weight: .bold))
//		  .foregroundStyle(theme.primaryText)
//		  .padding(.top, 28)
		
		Text(LocalizationSupport.localized("Log in to Teacher in a Minute to continue your journey."))
		  .font(.system(size: 16, weight: .regular))
		  .foregroundStyle(theme.secondaryText)
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
		theme.screenBackground.opacity(0.85).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(theme.primaryText)
		  Text(LocalizationSupport.localized("Signing in…"))
			.font(.system(size: 15, weight: .medium))
			.foregroundStyle(theme.primaryText)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	// Push the resolved destination when login completes
	.navigationTitle(LocalizationSupport.localized("Welcome Back"))
	.onChange(of: viewModel.destination) { _, resume in
	  logger.info("[Login] destination changed resume=\(String(describing: resume))")
	  guard let resume else { return }
	  router.resume(resume)
	  viewModel.destination = nil
	}
	.appDialog(
	  LocalizationSupport.localized("Sign In Error"),
	  isPresented: $viewModel.showAlert,
	  message: viewModel.alertMessage ?? LocalizationSupport.localized("An unexpected error occurred."),
	  actions: [AppDialogAction(LocalizationSupport.localized("OK"))]
	)
  }
  

  
  // MARK: - Form card (unchanged structure, UIKit types removed for Skip compat)
  
  var formCard: some View {
	VStack(alignment: .leading, spacing: 22) {
	  // Email field
	  VStack(alignment: .leading, spacing: 9) {
		Text(LocalizationSupport.localized("Email"))
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(theme.primaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(
			systemName: "envelope",
			size: 15,
			color: theme.secondaryText
		  )
		  
		  TextField(LocalizationSupport.localized("Enter your email"), text: $viewModel.emailOrPhone)
			.font(.system(size: 16))
			.foregroundStyle(theme.primaryText)
			.keyboardType(.emailAddress)
			.textInputAutocapitalization(.never)
			.autocorrectionDisabled()
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
			.accessibilityIdentifier("email_input")
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(theme.fieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
			.stroke(theme.controlBorder, lineWidth: 1)
		}
	  }
	  
	  // Password field
	  VStack(alignment: .leading, spacing: 9) {
		Text(LocalizationSupport.localized("Password"))
		  .font(.system(size: 14, weight: .semibold))
		  .foregroundStyle(theme.primaryText)
		
		HStack(spacing: 13) {
		  PlatformIcon(
			systemName: "lock.fill",
			size: 15,
			color: theme.secondaryText
		  )
		  
		  Group {
			if viewModel.isPasswordVisible {
			  TextField(LocalizationSupport.localized("Enter your password"), text: $viewModel.password)
			} else {
			  SecureField(LocalizationSupport.localized("Enter your password"), text: $viewModel.password)
				.accessibilityIdentifier("password_input")
			}
		  }
		  .font(.system(size: 16))
		  .foregroundStyle(theme.primaryText)
		  .textInputAutocapitalization(.never)
		  .autocorrectionDisabled()
		  
		  Button {
			viewModel.isPasswordVisible.toggle()
		  } label: {
			PlatformIcon(systemName: viewModel.isPasswordVisible ? "eye" : "eye.slash")
			  .font(.system(size: 17))
			  .foregroundStyle(theme.secondaryText)
		  }
		  .buttonStyle(.plain)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(theme.fieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
			.stroke(theme.controlBorder, lineWidth: 1)
		}
	  }
	  
	  Button {
		viewModel.forgotPassword()
	  } label: {
		Text(LocalizationSupport.localized("Forgot Password?"))
		  .font(.system(size: 14, weight: .medium))
		  .foregroundStyle(theme.accent)
		  .frame(maxWidth: .infinity, alignment: .trailing)
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 2)
	}
	.padding(.horizontal, 24)
	.padding(.top, 26)
	.padding(.bottom, 24)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }
  
  var loginButton: some View {
	Button {
	  Task { await viewModel.login() }
	} label: {
	  HStack(spacing: 8) {
		if viewModel.isLoading {
		  ProgressView().tint(theme.onAccentText)
		}

		Text(viewModel.isLoading ? LocalizationSupport.localized("Signing In…") : LocalizationSupport.localized("Log In"))
		  .font(.system(size: 17, weight: .bold))
	  }
	  // Disabled state swaps to the raised gray rather than fading ink into the
	  // background, which left the label unreadable.
	  .foregroundStyle(viewModel.canSubmit ? theme.onAccentText : theme.secondaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 54)
	  .background(viewModel.canSubmit ? theme.accent : theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
	}
	.buttonStyle(.plain)
	.disabled(!viewModel.canSubmit)
  }
  
  var dividerTitle: some View {
	HStack(spacing: 17) {
	  Rectangle()
		.fill(theme.separator)
		.frame(height: 1)
	  
	  Text(LocalizationSupport.localized("Or continue with"))
		.font(.system(size: 14, weight: .regular))
		.foregroundStyle(theme.secondaryText)
		.lineLimit(1)
	  
	  Rectangle()
		.fill(theme.separator)
		.frame(height: 1)
	}
	.padding(.horizontal, 16)
  }
  
  var socialButtons: some View {
	HStack(spacing: 16) {
	  socialButton(title: LocalizationSupport.localized("Google"), systemImage: "google-logo") { viewModel.loginWithGoogle() }
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
	  .foregroundStyle(theme.primaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 56)
	  .background(theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
	  .overlay { RoundedRectangle(cornerRadius: flatRadius, style: .continuous).stroke(theme.controlBorder, lineWidth: 1) }
	}
	.buttonStyle(.plain)
  }
  
  var bottomSignUp: some View {
	HStack(spacing: 4) {
	  Text(LocalizationSupport.localized("Don't have an account?"))
		.foregroundStyle(theme.secondaryText)
	  
	  Button {
		router.push(.createAccount)
	  } label: {
		Text(LocalizationSupport.localized("Sign Up"))
		  .fontWeight(.semibold)
		  .foregroundStyle(theme.accent)
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
