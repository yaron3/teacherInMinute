import SwiftUI

/// The profile step of a student's sign-up, on the brand's dark ground. The
/// same step as `CompleteProfileView`, on the same view model — the name, an
/// optional phone number, then on to the permissions or home — drawn as the
/// student app's design has it.
struct StudentCompleteProfileView: View {
  @State var viewModel: CompleteProfileViewModel
  @Environment(\.appRouter) var router

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
        .scrollDismissesKeyboard(.interactively)
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
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .onAppear {
      viewModel.onContinue = {
        if viewModel.shouldShowPermissionsOnContinue && PermissionsSetupStore.shouldShowForCurrentUser() {
          // Pushed, not replaced: the permissions step is part of the same
          // walk-backwards flow.
          router.push(.permissionsSetup(role: viewModel.role))
        } else {
          router.enterMainTabs(role: viewModel.role)
        }
      }
      viewModel.checkAndAutoAdvance()
    }
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

      if let error = viewModel.errorMessage {
        Text(error)
          .font(.system(size: 12))
          .foregroundStyle(theme.danger)
      }

      BrandPrimaryButton(
        title: viewModel.continueToMinutesLabel,
        isLoading: viewModel.isLoading,
        isEnabled: viewModel.canContinue
      ) {
        viewModel.continueFlow()
      }
    }
    .brandCard()
  }
}

#if os(iOS)
struct StudentCompleteProfileView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      StudentCompleteProfileView()
    }
  }
}
#endif
