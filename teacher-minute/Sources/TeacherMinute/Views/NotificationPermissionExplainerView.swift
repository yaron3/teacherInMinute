//
//  NotificationPermissionExplainerView.swift
//  teacher-minute
//
//  A custom, in-app explanation shown after a student's first lesson describing
//  why notifications are useful. The system permission dialog is only presented
//  if the student chooses to enable notifications here.
//

import SwiftUI

struct NotificationPermissionExplainerView: View {
    /// Called after the user makes a choice (enabled or not) so the presenter
    /// can dismiss and record that the explanation was shown.
    let onFinish: () -> Void

    @State var isRequesting = false
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.authPurpleSoft)
                .frame(width: 78, height: 78)
                .overlay {
                    PlatformIcon(systemName: "bell.badge.fill", size: 34, weight: .semibold, color: theme.authPurple)
                }
                .shadow(color: theme.authPurple.opacity(0.12), radius: 24, x: 0, y: 12)

            Text(LocalizationSupport.localized("Stay in the loop"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)
                .padding(.top, 28)

            Text(LocalizationSupport.localized("Turn on notifications so we can let you know the moment a teacher accepts your request, replies to a message, or your session is about to start."))
                .font(.system(size: 14))
                .foregroundStyle(theme.appSecondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 12)

            Spacer()

            AuthPrimaryButton(
                title: isRequesting ? LocalizationSupport.localized("Enabling...") : LocalizationSupport.localized("Enable Notifications"),
                systemImage: "bell.fill",
                isEnabled: !isRequesting
            ) {
                Task { await enable() }
            }

            Button {
                onFinish()
            } label: {
                Text(LocalizationSupport.localized("Not now"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.appSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isRequesting)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
    }

    private func enable() async {
        isRequesting = true
        // Only now, after the user opted in, do we surface the system dialog.
        let state = await PermissionService.shared.requestNotifications()
        if state == .granted {
            // Permission granted — register the device so pushes can be delivered.
            PushNotificationService.shared.registerCurrentDevice(role: .student)
        }
        isRequesting = false
        onFinish()
    }
}
