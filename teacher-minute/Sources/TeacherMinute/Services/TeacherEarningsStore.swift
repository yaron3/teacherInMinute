//
//  TeacherEarningsStore.swift
//  teacher-minute
//
//  One place the teacher's earnings come from.
//
//  The dashboard, the Lessons tab and the Earnings tab all show money the
//  teacher made, and they used to work it out separately: the first two walked
//  the `questions` array on the teacher's user document and added up what they
//  found, while the third called `teacherEarningsSummary`, which queries the
//  `questions` collection by `teacherUid`. Those two sets are written by
//  different code paths and drift — one teacher had five paid lessons that
//  reached the collection but never the array, so the Lessons tab showed ₪0.00
//  against the Earnings tab's ₪57.00. Everything now reads the backend
//  summary, which returns both the totals and the lessons they were computed
//  from, so the screens cannot disagree.
//

import Foundation

@MainActor
final class TeacherEarningsStore {
  static let shared = TeacherEarningsStore()
  private init() {}

  private var cached: TeacherEarningsSummaryResult?
  private var cachedAt: Date?
  private var inFlight: Task<TeacherEarningsSummaryResult, Error>?

  /// How long a fetched summary is reused. The call scans every one of the
  /// teacher's questions, so opening all three screens in one sitting should
  /// cost one call — but a lesson that just ended has to show up promptly,
  /// hence seconds rather than minutes. `invalidate()` covers the cases where
  /// we know something changed.
  private static let freshness: TimeInterval = 30

  func summary(forceRefresh: Bool = false) async throws -> TeacherEarningsSummaryResult {
    if !forceRefresh,
       let cached,
       let cachedAt,
       Date().timeIntervalSince(cachedAt) < Self.freshness {
      return cached
    }
    // Screens load in parallel at launch; without this they would each start
    // their own scan of the same documents.
    if !forceRefresh, let inFlight {
      return try await inFlight.value
    }

    let task = Task { try await FunctionsService.shared.teacherEarningsSummary() }
    inFlight = task
    defer { inFlight = nil }

    let result = try await task.value
    cached = result
    cachedAt = Date()
    return result
  }

  /// Drops the cache so the next read goes back to the backend — call after
  /// something that changes the figures, such as a lesson ending.
  func invalidate() {
    cached = nil
    cachedAt = nil
  }
}
