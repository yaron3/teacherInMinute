//
//  PermissionsSetupView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct PermissionsSetupView: View {
    @State var viewModel = PermissionsSetupViewModel()
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
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
                        PlatformIcon(systemName: "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(theme.authPink)
                    }
                    .shadow(color: theme.authPink.opacity(0.1), radius: 24, x: 0, y: 12)

                Circle()
                    .fill(theme.authPurpleSoft)
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(systemName: "bell.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.authPurple)
                    }
                    .offset(x: 12, y: 8)
            }

            Text("Connect & Learn")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.authPrimaryText)
                .padding(.top, 34)

            Text("To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly.")
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
                    subtitle: "Talk live with\nteachers to solve\nmath problems\ntogether in real-\ntime.",
                    isOn: $viewModel.microphoneEnabled
                )

                PermissionCard(
                    icon: "bell.fill",
					iconColor: theme.authPurple,
					iconBackground: theme.authPurpleSoft,
                    title: "Notifications",
                    subtitle: "Get instant alerts\nwhen a teacher\naccepts your\nrequest or replies.",
                    isOn: $viewModel.notificationsEnabled
                )
            }
            .padding(.top, 34)

            Spacer()

            AuthPrimaryButton(title: "Continue Setup", systemImage: "arrow.right") {
                viewModel.continueSetup()
            }

            Button {
                viewModel.limitedMode()
            } label: {
                Text("Not now, use limited mode")
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
