//
//  PermissionsSetupView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//
//  The last step of onboarding, on the brand's ground: the microphone and
//  camera a lesson needs, each with its switch.
//

import SwiftUI

struct PermissionsSetupView: View {
  let role: AuthRole
  @State var viewModel = PermissionsSetupViewModel()
  @Environment(\.appRouter) var router
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(role: AuthRole = .student) {
    self.role = role
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
              .fill(theme.accentBackground)
              .frame(width: 78, height: 78)
              .overlay {
                PlatformIcon(
                  systemName: "mic.fill",
                  size: 34,
                  weight: .semibold,
                  color: theme.brandActionBackground
                )
              }

            Circle()
              .fill(theme.accentBackground)
              .frame(width: 34, height: 34)
              .overlay {
                PlatformIcon(
                  systemName: "bell.fill",
                  size: 14,
                  weight: .semibold,
                  color: theme.brandActionBackground
                )
              }
              .offset(x: 12, y: 8)
          }
          .padding(.top, 24)

          Text(viewModel.screenTitle)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
            .multilineTextAlignment(.center)
            .padding(.top, 34)

          Text(viewModel.introText)
            .font(.system(size: 15))
            .foregroundStyle(theme.brandSecondaryText)
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

          VStack(spacing: 16) {
            PermissionCard(
              icon: "mic.fill",
              title: viewModel.microphoneCardTitle,
              subtitle: viewModel.microphoneCardSubtitle,
              isOn: $viewModel.microphoneEnabled
            )

            PermissionCard(
              icon: "camera.fill",
              title: viewModel.cameraCardTitle,
              subtitle: viewModel.cameraCardSubtitle,
              isOn: $viewModel.cameraEnabled
            )
            // Notifications are requested after the first lesson (with a
            // dedicated explanation), so they are not shown here.
          }
          .padding(.top, 34)
        }
        .padding(.horizontal, 20)
      }

      VStack(spacing: 0) {
        AuthPrimaryButton(title: viewModel.continueSetupLabel) {
          viewModel.continueSetup()
        }

        Button {
          viewModel.limitedMode()
        } label: {
          Text(viewModel.skipLabel)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
        .padding(.bottom, 24)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
    }
    .screenGround()
    .environment(\.colorScheme, .dark)
    // The header draws the back button, through the same handler as
    // Android's system back.
    .onboardingBackHandling(viewModel: viewModel)
    .toolbar(.hidden, for: .navigationBar)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .trackScreen(AnalyticsScreen.permissionsSetup)
    .onAppear {
      viewModel.onContinue = {
        PermissionsSetupStore.markCompletedForCurrentUser()
        router.enterMainTabs(role: role)
      }
    }
  }

  /// The way back, at the far end, as on the other steps.
  private var header: some View {
    HStack(spacing: 12) {
      Spacer(minLength: 0)
      BrandBackButton(accessibilityLabel: viewModel.onboardingBackLabel) {
        OnboardingBackCoordinator.shared.handleBack()
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }
}

/// A permission a lesson needs, with its switch at the far end.
struct PermissionCard: View {
  let icon: String
  let title: String
  let subtitle: String
  @Binding var isOn: Bool
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Circle()
        .fill(theme.accentBackground)
        .frame(width: 42, height: 42)
        .overlay {
          PlatformIcon(systemName: icon, size: 17, weight: .semibold, color: theme.brandActionBackground)
        }

      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)

        Text(subtitle)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
          .lineSpacing(4)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      BrandToggle(isOn: isOn) {
        isOn.toggle()
      }
    }
    .brandCard(padding: 18)
  }
}
