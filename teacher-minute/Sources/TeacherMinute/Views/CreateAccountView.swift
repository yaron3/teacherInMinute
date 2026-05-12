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
  
  var body: some View {
	ZStack {
	  Color.white.ignoresSafeArea()
	  VStack(spacing: 0) {
		ScrollView(showsIndicators: false) {
		  VStack(alignment: .leading, spacing: 24) {
			titleSection
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
		Color.black.opacity(0.18).ignoresSafeArea()
		ProgressView()
		  .progressViewStyle(.circular)
		  .scaleEffect(1.6)
		  .tint(.white)
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
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
  
  var titleSection: some View {
	VStack(alignment: .leading, spacing: 10) {
	  Text("Create Account")
		.font(.system(size: 32, weight: .bold))
		.foregroundStyle(Color(hex: "#111827"))
	  Text("Join Math Connect to start learning or\nteaching today.")
		.font(.system(size: 16, weight: .regular))
		.lineSpacing(5)
		.foregroundStyle(Color(hex: "#6B7280"))
	}
  }
  
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
		.fill(Color.white)
		.shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 10)
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
		.foregroundStyle(Color(hex: "#111827"))
	  
	  HStack(spacing: 12) {
		PlatformIcon(systemName: icon)
		  .font(.system(size: 15, weight: .medium))
		  .foregroundStyle(isValid ? Color(hex: "#9CA3AF") : Color.red.opacity(0.8))
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
		.foregroundStyle(Color(hex: "#111827"))
		.focused($focusedField, equals: field)
		
		if let trailingIcon {
		  Button { trailingAction?() } label: {
			PlatformIcon(systemName: trailingIcon)
			  .font(.system(size: 16, weight: .medium))
			  .foregroundStyle(Color(hex: "#9CA3AF"))
		  }
		}
	  }
	  .padding(.horizontal, 16)
	  .frame(height: 56)
	  .background(
		RoundedRectangle(cornerRadius: 16)
		  .fill(Color(hex: "#F9FAFB"))
		  .overlay(
			RoundedRectangle(cornerRadius: 16)
			  .stroke(isValid ? Color(hex: "#EEF2F7") : Color.red.opacity(0.5), lineWidth: 1.5)
		  )
	  )
	  
	  if !isValid {
		Text(field == .email ? "Enter a valid email address." : "Must be at least 6 characters.")
		  .font(.system(size: 11))
		  .foregroundStyle(.red)
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
			.fill(isOn.wrappedValue ? Color(hex: "#EC4899") : Color.white)
			.frame(width: 18, height: 18)
			.overlay(
			  RoundedRectangle(cornerRadius: 4)
				.stroke(isOn.wrappedValue ? Color(hex: "#EC4899") : Color(hex: "#CBD5E1"), lineWidth: 1)
			)
		  if isOn.wrappedValue {
			PlatformIcon(systemName: "checkmark")
			  .font(.system(size: 11, weight: .bold))
			  .foregroundStyle(.white)
		  }
		}
	  }
	  .buttonStyle(.plain)
	  
	  if isTermsRow { termsTextView() }
	  else {
		Text(text)
		  .font(.system(size: 14))
		  .lineSpacing(4)
		  .foregroundStyle(Color(hex: "#6B7280"))
	  }
	}
  }
  
  func termsTextView() -> some View {
	VStack(alignment: .leading, spacing: 2) {
	  HStack(spacing: 0) {
		Text("I agree to the ").foregroundStyle(Color(hex: "#6B7280"))
		Text("Terms of Service").foregroundStyle(Color(hex: "#EC4899"))
		Text(" and").foregroundStyle(Color(hex: "#6B7280"))
	  }
	  Text("Privacy Policy.").foregroundStyle(Color(hex: "#EC4899"))
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
		  .foregroundStyle(.white)
		  .opacity(viewModel.isLoading ? 0 : 1)
		if viewModel.isLoading {
		  ProgressView().tint(.white)
		}
	  }
	  .frame(maxWidth: .infinity)
	  .frame(height: 56)
	  .background(
		Capsule()
		  .fill(viewModel.canSubmit ? Color(hex: "#EC4899") : Color(hex: "#EC4899").opacity(0.45))
		  .shadow(color: Color(hex: "#EC4899").opacity(viewModel.canSubmit ? 0.28 : 0), radius: 14, x: 0, y: 8)
	  )
	}
	.disabled(viewModel.isLoading)
	.padding(.top, 4)
  }
  
  var dividerSection: some View {
	HStack(spacing: 16) {
	  Rectangle().fill(Color(hex: "#E5E7EB")).frame(height: 1)
	  Text("Or continue with")
		.font(.system(size: 14))
		.foregroundStyle(Color(hex: "#6B7280"))
		.lineLimit(1)
	  Rectangle().fill(Color(hex: "#E5E7EB")).frame(height: 1)
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
	  .foregroundStyle(Color(hex: "#111827"))
	  .frame(maxWidth: .infinity)
	  .frame(height: 54)
	  .background(
		RoundedRectangle(cornerRadius: 14)
		  .fill(Color.white)
		  .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#E5E7EB"), lineWidth: 1))
		  .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 4)
	  )
	}
  }
  
  var bottomLoginSection: some View {
	HStack(spacing: 4) {
	  Text("Already have an account?").foregroundStyle(Color(hex: "#6B7280"))
	  Button { router.push(.login) } label: {
		Text("Log In").foregroundStyle(Color(hex: "#EC4899"))
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
