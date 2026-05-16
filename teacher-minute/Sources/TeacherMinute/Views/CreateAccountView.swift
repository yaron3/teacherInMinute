//
//  CreateAccountView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//


import SwiftUI

struct CreateAccountView: View {
  
  enum SOCIAL_TYPE: String, CaseIterable {
	case apple = "apple"
	case google = "google"
  }
  
  @State var viewModel = CreateAccountViewModel()
  @Environment(\.appRouter) var router
  @State var isPasswordVisible = false
  @FocusState var focusedField: SignupField?
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  theme.appCardBackground.ignoresSafeArea()
	  VStack(spacing: 0) {
		ScrollView(showsIndicators: false) {
		  VStack(alignment: .leading, spacing: 24) {
			inputCard
			checkboxSection
			continueButton
			dividerSection
			socialButtons
		  }
		  .padding(.horizontal, 26)
		  .padding(.top, 18)
		}
		bottomLoginSection
	  }
	  
	  // Loading overlay
	  if viewModel.isLoading {
		theme.appPrimaryText.opacity(0.18).ignoresSafeArea()
		ProgressView()
		  .progressViewStyle(.circular)
		  .scaleEffect(1.6)
		  .tint(theme.appPrimaryText)
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	.navigationTitle("Create Account")
	.onChange(of: viewModel.navigateToChooseRole) { _, newValue in
	  if newValue { router.push(.chooseRole) }
	}
	.onChange(of: viewModel.focusField) { _, field in
	  focusedField = field
	}
	.alert("Sign Up", isPresented: $viewModel.showAlert) {
	  Button("OK", role: .cancel) { viewModel.showAlert = false }
	} message: {
	  Text(viewModel.alertMessage ?? "")
	}
  }
  
  // MARK: - Sections
  
  
  var inputCard: some View {
	VStack(alignment: .leading, spacing: 22) {
	  fieldSection(
		title: "Email",
		icon: "envelope",
		placeholder: "Enter your email",
		text: $viewModel.emailOrPhone,
		isSecure: false,
		field: .email,
		isValid: viewModel.emailOrPhone.isEmpty || viewModel.isEmailValid
	  )
	  fieldSection(
		title: "Password",
		icon: "lock.fill",
		placeholder: "Min. 6 characters",
		text: $viewModel.password,
		isSecure: !isPasswordVisible,
		field: .password,
		isValid: viewModel.password.isEmpty || viewModel.isPasswordValid,
		trailingIcon: isPasswordVisible ? "eye" : "eye.slash",
		trailingAction: { isPasswordVisible.toggle() }
	  )
	}
	.padding(24)
	.background(
	  RoundedRectangle(cornerRadius: 22)
		.fill(theme.appCardBackground)
		.shadow(color: theme.appCardBackgroundShadow.opacity(0.045), radius: 18, x: 0, y: 10)
	)
  }
  
  func fieldSection(
	title: String,
	icon: String,
	placeholder: String,
	text: Binding<String>,
	isSecure: Bool,
	field: SignupField,
	isValid: Bool,
	trailingIcon: String? = nil,
	trailingAction: (() -> Void)? = nil
  ) -> some View {
	VStack(alignment: .leading, spacing: 9) {
	  Text(title)
		.font(.system(size: 14, weight: .semibold))
		.foregroundStyle(theme.authPrimaryText)
	  
	  HStack(spacing: 12) {
		PlatformIcon(systemName: icon)
		  .font(.system(size: 15, weight: .medium))
		  .foregroundStyle(isValid ? theme.authIcon : theme.red.opacity(0.8))
		  .frame(width: 20)
		
		Group {
		  if isSecure {
			SecureField(placeholder, text: text)
		  } else {
			TextField(placeholder, text: text)
			  .keyboardType(.emailAddress)
			  .textInputAutocapitalization(.never)
		  }
		}
		.font(.system(size: 16))
		.foregroundStyle(theme.authPrimaryText)
		.focused($focusedField, equals: field)
		
		if let trailingIcon {
		  Button { trailingAction?() } label: {
			PlatformIcon(systemName: trailingIcon)
			  .font(.system(size: 16, weight: .medium))
			  .foregroundStyle(theme.authIcon)
		  }
		}
	  }
	  .padding(.horizontal, 16)
	  .frame(height: 56)
		.background(
		  RoundedRectangle(cornerRadius: 16)
			.fill(theme.authFieldBackground)
			.overlay(
			  RoundedRectangle(cornerRadius: 16)
				.stroke(isValid ? theme.authFieldBorder : theme.red.opacity(0.5), lineWidth: 1.5)
			)
		)
	  
	  if !isValid {
			Text(field == .email ? "Enter a valid email address." : "Must be at least 6 characters.")
			  .font(.system(size: 11))
			  .foregroundStyle(theme.red)
			  .padding(.leading, 4)
	  }
	}
  }
  
  var checkboxSection: some View {
	VStack(alignment: .leading, spacing: 18) {
	  checkboxRow(isOn: $viewModel.agreedToTerms, isTermsRow: true)
	  checkboxRow(isOn: $viewModel.sendUpdates,
				  text: "Send me occasional updates and tips about\nMath Connect.",
				  isTermsRow: false)
	}
	.padding(.horizontal, 8)
  }
  
  func checkboxRow(isOn: Binding<Bool>, text: String = "", isTermsRow: Bool = false) -> some View {
	HStack(alignment: .top, spacing: 12) {
		  Button { isOn.wrappedValue.toggle() } label: {
			ZStack {
			  RoundedRectangle(cornerRadius: 4)
				.fill(isOn.wrappedValue ? theme.authPink : theme.appCardBackground)
				.frame(width: 18, height: 18)
				.overlay(
				  RoundedRectangle(cornerRadius: 4)
					.stroke(isOn.wrappedValue ? theme.authPink : theme.appBorder, lineWidth: 1)
				)
		  if isOn.wrappedValue {
			PlatformIcon(systemName: "checkmark")
			  .font(.system(size: 11, weight: .bold))
			  .foregroundStyle(theme.appPrimaryText)
		  }
		}
	  }
	  .buttonStyle(.plain)
	  
	  if isTermsRow { termsTextView() }
	  else {
			Text(text)
			  .font(.system(size: 14))
			  .lineSpacing(4)
			  .foregroundStyle(theme.authSecondaryText)
		  }
	}
  }
  
	func termsTextView() -> some View {
	  VStack(alignment: .leading, spacing: 2) {
		HStack(spacing: 0) {
			Text("I agree to the ").foregroundStyle(theme.authSecondaryText)
			Text("Terms of Service").foregroundStyle(theme.authPink)
			Text(" and").foregroundStyle(theme.authSecondaryText)
		}
		Text("Privacy Policy.").foregroundStyle(theme.authPink)
	  }
	.font(.system(size: 14))
	.lineSpacing(4)
  }
  
  var continueButton: some View {
	Button {
	  Task { await viewModel.signup() }
	} label: {
	  ZStack {
		Text("Continue to Role Selection")
		  .font(.system(size: 16, weight: .semibold))
		  .foregroundStyle(theme.appPrimaryText)
		  .opacity(viewModel.isLoading ? 0 : 1)
		if viewModel.isLoading {
		  ProgressView().tint(theme.appPrimaryText)
		}
	  }
	  .frame(maxWidth: .infinity)
	  .frame(height: 56)
		.background(
			Capsule()
			  .fill(viewModel.canSubmit ? theme.authPink : theme.authPink.opacity(0.45))
			  .shadow(color: theme.authPink.opacity(viewModel.canSubmit ? 0.28 : 0), radius: 14, x: 0, y: 8)
		)
	}
	.disabled(viewModel.isLoading)
	.padding(.top, 4)
  }
  
	var dividerSection: some View {
	  HStack(spacing: 16) {
		Rectangle().fill(theme.authDivider).frame(height: 1)
		Text("Or continue with")
		  .font(.system(size: 14))
		  .foregroundStyle(theme.authSecondaryText)
		  .lineLimit(1)
		Rectangle().fill(theme.authDivider).frame(height: 1)
	  }
	.padding(.horizontal, 16)
  }
  
  var socialButtons: some View {
	HStack(spacing: 16) {
	  socialButton(type: .google)
	  socialButton(type: .apple)
	}
  }
  
  func socialButton(type: SOCIAL_TYPE) -> some View {
	Button {
	  type == .google ? viewModel.signupWithGoogle() : viewModel.signupWithApple()
	} label: {
	  HStack(spacing: 10) {
		PlatformIcon(systemName: type == .google ? "g.circle.fill" : "apple.logo")
		  .font(.system(size: 20, weight: .semibold))
		Text(type == .google ? "Google" : "Apple")
		  .font(.system(size: 15, weight: .semibold))
	  }
	  .foregroundStyle(theme.authPrimaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 54)
	  .background(
		  RoundedRectangle(cornerRadius: 14)
			.fill(theme.appGrayBackground)
			.overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.authSocialBorder, lineWidth: 1))
			.shadow(color: theme.appPrimaryText.opacity(0.025), radius: 6, x: 0, y: 4)
	  )
	}
  }
  
	var bottomLoginSection: some View {
	  HStack(spacing: 4) {
		Text("Already have an account?").foregroundStyle(theme.authSecondaryText)
		Button { router.push(.login) } label: {
			Text("Log In").foregroundStyle(theme.authPink)
		}
	}
	.font(.system(size: 14))
	.padding(.bottom, 18)
  }
}

#if os(iOS)
struct CreateAccountView_Previews: PreviewProvider {
  static var previews: some View { CreateAccountView() }
}
#endif
