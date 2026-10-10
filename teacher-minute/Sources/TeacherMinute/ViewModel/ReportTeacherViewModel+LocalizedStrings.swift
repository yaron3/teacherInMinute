//
//  ReportTeacherViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for reporting and blocking a teacher.
//

import Foundation

extension ReportTeacherViewModel {
  var title: String {
    String(format: LocalizationSupport.localized("Report or block %@"), displayedTeacherName)
  }
  var closeLabel: String { LocalizationSupport.localized("Close") }
  var reasonTitle: String { LocalizationSupport.localized("What happened?") }
  var detailsPlaceholder: String { LocalizationSupport.localized("Tell us more (optional)") }
  var alsoBlockLabel: String {
    String(format: LocalizationSupport.localized("Also block %@"), displayedTeacherName)
  }
  var blockExplanation: String {
    LocalizationSupport.localized("A blocked teacher is never sent your questions again.")
  }
  var sendReportLabel: String { LocalizationSupport.localized("Send report") }
  var reviewPromise: String {
    LocalizationSupport.localized("Our team reviews every report within 24 hours and acts on it, up to removing the teacher from the app.")
  }
  var blockOnlyLabel: String {
    String(format: LocalizationSupport.localized("Block %@ without reporting"), displayedTeacherName)
  }
  var blockConfirmTitle: String {
    String(format: LocalizationSupport.localized("Block %@?"), displayedTeacherName)
  }
  var blockConfirmMessage: String { blockExplanation }
  var blockLabel: String { LocalizationSupport.localized("Block") }
  var cancelLabel: String { LocalizationSupport.localized("Cancel") }
  var sendFailedMessage: String {
    LocalizationSupport.localized("Could not send. Check your connection and try again.")
  }

  var doneTitle: String { LocalizationSupport.localized("Thank you") }
  func doneMessage(blocked: Bool) -> String {
    blocked
      ? String(format: LocalizationSupport.localized("%@ is blocked and will not be sent your questions again. You can unblock them in Settings → Privacy Controls."), displayedTeacherName)
      : LocalizationSupport.localized("We received your report and will review it within 24 hours.")
  }
  var doneLabel: String { LocalizationSupport.localized("Done") }

  func label(for reason: TeacherReportReason) -> String {
    switch reason {
    case .inappropriate: LocalizationSupport.localized("Inappropriate or offensive behavior")
    case .harassment: LocalizationSupport.localized("Harassment or bullying")
    case .sexual: LocalizationSupport.localized("Sexual content")
    case .offPlatform: LocalizationSupport.localized("Asked to pay or talk outside the app")
    case .notTeaching: LocalizationSupport.localized("Did not teach or wasted my time")
    case .other: LocalizationSupport.localized("Something else")
    }
  }

  private var displayedTeacherName: String {
    let trimmed = teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? LocalizationSupport.localized("this teacher") : trimmed
  }
}
