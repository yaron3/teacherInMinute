//
//  OnlineTeacher.swift
//  teacher-minute
//

import Foundation

/// A teacher currently online, ready to be shown in the student home "Teachers
/// online now" grid. Built straight from `OnlineTeacherPresence` — the backend
/// projection already carries the name and photo, so drawing the grid needs no
/// per-teacher profile read.
struct OnlineTeacher: Identifiable {
  let id: String
  let name: String
  let subject: String
  let profileImageURL: String

  var initial: String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
  }
}

/// One entry of the public `onlineTeachers/{uid}` projection the backend
/// maintains (functions/src/presence.ts). Only teachers who are online appear,
/// and only fields that are safe for any signed-in user to see — the private
/// `teachers/{uid}` node stays owner-only because it holds student names.
struct OnlineTeacherPresence: Identifiable {
  let id: String
  let subjects: [String]
  let displayName: String
  let photoUrl: String
}
