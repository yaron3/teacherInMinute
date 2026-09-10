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
  @State var isConfirmPasswordVisible = false
  @FocusState var focusedField: SignupField?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  theme.screenBackground.ignoresSafeArea()
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
		theme.scrim.opacity(0.18).ignoresSafeArea()
		ProgressView()
		  .progressViewStyle(.circular)
		  .scaleEffect(1.6)
		  .tint(theme.primaryText)
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	.navigationTitle(viewModel.screenTitle)
	.onChange(of: viewModel.navigateToChooseRole) { _, newValue in
	  // Replace rather than push so the user cannot navigate back to the
	  // sign-up form after their account has been created.
	  if newValue { router.replace(with: .chooseRole) }
	}
	.onChange(of: viewModel.destination) { _, resume in
	  guard let resume else { return }
	  router.resume(resume)
	  viewModel.destination = nil
	}
	.onChange(of: viewModel.focusField) { _, field in
	  focusedField = field
	}
	.appDialog(
	  viewModel.signUpDialogTitle,
	  isPresented: $viewModel.showAlert,
	  message: viewModel.alertMessage ?? "",
	  actions: [AppDialogAction(viewModel.okLabel)]
	)
	.sheet(isPresented: $viewModel.showingTerms) {
		  
		  if let _ = viewModel.termsURL {
			NavigationStack { AboutWebView(url: viewModel.termsURL!, title: viewModel.eulaTitle) }
		  }
		}
		.sheet(isPresented: $viewModel.showingPrivacy) {
		  if let _ = viewModel.privacyURL {
			NavigationStack { AboutWebView(url: viewModel.privacyURL!, title: viewModel.privacyPolicyTitle) }
		  }
		}
		.appDialog(
		  viewModel.signUpDialogTitle,
		  isPresented: $viewModel.showLegalAlert,
		  message: viewModel.legalAlertMessage,
		  actions: [AppDialogAction(viewModel.okLabel)]
		)
  }
  
  // MARK: - Sections


  
  
  var inputCard: some View {
	VStack(alignment: .leading, spacing: 22) {
	  fieldSection(
		title: viewModel.emailFieldTitle,
		icon: "envelope",
		placeholder: viewModel.emailPlaceholder,
		text: $viewModel.emailOrPhone,
		isSecure: false,
		field: .email,
		isValid: viewModel.emailOrPhone.isEmpty || viewModel.isEmailValid,
		errorMessage: viewModel.emailErrorMessage
	  )
	  fieldSection(
		title: viewModel.passwordFieldTitle,
		icon: "lock.fill",
		placeholder: viewModel.passwordPlaceholder,
		text: $viewModel.password,
		isSecure: !isPasswordVisible,
		field: .password,
		isValid: viewModel.password.isEmpty || viewModel.isPasswordValid,
		errorMessage: viewModel.passwordErrorMessage,
		trailingIcon: isPasswordVisible ? "eye" : "eye.slash",
		trailingAction: { isPasswordVisible.toggle() }
	  )
	  fieldSection(
		title: viewModel.confirmPasswordFieldTitle,
		icon: "lock.fill",
		placeholder: viewModel.confirmPasswordPlaceholder,
		text: $viewModel.confirmPassword,
		isSecure: !isConfirmPasswordVisible,
		field: .confirmPassword,
		// Stays quiet until there is something to compare, so the field does
		// not shout mismatch at every keystroke of the first character.
		isValid: viewModel.confirmPassword.isEmpty || viewModel.doPasswordsMatch,
		errorMessage: viewModel.confirmPasswordErrorMessage,
		trailingIcon: isConfirmPasswordVisible ? "eye" : "eye.slash",
		trailingAction: { isConfirmPasswordVisible.toggle() }
	  )
	}
	.padding(24)
	.background(
	  RoundedRectangle(cornerRadius: flatRadius)
		.fill(theme.cardBackground)
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
	/// Shown under the field while `isValid` is false. Passed in rather than
	/// derived from `field`, so each field owns its own wording.
	errorMessage: String,
	trailingIcon: String? = nil,
	trailingAction: (() -> Void)? = nil
  ) -> some View {
	VStack(alignment: .leading, spacing: 9) {
	  Text(title)
		.font(.system(size: 14, weight: .semibold))
		.foregroundStyle(theme.primaryText)
	  
	  HStack(spacing: 12) {
		PlatformIcon(systemName: icon)
		  .font(.system(size: 15, weight: .medium))
		  .foregroundStyle(isValid ? theme.secondaryText : theme.danger.opacity(0.8))
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
		.textFieldStyle(.plain)
		.font(.system(size: 16))
		.foregroundStyle(theme.primaryText)
		.focused($focusedField, equals: field)
		
		if let trailingIcon {
		  Button { trailingAction?() } label: {
			PlatformIcon(systemName: trailingIcon)
			  .font(.system(size: 16, weight: .medium))
			  .foregroundStyle(theme.secondaryText)
		  }
		}
	  }
	  .padding(.horizontal, 16)
	  .frame(height: 56)
		.background(
		  RoundedRectangle(cornerRadius: flatRadius)
			.fill(theme.fieldBackground)
			.overlay(
			  RoundedRectangle(cornerRadius: flatRadius)
				.stroke(isValid ? theme.controlBorder : theme.danger.opacity(0.5), lineWidth: 1.5)
			)
		)
	  
	  if !isValid {
			Text(errorMessage)
			  .font(.system(size: 11))
			  .foregroundStyle(theme.danger)
			  .padding(.leading, 4)
	  }
	}
  }
  
  var checkboxSection: some View {
	VStack(alignment: .leading, spacing: 18) {
	  checkboxRow(isOn: $viewModel.agreedToTerms, isTermsRow: true)
	  checkboxRow(isOn: $viewModel.sendUpdates,
				  text: viewModel.marketingOptInText,
				  isTermsRow: false)
	}
	.padding(.horizontal, 8)
  }
  
  func checkboxRow(isOn: Binding<Bool>, text: String = "", isTermsRow: Bool = false) -> some View {
	HStack(alignment: .top, spacing: 12) {
		  Button { isOn.wrappedValue.toggle() } label: {
			ZStack {
			  RoundedRectangle(cornerRadius: flatRadiusSmall)
				.fill(isOn.wrappedValue ? theme.accent : theme.cardBackground)
				.frame(width: 18, height: 18)
				.overlay(
				  RoundedRectangle(cornerRadius: flatRadiusSmall)
					.stroke(isOn.wrappedValue ? theme.accent : theme.controlBorder, lineWidth: 1)
				)
		  if isOn.wrappedValue {
			// The box fills with ink when checked, so the tick must invert.
			PlatformIcon(
			  systemName: "checkmark",
			  size: 11,
			  weight: .bold,
			  color: theme.onAccentText
			)
		  }
		}
	  }
	  .buttonStyle(.plain)
	  
	  if isTermsRow { termsTextView() }
	  else {
			Text(text)
			  .font(.system(size: 14))
			  .lineSpacing(4)
			  .foregroundStyle(theme.secondaryText)
		  }
	}
  }
  
	@ViewBuilder
	func termsTextView() -> some View {
	  let markdown = viewModel.agreementMarkdown
#if os(Android)
	  // Skip's `Text` does not parse markdown links, so the tappable link never
	  // rendered (most visible in Hebrew). Show the agreement as plain text with
	  // explicitly tappable Terms/Privacy buttons instead.
	  VStack(alignment: .leading, spacing: 6) {
		Text(Self.plainAgreementText(markdown))
		  .font(.system(size: 14))
		  .lineSpacing(4)
		  .foregroundStyle(theme.secondaryText)

		HStack(spacing: 16) {
		  Button { viewModel.openTerms() } label: {
			Text(viewModel.termsOfServiceTitle)
			  .font(.system(size: 14, weight: .semibold))
			  .foregroundStyle(theme.accent)
		  }
		  Button { viewModel.openPrivacy() } label: {
			Text(viewModel.privacyPolicyTitle)
			  .font(.system(size: 14, weight: .semibold))
			  .foregroundStyle(theme.accent)
		  }
		}
	  }
#else
	  // Parsing the localized string as markdown makes the links tappable in
	  // every language; passing a `String` straight to `Text` renders it
	  // verbatim, which is why the Hebrew (and English) links were dead.
	  let attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
	  Text(attributed)
		.font(.system(size: 14))
		.lineSpacing(4)
		.foregroundStyle(theme.secondaryText)
		.tint(theme.accent)
		.environment(\.openURL, OpenURLAction { url in
		  switch url.absoluteString {
		  case "teacherminute://terms":
			viewModel.openTerms()
			return .handled
		  case "teacherminute://privacy":
			viewModel.openPrivacy()
			return .handled
		  default:
			return .systemAction
		  }
		})
#endif
  }

  /// Strips markdown link syntax (`[text](url)` -> `text`) so the agreement
  /// sentence reads naturally where markdown links can't render.
  static func plainAgreementText(_ markdown: String) -> String {
	var result = ""
	var dropUntilCloseParen = false
	var previous: Character? = nil
	for character in markdown {
	  if dropUntilCloseParen {
		if character == ")" { dropUntilCloseParen = false }
		continue
	  }
	  if character == "[" { continue }
	  if character == "]" { previous = character; continue }
	  if character == "(" && previous == "]" {
		dropUntilCloseParen = true
		previous = nil
		continue
	  }
	  previous = character
	  result.append(character)
	}
	return result
  }
  
  var continueButton: some View {
	Button {
	  Task { await viewModel.signup() }
	} label: {
	  ZStack {
		Text(viewModel.continueToRoleSelectionLabel)
		  .font(.system(size: 17, weight: .bold))
		  .foregroundStyle(viewModel.canSubmit ? theme.onAccentText : theme.secondaryText)
		  .opacity(viewModel.isLoading ? 0 : 1)
		if viewModel.isLoading {
		  ProgressView().tint(theme.onAccentText)
		}
	  }
	  .frame(maxWidth: .infinity)
	  .frame(height: 54)
		.background(
			RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
			  .fill(viewModel.canSubmit ? theme.accent : theme.cardBackground)
		)
	}
	.disabled(viewModel.isLoading)
	.padding(.top, 4)
  }
  
	var dividerSection: some View {
	  HStack(spacing: 16) {
		Rectangle().fill(theme.separator).frame(height: 1)
		Text(viewModel.orContinueWithLabel)
		  .font(.system(size: 14))
		  .foregroundStyle(theme.secondaryText)
		  .lineLimit(1)
		Rectangle().fill(theme.separator).frame(height: 1)
	  }
	.padding(.horizontal, 16)
  }
  
  var socialButtons: some View {
	HStack(spacing: 16) {
	  socialButton(type: .google)
	  #if !os(Android)
		  socialButton(type: .apple)
#endif
	}
  }
  
  func socialButton(type: SOCIAL_TYPE) -> some View {
	Button {
	  type == .google ? viewModel.signupWithGoogle() : viewModel.signupWithApple()
	} label: {
	  HStack(spacing: 10) {
		PlatformIcon(systemName: type == .google ? "google-logo" : "apple.logo")
		  .font(.system(size: 20, weight: .semibold))
		Text(type == .google ? viewModel.googleLabel : viewModel.appleLabel)
		  .font(.system(size: 15, weight: .semibold))
	  }
	  .foregroundStyle(theme.primaryText)
	  .frame(maxWidth: .infinity)
	  .frame(height: 54)
	  .background(
		  RoundedRectangle(cornerRadius: flatRadius)
			.fill(theme.cardBackground)
			.overlay(RoundedRectangle(cornerRadius: flatRadius).stroke(theme.controlBorder, lineWidth: 1))
	  )
	}
  }
  
	var bottomLoginSection: some View {
	  HStack(spacing: 4) {
		Text(viewModel.alreadyHaveAccountText).foregroundStyle(theme.secondaryText)
		Button { router.push(.login) } label: {
			Text(viewModel.logInLabel).foregroundStyle(theme.accent)
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
