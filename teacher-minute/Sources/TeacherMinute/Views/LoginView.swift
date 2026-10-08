import SwiftUI

/// The log-in screen, on the brand's dark ground, as the sign-up screen is.
struct LoginView: View {
  @State var viewModel = LoginViewModel()
  @Environment(\.appRouter) var router
  @FocusState var focusedField: Field?

  enum Field: Hashable {
    case email, password
  }

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
        .formScrollDismissesKeyboard()
      }

      if viewModel.isLoading {
        theme.brandScrim.opacity(0.6).ignoresSafeArea()
        VStack(spacing: 14) {
          ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(1.6)
            .tint(theme.onDarkFill)
          Text(viewModel.signingInProgressText)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(theme.onDarkFill)
        }
      }
    }
    .environment(\.colorScheme, .dark)
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .onChange(of: viewModel.destination) { _, resume in
      guard let resume else { return }
      router.resume(resume)
      viewModel.destination = nil
    }
    .appDialog(
      viewModel.signInErrorTitle,
      isPresented: $viewModel.showAlert,
      message: viewModel.alertMessage ?? viewModel.genericErrorMessage,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
    .trackScreen(AnalyticsScreen.login)
  }

  // MARK: - Sections

  /// The way back at the far end, as on the sign-up screen.
  private var header: some View {
    HStack(spacing: 12) {
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
      Text(viewModel.subtitleText)
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
        keyboardType: .emailAddress,
        textContentType: .emailAddress,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .email)
      .submitLabel(.next)
      .onSubmit { focusedField = .password }
      .accessibilityIdentifier("email_input")

      BrandTextField(
        title: viewModel.passwordFieldTitle,
        placeholder: viewModel.passwordPlaceholder,
        text: $viewModel.password,
        icon: "brand-lock",
        isSecure: true,
        textContentType: .password,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .password)
      .submitLabel(.done)
      .accessibilityIdentifier("password_input")

      Button {
        viewModel.forgotPassword()
      } label: {
        Text(viewModel.forgotPasswordLabel)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.brandActionBackground)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .buttonStyle(.plain)

      BrandPrimaryButton(
        title: viewModel.logInButtonLabel,
        isLoading: viewModel.isLoading,
        isEnabled: viewModel.canSubmit
      ) {
        Task { await viewModel.login() }
      }

      divider
      socialButtons
      signUpRow
    }
    .brandCard()
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

  /// Apple on the left and Google on the right in both languages, as on the
  /// sign-up screen. Sign in with Apple is iOS only.
  private var socialButtons: some View {
    HStack(spacing: 12) {
#if !os(Android)
      socialButton(label: viewModel.appleLabel, identifier: "log_in_apple") {
		Image(systemName: "apple.logo")
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onDarkFill)
          .frame(width: 18, height: 18)
      } action: {
        viewModel.loginWithApple()
      }
#endif
      socialButton(label: viewModel.googleLabel, identifier: "log_in_google") {
        // Google's own mark: its guidelines do not allow a recoloured one.
        Image("google-logo", bundle: .module)
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
      } action: {
        viewModel.loginWithGoogle()
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

  private var signUpRow: some View {
    HStack(spacing: 4) {
      Text(viewModel.noAccountText)
        .foregroundStyle(theme.brandSecondaryText)
      Button {
        router.push(.createAccount)
      } label: {
        Text(viewModel.signUpLabel)
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
struct LoginView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      LoginView()
    }
  }
}
#endif
