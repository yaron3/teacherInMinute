//
//  BlockedTeachersViewModel.swift
//  teacher-minute
//
//  The teachers a student has blocked, listed in Settings → Privacy Controls
//  so a block can be undone. Blocking itself happens from a lesson; see
//  ReportTeacherViewModel.
//

import Foundation
import Observation

@Observable
@MainActor
final class BlockedTeachersViewModel {
  private(set) var teachers: [BlockedTeacher] = []
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  private(set) var loadFailed = false
  /// The teacher being unblocked, whose row shows a spinner meanwhile.
  private(set) var unblockingUid: String?
  var errorMessage: String?

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    do {
      teachers = try await FunctionsService.shared.listBlockedTeachers()
      loadFailed = false
    } catch {
      AnalyticsService.shared.recordError(error, context: "listBlockedTeachers")
      loadFailed = true
      errorMessage = loadFailedMessage
    }
  }

  /// "Nobody blocked" only when the list was actually read and is empty.
  var showsEmptyState: Bool { hasLoaded && !loadFailed && teachers.isEmpty }

  func unblock(_ teacher: BlockedTeacher) async {
    guard unblockingUid == nil else { return }
    unblockingUid = teacher.teacherUid
    defer { unblockingUid = nil }
    do {
      try await FunctionsService.shared.unblockTeacher(teacherUid: teacher.teacherUid)
      teachers.removeAll { $0.teacherUid == teacher.teacherUid }
      AnalyticsService.shared.logEvent(AnalyticsEvent.teacherUnblocked)
    } catch {
      AnalyticsService.shared.recordError(error, context: "unblockTeacher")
      errorMessage = unblockFailedMessage
    }
  }
}
