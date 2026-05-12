//
//  PermissionsSetupView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct PermissionsSetupView: View {
    @State var viewModel = PermissionsSetupViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 72)

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.authPinkSoft)
                    .frame(width: 78, height: 78)
                    .overlay {
                        PlatformIcon(systemName: "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.authPink)
                    }
                    .shadow(color: Color.authPink.opacity(0.1), radius: 24, x: 0, y: 12)

                Circle()
                    .fill(Color.authPurpleSoft)
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(systemName: "bell.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.authPurple)
                    }
                    .offset(x: 12, y: 8)
            }

            Text("Connect & Learn")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.authPrimaryText)
                .padding(.top, 34)

            Text("To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly.")
                .font(.system(size: 14))
                .foregroundStyle(Color.authSecondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            VStack(spacing: 16) {
                PermissionCard(
                    icon: "mic.fill",
                    iconColor: .authPink,
                    iconBackground: .authPinkSoft,
                    title: "Microphone",
                    subtitle: "Talk live with\nteachers to solve\nmath problems\ntogether in real-\ntime.",
                    isOn: $viewModel.microphoneEnabled
                )

                PermissionCard(
                    icon: "bell.fill",
                    iconColor: .authPurple,
                    iconBackground: .authPurpleSoft,
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
                    .foregroundStyle(Color.authSecondaryText)
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
                    .foregroundStyle(Color.authPrimaryText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(4)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.authGreen)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.authPink.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.03), radius: 18, x: 0, y: 10)
    }
}
