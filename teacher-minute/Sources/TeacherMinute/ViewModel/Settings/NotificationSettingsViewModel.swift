//
//  NotificationSettingsViewModel.swift
//  teacher-minute
//
//  The notification settings: the system's permission behind the first
//  switch, and the user's own choices of which notifications they want.
//

import Foundation
import Observation
import SkipFuse

@Observable
@MainActor
final class NotificationSettingsViewModel {
  var state: PermissionState = .notDetermined

  /// Lesson notifications: a teacher's question invites, a student's "teacher
  /// found" and "no teacher available".
  var notifyIncomingMessages = NotificationPreferences.current.incomingMessages
  /// Announcements sent from the admin console.
  var notifyGeneralAnnouncements = NotificationPreferences.current.announcements

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

  /// IT-28: the choice is the backend's to honour, since it sends the pushes
  /// that arrive while the app is closed. Kept on the device, and written next
  /// to the push token, where the backend reads it before each send.
  func toggleIncomingMessages() {
    notifyIncomingMessages.toggle()
    save()
  }

  func toggleGeneralAnnouncements() {
    notifyGeneralAnnouncements.toggle()
    save()
  }

  private func save() {
    let preferences = NotificationPreferences(
      incomingMessages: notifyIncomingMessages,
      announcements: notifyGeneralAnnouncements
    )
    preferences.store()
    AnalyticsService.shared.logEvent(AnalyticsEvent.notificationPreferencesChanged, parameters: [
      "incoming_messages": notifyIncomingMessages ? "on" : "off",
      "announcements": notifyGeneralAnnouncements ? "on" : "off",
    ])
    PushNotificationService.shared.writeNotificationPreferences(preferences)
  }
}
