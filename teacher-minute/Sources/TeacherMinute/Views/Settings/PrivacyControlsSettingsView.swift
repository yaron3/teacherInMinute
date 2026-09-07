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

    var body: some View {
        Form {
            Section(
                header: Text(viewModel.privacySectionTitle),
                footer: Text(viewModel.privacyFooterText)
            ) {
                Toggle(viewModel.showProfileImageLabel, isOn: $showProfileImage)
                Toggle(viewModel.allowMessagesOutsideCallsLabel, isOn: $allowTeacherMessagesOutsideCalls)
            }
        }
        .task { await loadShowProfileImage() }
        .onChange(of: showProfileImage) { _, newValue in
            Task { await persistShowProfileImage(newValue) }
        }
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
