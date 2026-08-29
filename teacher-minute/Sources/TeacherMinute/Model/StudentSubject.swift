//
//  StudentSubject.swift
//  teacher-minute
//
// A subject on the student home "Available Subjects" grid.
//
// The list itself comes from the Remote Config subject catalog (`subjects` and
// `subTask<Subject>`) — the same catalog teachers choose from, so a subject can
// never be offered to students that no teacher is able to pick. The teacher
// count is the number of teachers online for it right now, read from RTDB
// presence; it is not a marketing figure.
//

import Foundation

struct StudentSubject: Identifiable {
  /// Snake-case key, e.g. "computer_science". Used for the `enable_<key>`
  /// Remote Config visibility flag and for the grid's per-subject tint.
  let key: String
  /// Localized area name for display.
  let title: String
  /// Its subtopics, localized and comma-joined. Empty when the catalog lists
  /// none, in which case the grid leaves the line out.
  let topics: String
  let systemImage: String
  /// Teachers online right now who teach this subject.
  let teacherCount: Int

  var id: String { key }

  var hasTeachersOnline: Bool { teacherCount > 0 }
}

/// Shared naming and iconography for subjects, so the teacher's subject picker
/// and the student's subject grid derive the same key and icon from the same
/// catalog entry.
enum SubjectPresentation {
  /// Snake-case flag/tint key: "Computer_Science" and "Computer Science" both
  /// become "computer_science".
  static func flagKey(for title: String) -> String {
    var key = ""
    var lastWasSeparator = true   // leading separators are dropped
    for character in title.lowercased() {
      if character.isLetter || character.isNumber {
        key.append(character)
        lastWasSeparator = false
      } else if !lastWasSeparator {
        key.append("_")
        lastWasSeparator = true
      }
    }
    if key.hasSuffix("_") { key.removeLast() }
    return key
  }

  /// Letters and digits only — the form teacher presence uses for its RTDB
  /// subject entries, so the two can be compared.
  static func matchKey(for title: String) -> String {
    title.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  /// Remote Config writes multi-word subjects with underscores
  /// ("Computer_Science"); show them as words.
  static func displayTitle(for title: String) -> String {
    title.replacingOccurrences(of: "_", with: " ")
  }

  static func systemImage(for title: String) -> String {
    let lowercased = title.lowercased()
    if lowercased.contains("math") { return "function" }
    if lowercased.contains("physics") { return "atom" }
    if lowercased.contains("chem") { return "testtube.2" }
    if lowercased.contains("bio") { return "leaf.fill" }
    if lowercased.contains("computer") || lowercased.contains("program") { return "laptopcomputer" }
    if lowercased.contains("algebra") { return "x.squareroot" }
    if lowercased.contains("geometry") { return "triangle" }
    if lowercased.contains("trigon") { return "angle" }
    if lowercased.contains("calculus") { return "chart.xyaxis.line" }
    if lowercased.contains("stat") { return "chart.pie" }
    return "book.closed.fill"
  }
}
