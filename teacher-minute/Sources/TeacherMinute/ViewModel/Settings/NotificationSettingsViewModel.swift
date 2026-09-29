//
//  NotificationSettingsViewModel.swift
//  teacher-minute
//
//  The notification permission behind the switch on Instant Teacher's
//  notification settings.
//

import Foundation
import Observation
import SkipFuse

@Observable
@MainActor
final class NotificationSettingsViewModel {
  var state: PermissionState = .notDetermined

  /// Reads the permission, and asks for it when it has never been asked, as
  /// the standard notification settings do on opening.
  func load() async {
    state = await PermissionService.shared.notificationStatus()
    if state == .notDetermined {
      state = await PermissionService.shared.requestNotifications()
    }
  }

  /// Re-reads the permission, which the student may have changed in Settings
  /// while the app was in the background.
  func refresh() async {
    state = await PermissionService.shared.notificationStatus()
  }

  /// The switch was tapped. Never asked, it asks; otherwise it opens Settings,
  /// the only place the permission can be turned on or off once answered.
  func toggleTapped() async {
    if state == .notDetermined {
      state = await PermissionService.shared.requestNotifications()
    } else {
      PermissionService.shared.openAppSettings()
    }
  }
}
