//
//  TeacherReport.swift
//  teacher-minute
//
//  What a student can report a teacher for, and a teacher they have blocked.
//  The raw values are the backend's (REPORT_REASONS in
//  backend/Firebase/functions/src/moderation.ts); the copy for each is the
//  report screen's view model's.
//

import Foundation

enum TeacherReportReason: String, CaseIterable, Hashable {
  case inappropriate
  case harassment
  case sexual
  case offPlatform = "off_platform"
  case notTeaching = "not_teaching"
  case other
}

struct BlockedTeacher: Identifiable, Hashable {
  let teacherUid: String
  let teacherName: String
  let blockedAt: Date

  var id: String { teacherUid }
}
