import SwiftUI

/// Instant Teacher's sign-up screen, on the brand's dark ground. It runs on
/// the same `CreateAccountViewModel` as Pro Teacher's `CreateAccountView`:
/// only the look is the student app's own.
struct StudentSignUpView: View {
  @State var viewModel = CreateAccountViewModel()
  @Environment(\.appRouter) var router
  @FocusState var focusedField: SignupField?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground()

      VStack(spacing: 0) {
        header
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 16) {
            hero
            formCard
          }
          .padding(.horizontal, 20)
          .padding(.top, 16)
          .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
      }

      if viewModel.isLoading {
        theme.brandScrim.opacity(0.4).ignoresSafeArea()
        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(1.6)
          .tint(theme.onDarkFill)
      }
    }
    .environment(\.colorScheme, .dark)
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    // `resume` replaces the path rather than pushing onto it, so the user
    // cannot navigate back to the sign-up form once their account exists.
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
      if let url = viewModel.termsURL {
        NavigationStack { AboutWebView(url: url, title: viewModel.eulaTitle) }
      }
    }
    .sheet(isPresented: $viewModel.showingPrivacy) {
      if let url = viewModel.privacyURL {
        NavigationStack { AboutWebView(url: url, title: viewModel.privacyPolicyTitle) }
      }
    }
    .appDialog(
      viewModel.signUpDialogTitle,
      isPresented: $viewModel.showLegalAlert,
      message: viewModel.legalAlertMessage,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
    .trackScreen(AnalyticsScreen.createAccount)
  }

  // MARK: - Sections

  /// Where the student is in sign-up, then the way back, as designed: the
  /// back button at the far end from where the text starts.
  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.signUpStepLabel)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
        Text(viewModel.signUpStepTitle)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
      }
      Spacer(minLength: 0)
      BrandBackButton(accessibilityLabel: viewModel.backLabel) {
        router.pop()
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(viewModel.screenTitle)
        .font(.system(size: 34, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
      Text(viewModel.signUpSubtitle)
        .font(.system(size: 15))
        .foregroundStyle(theme.brandSecondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var formCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      BrandTextField(
        title: viewModel.emailFieldTitle,
        placeholder: viewModel.emailPlaceholder,
        text: $viewModel.emailOrPhone,
        isValid: viewModel.emailOrPhone.isEmpty || viewModel.isEmailValid,
        errorMessage: viewModel.emailErrorMessage,
        keyboardType: .emailAddress,
        textContentType: .emailAddress,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .email)

      BrandTextField(
        title: viewModel.passwordFieldTitle,
        placeholder: viewModel.passwordPlaceholder,
        text: $viewModel.password,
        isSecure: true,
        isValid: viewModel.password.isEmpty || viewModel.isPasswordValid,
        errorMessage: viewModel.passwordErrorMessage,
        textContentType: .newPassword,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .password)

      BrandTextField(
        title: viewModel.confirmPasswordFieldTitle,
        placeholder: viewModel.confirmPasswordPlaceholder,
        text: $viewModel.confirmPassword,
        isSecure: true,
        // Stays quiet until there is something to compare, so the field does
        // not shout mismatch at every keystroke of the first character.
        isValid: viewModel.confirmPassword.isEmpty || viewModel.doPasswordsMatch,
        errorMessage: viewModel.confirmPasswordErrorMessage,
        textContentType: .newPassword,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .confirmPassword)

      consentRow(isOn: $viewModel.agreedToTerms) {
        agreementText
      }
      consentRow(isOn: $viewModel.sendUpdates) {
        consentText(viewModel.marketingOptInText)
      }

      BrandPrimaryButton(title: viewModel.continueLabel, isLoading: viewModel.isLoading) {
        Task { await viewModel.signup() }
      }

      divider
      socialButtons
      loginRow
    }
    .brandCard()
  }

  /// The sentence, then its box at the far end, as designed.
  private func consentRow<Content: View>(isOn: Binding<Bool>, @ViewBuilder text: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 8) {
      text()
        .frame(maxWidth: .infinity, alignment: .leading)
      BrandCheckbox(isOn: isOn)
    }
  }

  private func consentText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(theme.brandSecondaryText)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The agreement, with its Terms and Privacy links: markdown links on iOS,
  /// and on Android, whose `Text` does not parse them, the plain sentence with
  /// the two links under it.
  @ViewBuilder
  private var agreementText: some View {
    let markdown = viewModel.agreementMarkdown
#if os(Android)
    VStack(alignment: .leading, spacing: 6) {
      consentText(CreateAccountView.plainAgreementText(markdown))
      HStack(spacing: 16) {
        Button { viewModel.openTerms() } label: {
          Text(viewModel.termsOfServiceTitle)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
        }
        .buttonStyle(.plain)
        Button { viewModel.openPrivacy() } label: {
          Text(viewModel.privacyPolicyTitle)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
        }
        .buttonStyle(.plain)
      }
    }
#else
    let attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    Text(attributed)
      .font(.system(size: 13))
      .foregroundStyle(theme.brandSecondaryText)
      .lineSpacing(3)
      .tint(theme.brandActionBackground)
      .fixedSize(horizontal: false, vertical: true)
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

  private var divider: some View {
    HStack(spacing: 8) {
      Rectangle()
        .fill(theme.brandControlBorder)
        .frame(height: 1)
      Text(viewModel.orContinueWithLabel)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .fixedSize()
      Rectangle()
        .fill(theme.brandControlBorder)
        .frame(height: 1)
    }
  }

  /// Apple on the left and Google on the right in both languages, as
  /// designed. Sign in with Apple is iOS only.
  private var socialButtons: some View {
    HStack(spacing: 12) {
#if !os(Android)
      socialButton(label: viewModel.appleLabel, identifier: "sign_up_apple") {
        Image("brand-apple", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onDarkFill)
          .frame(width: 18, height: 18)
      } action: {
        viewModel.signupWithApple()
      }
#endif
      socialButton(label: viewModel.googleLabel, identifier: "sign_up_google") {
        // Google's own mark: its guidelines do not allow a recoloured one.
        Image("google-logo", bundle: .module)
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
      } action: {
        viewModel.signupWithGoogle()
      }
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private func socialButton<Icon: View>(
    label: String,
    identifier: String,
    @ViewBuilder icon: () -> Icon,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      action()
    } label: {
      HStack(spacing: 8) {
        icon()
        Text(label)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 36)
      .background(theme.brandBackgroundTop)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }

  private var loginRow: some View {
    HStack(spacing: 4) {
      Text(viewModel.alreadyHaveAccountText)
        .foregroundStyle(theme.brandSecondaryText)
      Button {
        router.push(.login)
      } label: {
        Text(viewModel.logInLabel)
          .fontWeight(.bold)
          .foregroundStyle(theme.brandActionBackground)
      }
      .buttonStyle(.plain)
    }
    .font(.system(size: 14))
    .frame(maxWidth: .infinity)
  }
}

#if os(iOS)
struct StudentSignUpView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      StudentSignUpView()
    }
  }
}
#endif
