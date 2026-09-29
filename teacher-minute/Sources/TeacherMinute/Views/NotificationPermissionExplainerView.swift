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
    let viewModel: any StudentHomeViewModeling
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
                .fill(theme.accentBackground)
                .frame(width: 78, height: 78)
                .overlay {
                    PlatformIcon(systemName: "bell.badge.fill", size: 34, weight: .semibold, color: theme.brandActionBackground)
                }

            Text(viewModel.notificationExplainerTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.onDarkFill)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            Text(viewModel.notificationExplainerText)
                .font(.system(size: 15))
                .foregroundStyle(theme.brandSecondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 12)

            Spacer()

            AuthPrimaryButton(
                title: viewModel.enableNotificationsButtonLabel(isRequesting: isRequesting),
                isEnabled: !isRequesting
            ) {
                Task { await enable() }
            }

            Button {
                onFinish()
            } label: {
                Text(viewModel.notNowLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.brandActionBackground)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isRequesting)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .screenGround()
        .environment(\.colorScheme, .dark)
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
