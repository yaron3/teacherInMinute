//
//  PermissionsSetupView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
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
            Spacer()
                .frame(height: 72)

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
                    .fill(theme.accentBackground)
                    .frame(width: 78, height: 78)
                    .overlay {
                        PlatformIcon(
                            systemName: "mic.fill",
                            size: 34,
                            weight: .semibold,
                            color: theme.accent
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
                            color: theme.accent
                        )
                    }
                    .offset(x: 12, y: 8)
            }

            Text(LocalizationSupport.localized("Connect & Learn"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 34)

            Text(LocalizationSupport.localized("To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly."))
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            VStack(spacing: 16) {
                PermissionCard(
                    icon: "mic.fill",
                    iconColor: theme.accent,
                    iconBackground: theme.accentBackground,
                    title: LocalizationSupport.localized("Microphone"),
                    subtitle: LocalizationSupport.localized("Talk live with\nteachers to solve\nmath problems\ntogether in real-\ntime."),
                    isOn: $viewModel.microphoneEnabled
                )

                PermissionCard(
                    icon: "camera.fill",
                    iconColor: theme.positive,
                    iconBackground: theme.positive.opacity(0.14),
                    title: LocalizationSupport.localized("Camera"),
                    subtitle: LocalizationSupport.localized("Use video in live\nlessons and update\nyour profile photo\nwhen needed."),
                    isOn: $viewModel.cameraEnabled
                )
                // Notifications are requested after the first lesson (with a
                // dedicated explanation), so they are not shown here.
            }
            .padding(.top, 34)

            Spacer()

            AuthPrimaryButton(title: LocalizationSupport.localized("Continue Setup"), systemImage: "arrow.right") {
                viewModel.continueSetup()
            }

            Button {
                viewModel.limitedMode()
            } label: {
                Text(LocalizationSupport.localized("Not now, use limited mode"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 18)
        .background(theme.screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .trackScreen(AnalyticsScreen.permissionsSetup)
        .onAppear {
            viewModel.onContinue = {
                PermissionsSetupStore.markCompletedForCurrentUser()
                router.enterMainTabs(role: role)
            }
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
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
                .fill(iconBackground)
                .frame(width: 42, height: 42)
                .overlay {
                    PlatformIcon(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .lineSpacing(4)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.positive)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
                .stroke(theme.accent.opacity(0.10), lineWidth: 1)
        }
    }
}
