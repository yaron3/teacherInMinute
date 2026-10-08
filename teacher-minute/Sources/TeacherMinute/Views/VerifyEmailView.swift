//
//  VerifyEmailView.swift
//  teacher-minute
//
//  The last profile step of a student's sign-up, on the brand's ground: the
//  address a verification link went to, a way back to correct it or the phone
//  number, and "Not now" for a student who would rather verify later from the
//  home screen's banner.
//

import SwiftUI

struct VerifyEmailView: View {
  @State var viewModel: VerifyEmailViewModel
  @Environment(\.appRouter) var router
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.colorScheme) var colorScheme
  @State var emailLink = EmailVerificationLinkViewModel.shared
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(email: String) {
    self._viewModel = State(wrappedValue: VerifyEmailViewModel(email: email))
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          Circle()
            .fill(theme.accentBackground)
            .frame(width: 78, height: 78)
            .overlay {
              PlatformIcon(
                systemName: "envelope.badge.fill",
                size: 32,
                weight: .semibold,
                color: theme.brandActionBackground
              )
            }
            .padding(.top, 24)

          Text(viewModel.verifyEmailTitle)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
            .multilineTextAlignment(.center)
            .padding(.top, 30)

          Text(viewModel.linkSentToText)
            .font(.system(size: 15))
            .foregroundStyle(theme.brandSecondaryText)
            .multilineTextAlignment(.center)
            .padding(.top, 12)

          Text(viewModel.email)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
            .multilineTextAlignment(.center)
            .padding(.top, 6)

          Text(viewModel.tapLinkHint)
            .font(.system(size: 14))
            .foregroundStyle(theme.brandSecondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

          Button {
            OnboardingBackCoordinator.shared.handleBack()
          } label: {
            HStack(spacing: 6) {
              PlatformIcon(systemName: "pencil", size: 12, weight: .semibold, color: theme.brandActionBackground)
              Text(viewModel.changeContactInfoLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.brandActionBackground)
            }
            .tappableFrame()
          }
          .buttonStyle(.plain)
          .padding(.top, 14)

          if let offer = viewModel.offerText {
            HStack(alignment: .top, spacing: 12) {
              PlatformIcon(systemName: "gift.fill", size: 20, weight: .semibold, color: theme.brandActionBackground)
              Text(offer)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.onDarkFill)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .brandCard()
            .padding(.top, 28)
          }
        }
        .padding(.horizontal, 20)
      }

      VStack(spacing: 12) {
        // No "I've verified": the link itself brings the student back and
        // moves this step on.
        BrandSecondaryButton(title: viewModel.resendLabel) {
          Task { await viewModel.resendTapped() }
        }
        .disabled(viewModel.isWorking)

        Button {
          viewModel.notNowTapped()
        } label: {
          Text(viewModel.notNowLabel)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
            .frame(maxWidth: .infinity)
            .tappableFrame()
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
    }
    .screenGround()
    .environment(\.colorScheme, .dark)
    // The header draws the back button, through the same handler as
    // Android's system back: one step back, to the profile form.
    .onboardingBackHandling(viewModel: viewModel)
    .toolbar(.hidden, for: .navigationBar)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .appDialog(
      viewModel.dialog?.title ?? "",
      isPresented: Binding(
        get: { viewModel.dialog != nil },
        set: { if !$0 { viewModel.dismissDialog() } }
      ),
      message: viewModel.dialog?.message,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
    .trackScreen(AnalyticsScreen.verifyEmail)
    .onAppear {
      viewModel.onFinished = {
        if PermissionsSetupStore.shouldShowForCurrentUser() {
          router.push(.permissionsSetup(role: .student))
        } else {
          router.enterMainTabs(role: .student)
        }
      }
      viewModel.onSessionEnded = {
        router.startLogin()
      }
    }
    .task {
      await viewModel.load()
    }
    // Coming back from the mail app is the usual moment the link was opened.
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await viewModel.checkQuietly() }
    }
    // The link verified the address; the app root says how the reward went.
    .onChange(of: emailLink.verifiedVersion) { _, _ in
      viewModel.linkVerifiedEmail()
    }
  }

  /// The way back, at the far end, as on the other steps.
  private var header: some View {
    HStack(spacing: 12) {
      Spacer(minLength: 0)
      BrandBackButton(accessibilityLabel: viewModel.backLabel) {
        OnboardingBackCoordinator.shared.handleBack()
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }
}

#if os(iOS)
struct VerifyEmailView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      VerifyEmailView(email: "student@example.com")
    }
  }
}
#endif
