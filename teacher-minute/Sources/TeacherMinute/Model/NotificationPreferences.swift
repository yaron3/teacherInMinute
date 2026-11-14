//
//  NotificationPreferences.swift
//  teacher-minute
//
//  Which notifications the user chose in Settings → Notifications. Kept on the
//  device, and written by PushNotificationService to
//  `users/{uid}/notificationPreferences` (and a teacher's
//  `teachers/{uid}/notificationPreferences`), where the backend reads them
//  before sending a push (backend/Firebase/functions/src/types.ts).
//

import Foundation

struct NotificationPreferences: Equatable {
  /// Lesson notifications: a teacher's question invites, a student's "teacher
  /// found" and "no teacher available".
  var incomingMessages: Bool
  /// Announcements sent from the admin console.
  var announcements: Bool

  /// The keys the settings have always been kept under.
  static let incomingMessagesKey = "notifyIncomingTeacherMessage"
  static let announcementsKey = "notifyGeneralAnnouncements"

  /// What the user chose on this device; on until they turn it off.
  static var current: NotificationPreferences {
    let defaults = UserDefaults.standard
    return NotificationPreferences(
      incomingMessages: defaults.object(forKey: incomingMessagesKey) as? Bool ?? true,
      announcements: defaults.object(forKey: announcementsKey) as? Bool ?? true
    )
  }

  func store() {
    UserDefaults.standard.set(incomingMessages, forKey: Self.incomingMessagesKey)
    UserDefaults.standard.set(announcements, forKey: Self.announcementsKey)
  }

  /// As written to the database.
  var databaseValue: [String: Any] {
    ["incomingMessages": incomingMessages, "announcements": announcements]
  }
}
