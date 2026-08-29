//
//  PlatformStatsService.swift
//  teacher-minute
//
// Reads the aggregate counters the backend maintains at Firestore
// `stats/platform` (see functions/src/stats.ts). Today that is the measured
// average time it takes a question to reach a teacher — the number the student
// home shows next to the online-teacher count, in place of a fixed claim.
//
// The document is server-written and readable by any signed-in user, so this is
// a single document read rather than a callable.
//

import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

/// Platform-wide, non-identifying numbers shown to students.
struct PlatformStats {
    /// Measured seconds from asking a question to a teacher accepting it.
    let averageConnectSeconds: Int
    /// How many connected questions the average is drawn from. Zero means the
    /// platform has no history yet and the average should not be shown.
    let sampleSize: Int
    /// Users registered as teachers. Zero means the counter has not been
    /// seeded yet, in which case the caption is left out rather than claiming
    /// the platform has no teachers.
    let registeredTeacherCount: Int

    var hasConnectTime: Bool { sampleSize > 0 && averageConnectSeconds > 0 }

    var hasRegisteredTeachers: Bool { registeredTeacherCount > 0 }

    static let unavailable = PlatformStats(
        averageConnectSeconds: 0,
        sampleSize: 0,
        registeredTeacherCount: 0
    )
}

@MainActor
final class PlatformStatsService {
    static let shared = PlatformStatsService()

    private init() {}

    /// Cached for the lifetime of the session: the average moves slowly and the
    /// student home asks for it on every appearance and pull-to-refresh.
    private var cached: PlatformStats?

    func fetchStats(forceRefresh: Bool = false) async -> PlatformStats {
        if !forceRefresh, let cached {
            return cached
        }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("stats")
                .document("platform")
                .getDocument()

            guard let data = snapshot.data() else {
                logger.info("[PlatformStats] no stats document yet")
                cached = .unavailable
                return .unavailable
            }

            let stats = PlatformStats(
                averageConnectSeconds: Self.intValue(data["averageConnectSeconds"]) ?? 0,
                sampleSize: Self.intValue(data["connectedQuestionCount"]) ?? 0,
                registeredTeacherCount: Self.intValue(data["registeredTeacherCount"]) ?? 0
            )
            cached = stats
            logger.info("[PlatformStats] averageConnectSeconds=\(stats.averageConnectSeconds) sampleSize=\(stats.sampleSize) registeredTeachers=\(stats.registeredTeacherCount)")
            return stats
        } catch {
            logger.error("[PlatformStats] failed loading stats: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "PlatformStats.fetch")
            return cached ?? .unavailable
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
