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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.authPinkSoft)
                    .frame(width: 78, height: 78)
                    .overlay {
                        PlatformIcon(
                            systemName: "mic.fill",
                            size: 34,
                            weight: .semibold,
                            color: theme.authPink
                        )
                    }
                    .shadow(color: theme.authPink.opacity(0.1), radius: 24, x: 0, y: 12)

                Circle()
                    .fill(theme.authPurpleSoft)
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(
                            systemName: "bell.fill",
                            size: 14,
                            weight: .semibold,
                            color: theme.authPurple
                        )
                    }
                    .offset(x: 12, y: 8)
            }

            Text(LocalizationSupport.localized("Connect & Learn"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.authPrimaryText)
                .padding(.top, 34)

            Text(LocalizationSupport.localized("To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly."))
                .font(.system(size: 14))
                .foregroundStyle(theme.authSecondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            VStack(spacing: 16) {
                PermissionCard(
                    icon: "mic.fill",
                    iconColor: theme.authPink,
                    iconBackground: theme.authPinkSoft,
                    title: "Microphone",
                    subtitle: LocalizationSupport.localized("Talk live with\nteachers to solve\nmath problems\ntogether in real-\ntime."),
                    isOn: $viewModel.microphoneEnabled
                )

                PermissionCard(
                    icon: "camera.fill",
                    iconColor: theme.authGreen,
                    iconBackground: theme.authGreen.opacity(0.14),
                    title: "Camera",
                    subtitle: LocalizationSupport.localized("Use video in live\\nlessons and update\\nyour profile photo\\nwhen needed."),
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
                    .foregroundStyle(theme.authSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 18)
        .background(Color(.systemBackground))
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
                    .foregroundStyle(theme.authPrimaryText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.authSecondaryText)
                    .lineSpacing(4)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.authGreen)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(theme.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.authPink.opacity(0.10), lineWidth: 1)
        }
		.shadow(color: theme.appPrimaryText.opacity(0.03), radius: 18, x: 0, y: 10)
    }
}
