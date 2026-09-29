//
//  StudentNotificationsView.swift
//  teacher-minute
//
//  Instant Teacher's notification settings, as its design draws them: the
//  system's permission, then the notifications the student chooses. The same
//  settings, in the same storage, as `NotificationPreferencesSettingsView`.
//

import SwiftUI

struct StudentNotificationsView: View {
  let viewModel: any SettingsViewModeling
  @State var permission = NotificationSettingsViewModel()
  @AppStorage("notifyIncomingTeacherMessage") var notifyIncomingTeacherMessage = true
  @AppStorage("notifyGeneralAnnouncements") var notifyGeneralAnnouncements = true
  @Environment(\.scenePhase) var scenePhase

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    BrandSubpage(
      label: viewModel.settingsTitle,
      title: viewModel.notificationsHeaderTitle,
      backLabel: viewModel.backLabel
    ) {
      VStack(alignment: .leading, spacing: 16) {
        BrandPageHero(title: viewModel.notificationsSectionTitle, subtitle: viewModel.notificationsSubtitle)
        card
      }
      // On a plain stack inside the page, not on `BrandSubpage`; see
      // `BrandTabScreen`.
      .task {
        await permission.load()
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await permission.refresh() }
      }
    }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        sectionTitle(viewModel.systemPermissionSectionTitle, size: 16)
        toggleRow(
          viewModel.pushNotificationsLabel,
          size: 17,
          isOn: permission.state.isGranted,
          identifier: "push"
        ) {
          Task { await permission.toggleTapped() }
        }
      }

      BrandRule()

      // Until the system lets notifications through, these choices have
      // nothing to act on, and stay dimmed.
      VStack(alignment: .leading, spacing: 8) {
        sectionTitle(viewModel.notificationsSectionTitle, size: 17)
        toggleRow(
          viewModel.incomingMessageNotificationLabel,
          size: 16,
          isOn: notifyIncomingTeacherMessage,
          isEnabled: permission.state.isGranted,
          identifier: "incoming_message"
        ) {
          notifyIncomingTeacherMessage.toggle()
        }
        toggleRow(
          viewModel.generalAnnouncementsNotificationLabel,
          size: 16,
          isOn: notifyGeneralAnnouncements,
          isEnabled: permission.state.isGranted,
          identifier: "general_announcements"
        ) {
          notifyGeneralAnnouncements.toggle()
        }
      }
    }
    .brandCard()
  }

  /// The switch at the start, then what it turns on, as designed.
  private func toggleRow(
    _ title: String,
    size: CGFloat,
    isOn: Bool,
    isEnabled: Bool = true,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 12) {
      BrandToggle(isOn: isOn, isEnabled: isEnabled, action: action)
        .accessibilityIdentifier("notification_toggle_\(identifier)")
      Text(title)
        .font(.system(size: size))
        .foregroundStyle(theme.onDarkFill)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
  }

  private func sectionTitle(_ title: String, size: CGFloat) -> some View {
    Text(title)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(theme.brandSecondaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if os(iOS)
#Preview {
  NavigationStack {
    StudentNotificationsView(viewModel: MockSettingsViewModel(role: .student))
  }
}
#endif
