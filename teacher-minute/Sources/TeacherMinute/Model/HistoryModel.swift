//
//  HistoryModel.swift
//  teacher-minute
//
//  Created by Codex on 14/05/2026.
//

import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

struct HistoryLesson: Identifiable, Hashable {
    let id: String
    let questionId: String
    let title: String
    let otherParticipantName: String
    let acceptedAt: Date
    let durationSeconds: Int
    let costCents: Int
    let teacherEarningsCents: Int
}

@MainActor
final class HistoryModel {
    static let shared = HistoryModel()

    private init() {}

    func fetchRecentLessons(for uid: String, limit: Int = 3) async throws -> [HistoryLesson] {
        let userSnapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let userData = userSnapshot.data() else { return [] }

        let questionIds = Self.stringArray(userData["questions"])
        guard !questionIds.isEmpty else { return [] }
        let defaultCommission = await SettingsRemoteConfigService.shared.fetchDefaultCommission()
        let commission = Self.doubleValue(userData["commission"])
        let teacherMultiplier = max(0, 1.0 - (commission ?? defaultCommission))

        var lessons: [HistoryLesson] = []
        for questionId in questionIds {
            guard let lesson = try await fetchLesson(
                questionId: questionId,
                currentUserId: uid,
                teacherMultiplier: teacherMultiplier
            ) else { continue }
            lessons.append(lesson)
        }

        return Array(
            lessons
                .sorted { $0.acceptedAt > $1.acceptedAt }
                .prefix(limit)
        )
    }

    private func fetchLesson(
        questionId: String,
        currentUserId: String,
        teacherMultiplier: Double
    ) async throws -> HistoryLesson? {
        let snapshot = try await Firestore.firestore().collection("questions").document(questionId).getDocument()
        guard let data = snapshot.data() else { return nil }

        let studentId = Self.firstString(in: data, keys: ["studentId", "studentUid", "studentUID"])
        let teacherId = Self.firstString(in: data, keys: ["teacherId", "teacherUid", "teacherUID"])
        let otherParticipantId = currentUserId == studentId ? teacherId : studentId
        let otherParticipant = try await profileSummary(uid: otherParticipantId)
        let fallbackName = currentUserId == studentId ? "Teacher" : "Student"
        let acceptedAt = Self.dateValue(data["acceptedAt"])
            ?? Self.dateValue(data["connectedAt"])
            ?? Self.dateValue(data["startedAt"])
            ?? Self.dateValue(data["createdAt"])
            ?? Date.distantPast
        let createdAt = Self.dateValue(data["createdAt"]) ?? acceptedAt
        let endedAt = Self.dateValue(data["endedAt"])
            ?? Self.dateValue(data["completedAt"])
            ?? Self.dateValue(data["finishedAt"])
        let durationSeconds = endedAt.map { max(0, Int($0.timeIntervalSince(createdAt))) } ?? 0
        let costCents = Self.costCents(from: data)
        let teacherEarningsCents = Int((Double(costCents) * teacherMultiplier).rounded())

        return HistoryLesson(
            id: questionId,
            questionId: questionId,
            title: Self.lessonTitle(from: data),
            otherParticipantName: otherParticipant?.displayName ?? fallbackName,
            acceptedAt: acceptedAt,
            durationSeconds: durationSeconds,
            costCents: costCents,
            teacherEarningsCents: teacherEarningsCents
        )
    }

    private func profileSummary(uid: String) async throws -> UserProfileSummary? {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let snapshot = try await Firestore.firestore().collection("users").document(trimmed).getDocument()
        guard let data = snapshot.data() else { return nil }
        return UserProfileSummary(uid: trimmed, data: data)
    }

    private static func lessonTitle(from data: [String: Any]) -> String {
        let title = firstString(in: data, keys: ["topic", "subject", "title", "questionText", "text", "message"])
        return title.isEmpty ? "Lesson" : title
    }

    private static func firstString(in data: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = data[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Timestamp { return value.dateValue() }
        if let value = value as? String { return ISO8601DateFormatter().date(from: value) }
        if let value = value as? Double { return normalizedDate(millisecondsOrSeconds: value) }
        if let value = value as? NSNumber { return normalizedDate(millisecondsOrSeconds: value.doubleValue) }
        return nil
    }

    private static func normalizedDate(millisecondsOrSeconds value: Double) -> Date? {
        guard value > 0 else { return nil }
        let seconds = value < 10_000_000_000 ? value : value / 1000.0
        return Date(timeIntervalSince1970: seconds)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func costCents(from data: [String: Any]) -> Int {
        if let cents = intValue(data["costCents"])
            ?? intValue(data["totalCostCents"])
            ?? intValue(data["priceCents"])
            ?? intValue(data["costPerQuestionCents"]) {
            return cents
        }

        if let amount = doubleValue(data["cost"])
            ?? doubleValue(data["totalCost"])
            ?? doubleValue(data["price"])
            ?? doubleValue(data["costPerQuestion"]) {
            return Int((amount * 100.0).rounded())
        }

        return 0
    }
}
