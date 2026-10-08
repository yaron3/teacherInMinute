import SwiftUI

/// The profile step of sign-up, on the brand's dark ground: the name, a phone
/// number — optional for a student — and, for a teacher, where their payouts
/// should go; then on to the permissions or home.
struct CompleteProfileView: View {
  @State var viewModel: CompleteProfileViewModel
  @Environment(\.appRouter) var router
  @FocusState var focusedField: Field?

  enum Field: Hashable {
    case fullName, email, phone
  }

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(viewModel: CompleteProfileViewModel = CompleteProfileViewModel(role: .student)) {
    self._viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground()

      VStack(spacing: 0) {
        header
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.introText)
              .font(.system(size: 15))
              .foregroundStyle(theme.brandSecondaryText)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)

            formCard
          }
          .padding(.horizontal, 20)
          .padding(.top, 16)
          .padding(.bottom, 20)
        }
        .formScrollDismissesKeyboard()
      }

      if viewModel.isCheckingCompletion {
        ZStack {
          theme.brandScrim.opacity(0.4).ignoresSafeArea()
          VStack(spacing: 12) {
            ProgressView()
              .progressViewStyle(.circular)
              .scaleEffect(1.6)
              .tint(theme.onDarkFill)
            Text(viewModel.loadingText)
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(theme.onDarkFill)
          }
        }
      }
    }
    .environment(\.colorScheme, .dark)
    // The header draws the back button. It walks onboarding backwards through
    // the same handler as Android's system back, which asks before a first
    // step's back signs the account out.
    .onboardingBackHandling(viewModel: viewModel)
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .onAppear {
      viewModel.onContinue = {
        if viewModel.needsEmailVerification {
          router.push(.verifyEmail(email: viewModel.email))
        } else if viewModel.shouldShowPermissionsOnContinue && PermissionsSetupStore.shouldShowForCurrentUser() {
          // Pushed, not replaced: the permissions step is part of the same
          // walk-backwards flow, and replacing here wiped every earlier step
          // out of the stack.
          router.push(.permissionsSetup(role: viewModel.role))
        } else {
          router.enterMainTabs(role: viewModel.role)
        }
      }
      viewModel.checkAndAutoAdvance()
    }
    .appDialog(
      viewModel.payoutMissingDialogTitle,
      isPresented: $viewModel.showMissingPayoutInfoConfirmation,
      message: viewModel.payoutMissingDialogMessage,
      actions: [
        AppDialogAction(viewModel.addNowLabel, kind: .cancel),
        AppDialogAction(viewModel.continueAnywayLabel) {
          viewModel.continueWithoutPayoutInfo()
        }
      ]
    )
    .trackScreen(AnalyticsScreen.completeProfile)
  }

  /// The title, then the way back, as designed: the back button at the far
  /// end from where the text starts.
  private var header: some View {
    HStack(spacing: 12) {
      Text(viewModel.screenTitle)
        .font(.system(size: 34, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 0)
      BrandBackButton(accessibilityLabel: viewModel.backLabel) {
        OnboardingBackCoordinator.shared.handleBack()
      }
    }
    .padding(.horizontal, 20)
    .frame(height: 76)
  }

  private var formCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      BrandTextField(
        title: viewModel.fullNameFieldTitle,
        placeholder: viewModel.fullNamePlaceholder,
        text: $viewModel.fullName,
        icon: "brand-user",
        textContentType: .name,
        autocapitalization: .words
      )
      .focused($focusedField, equals: .fullName)
      .submitLabel(.next)
      .onSubmit { focusedField = viewModel.showsEmailField ? .email : .phone }

      if viewModel.showsEmailField {
        BrandTextField(
          title: viewModel.emailFieldTitle,
          placeholder: viewModel.emailPlaceholder,
          text: $viewModel.email,
          icon: "brand-mail",
          isValid: !viewModel.showsEmailError,
          errorMessage: viewModel.emailErrorMessage,
          keyboardType: .emailAddress,
          textContentType: .emailAddress,
          autocapitalization: .never
        )
        .focused($focusedField, equals: .email)
        .submitLabel(.next)
        .onSubmit { focusedField = .phone }
      }

      BrandTextField(
        title: viewModel.phoneFieldTitle(isOptional: viewModel.role == .student),
        placeholder: viewModel.phonePlaceholder,
        text: $viewModel.phoneNumber,
        icon: "brand-phone",
        isValid: !viewModel.showsPhoneError,
        errorMessage: viewModel.phoneErrorMessage,
        keyboardType: .phonePad,
        textContentType: .telephoneNumber,
        autocapitalization: .never
      )
      .focused($focusedField, equals: .phone)
      .submitLabel(.done)

      if viewModel.role == .teacher {
        payoutMethodSection
      }

      if let error = viewModel.errorMessage {
        Text(error)
          .font(.system(size: 12))
          .foregroundStyle(theme.danger)
      }

      // A student's step leads on to the free minutes a verified account
      // earns, and says so.
      BrandPrimaryButton(
        title: viewModel.role == .student ? viewModel.continueToMinutesLabel : viewModel.continueLabel,
        isLoading: viewModel.isLoading,
        isEnabled: viewModel.canContinue
      ) {
        viewModel.continueFlow()
      }
    }
    .brandCard()
  }

  /// Which destination the teacher would like — the choice only, with no
  /// account details: those are typed later into the payout form, which opens
  /// on whichever tab is picked here.
  private var payoutMethodSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(viewModel.payoutMethodSectionTitle)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)

      PayoutMethodTypePicker(
        types: viewModel.availablePayoutMethodTypes,
        selected: viewModel.payoutMethodType,
        onSelect: { type in viewModel.selectPayoutMethodType(type) }
      )

      Text(viewModel.payoutMethodSectionHint)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#if os(iOS)
struct CompleteProfileView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      CompleteProfileView()
    }
  }
}
#endif
