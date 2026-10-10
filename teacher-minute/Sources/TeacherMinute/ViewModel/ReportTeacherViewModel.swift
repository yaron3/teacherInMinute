//
//  ReportTeacherViewModel.swift
//  teacher-minute
//
//  A student reporting or blocking the teacher of one of their lessons — from
//  the lesson itself, the rating that follows it, or the lesson in Activity.
//  A report says what happened and can block the teacher in the same step; a
//  block alone stops the teacher being sent this student's questions again.
//  The backend checks the lesson is the student's and finds the teacher from
//  it (backend/Firebase/functions/src/moderation.ts).
//

import Foundation
import Observation

@Observable
@MainActor
final class ReportTeacherViewModel {
  enum Phase: Equatable {
    case form
    /// Sent. `blocked` says whether the teacher is now blocked.
    case done(blocked: Bool)
  }

  let questionId: String
  let teacherName: String

  var reason: TeacherReportReason?
  var details = ""
  /// On by default: a student who reports a teacher rarely wants them back.
  var alsoBlock = true
  var isConfirmingBlockOnly = false
  private(set) var isSending = false
  private(set) var phase: Phase = .form
  var errorMessage: String?

  /// Called once the student leaves the screen, with whether the teacher is
  /// now blocked — a lesson still running then ends.
  private let onFinish: (_ blocked: Bool) -> Void

  init(questionId: String, teacherName: String, onFinish: @escaping (_ blocked: Bool) -> Void) {
    self.questionId = questionId
    self.teacherName = teacherName
    self.onFinish = onFinish
  }

  var canSendReport: Bool { reason != nil && !isSending }

  func appeared() {
    AnalyticsService.shared.logEvent(AnalyticsEvent.teacherReportOpened)
  }

  func sendReport() async {
    guard let reason, !isSending else { return }
    isSending = true
    errorMessage = nil
    defer { isSending = false }
    do {
      try await FunctionsService.shared.reportTeacher(
        questionId: questionId,
        reason: reason,
        details: details,
        block: alsoBlock
      )
      AnalyticsService.shared.logEvent(
        AnalyticsEvent.teacherReported,
        parameters: ["reason": reason.rawValue, "blocked": alsoBlock]
      )
      phase = .done(blocked: alsoBlock)
    } catch {
      AnalyticsService.shared.recordError(error, context: "reportTeacher")
      errorMessage = sendFailedMessage
    }
  }

  func requestBlockOnly() {
    isConfirmingBlockOnly = true
  }

  func blockOnly() async {
    guard !isSending else { return }
    isSending = true
    errorMessage = nil
    defer { isSending = false }
    do {
      try await FunctionsService.shared.blockTeacher(questionId: questionId)
      AnalyticsService.shared.logEvent(AnalyticsEvent.teacherBlocked)
      phase = .done(blocked: true)
    } catch {
      AnalyticsService.shared.recordError(error, context: "blockTeacher")
      errorMessage = sendFailedMessage
    }
  }

  /// Closing from the form leaves everything as it was.
  func close() {
    switch phase {
    case .form: onFinish(false)
    case .done(let blocked): onFinish(blocked)
    }
  }
}
