//
//  BlockedTeachersViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the blocked teachers in Settings → Privacy Controls.
//

import Foundation

extension BlockedTeachersViewModel {
  var sectionTitle: String { LocalizationSupport.localized("Blocked teachers") }
  var emptyText: String {
    LocalizationSupport.localized("You have not blocked anyone. To block a teacher, use the flag in a lesson or open the lesson in Activity.")
  }
  var footerText: String {
    LocalizationSupport.localized("A blocked teacher is never sent your questions again.")
  }
  var unblockLabel: String { LocalizationSupport.localized("Unblock") }
  var loadFailedMessage: String {
    LocalizationSupport.localized("Could not load your blocked teachers. Check your connection and try again.")
  }
  var unblockFailedMessage: String {
    LocalizationSupport.localized("Could not unblock. Check your connection and try again.")
  }
  func displayName(for teacher: BlockedTeacher) -> String {
    let name = teacher.teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? LocalizationSupport.localized("Teacher") : name
  }
}
