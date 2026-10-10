//
//  PrivacyControlsSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct PrivacyControlsSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage("showProfileImage") var showProfileImage = true
    @AppStorage("allowTeacherMessagesOutsideCalls") var allowTeacherMessagesOutsideCalls = true

    private let authService = AuthService()

    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        // A plain stack around the page, which carries its modifiers; see
        // `BrandTabScreen`.
        ZStack {
            page
        }
        .task { await loadShowProfileImage() }
        .onChange(of: showProfileImage) { _, newValue in
            Task { await persistShowProfileImage(newValue) }
        }
    }

    /// The switches at the start of their rows, as on the notification
    /// settings.
    var page: some View {
        BrandSubpage(
            label: viewModel.settingsTitle,
            title: viewModel.settingsPageTitle(SettingsDestination.privacyControls.title),
            backLabel: viewModel.backLabel
        ) {
            BrandPageHero(title: SettingsDestination.privacyControls.title)
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.privacySectionTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.brandSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                brandToggleRow(viewModel.showProfileImageLabel, isOn: showProfileImage, identifier: "show_profile_image") {
                    showProfileImage.toggle()
                }
                brandToggleRow(
                    viewModel.allowMessagesOutsideCallsLabel,
                    isOn: allowTeacherMessagesOutsideCalls,
                    identifier: "messages_outside_calls"
                ) {
                    allowTeacherMessagesOutsideCalls.toggle()
                }
                Text(viewModel.privacyFooterText)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.brandSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .brandCard()

            // Only students block: a teacher is sent questions, not people.
            if viewModel.role == .student {
                BlockedTeachersSection()
            }
        }
    }

    func brandToggleRow(_ title: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            BrandToggle(isOn: isOn, action: action)
                .accessibilityIdentifier("privacy_toggle_\(identifier)")
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(theme.onDarkFill)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    // The "Show my profile image" preference must live on the user's profile so
    // the backend can decide whether to share the photo with the other
    // participant — a device-local @AppStorage value is invisible to it.
    private func loadShowProfileImage() async {
        guard let uid = authService.currentUserID,
              let data = try? await UserService.shared.fetchRaw(uid: uid),
              let stored = data["showProfileImage"] as? Bool else { return }
        showProfileImage = stored
    }

    private func persistShowProfileImage(_ newValue: Bool) async {
        guard let uid = authService.currentUserID else { return }
        try? await UserService.shared.updateShowProfileImage(uid: uid, enabled: newValue)
    }
}
