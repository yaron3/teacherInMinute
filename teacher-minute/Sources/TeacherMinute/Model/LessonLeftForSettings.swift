//
//  LessonLeftForSettings.swift
//  teacher-minute
//
//  A lesson the teacher left for Settings before it started, kept so the app
//  can take them back into it after iOS closes it there.
//

import Foundation

/// A lesson the teacher left for Settings, to turn on a permission, while it
/// was still connecting.
///
/// iOS closes an app when one of its privacy permissions is changed in
/// Settings, so turning the microphone on there ends the app, and the lesson
/// with it, while the student waits on the connecting screen, told the teacher
/// will join shortly. So the dashboard writes the lesson down on the way to
/// Settings, and the next launch takes the teacher straight back into it.
struct LessonLeftForSettings: Codable, Equatable {
  let questionId: String
  let teacherUid: String
  let conversationType: String
  let studentUid: String
  let studentName: String
  let studentImageURL: String
  let questionText: String
  let questionPhotoUrls: [String]
  let pricePerMinuteCents: Int
  let currencyCode: String
  /// When the teacher accepted, in epoch milliseconds.
  let acceptedAt: Double
  /// When the teacher left for Settings, in epoch seconds.
  let leftAt: Double
}

/// Keeps the one `LessonLeftForSettings` a teacher can have, across launches.
enum LessonLeftForSettingsStore {
  /// How long a lesson left for Settings is worth going back to. The server
  /// ends a lesson that has not started five minutes after the accept, so one
  /// written down longer ago than this can only be over.
  static let maxAgeSeconds: Double = 10 * 60

  private static let keyPrefix = "teacherLessonLeftForSettings"

  static func save(_ lesson: LessonLeftForSettings) {
    guard let data = try? JSONEncoder().encode(lesson),
          let json = String(data: data, encoding: .utf8) else { return }
    UserDefaults.standard.set(json, forKey: key(lesson.teacherUid))
  }

  /// The lesson this teacher left for Settings, while it is recent enough to
  /// go back to. One that is too old, or unreadable, is dropped here.
  static func lesson(teacherUid: String, now: Date = Date()) -> LessonLeftForSettings? {
    guard let json = UserDefaults.standard.string(forKey: key(teacherUid)) else { return nil }
    guard let data = json.data(using: .utf8),
          let lesson = try? JSONDecoder().decode(LessonLeftForSettings.self, from: data),
          now.timeIntervalSince1970 - lesson.leftAt < maxAgeSeconds else {
      clear(teacherUid: teacherUid)
      return nil
    }
    return lesson
  }

  static func clear(teacherUid: String) {
    UserDefaults.standard.removeObject(forKey: key(teacherUid))
  }

  private static func key(_ teacherUid: String) -> String {
    "\(keyPrefix).\(teacherUid)"
  }
}
