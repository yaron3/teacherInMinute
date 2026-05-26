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
    let otherParticipantImageURL: String
    let acceptedAt: Date
    let durationSeconds: Int
    let costCents: Int
    let teacherEarningsCents: Int
    let currencyCode: String
}

struct LessonMessage: Identifiable {
	let id: String
    let text: String
	let senderRole: String
    let kind: String
    let senderUid: String
    let createdAt: Date
}

@MainActor
final class HistoryModel {
    static let shared = HistoryModel()

    private init() {}

    func fetchPurchasedCurrencyCode(for uid: String) async throws -> String {
        let userSnapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let userData = userSnapshot.data() else { return LessonFormatting.defaultCurrencyCode }
        let pricingCurrencyById = await Self.pricingCurrencyById()
        return Self.purchasedPackageCurrencyCode(
            from: userData,
            pricingCurrencyById: pricingCurrencyById
        ) ?? LessonFormatting.defaultCurrencyCode
    }

    func fetchTotalPurchasedMinutes(for uid: String) async throws -> Int {
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("purchases")
            .getDocuments()

        return snapshot.documents.reduce(0) { total, document in
            total + max(0, Self.intValue(document.data()["minutesPurchased"]) ?? 0)
        }
    }

    func fetchRecentLessons(for uid: String, limit: Int = 3) async throws -> [HistoryLesson] {
        let userSnapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let userData = userSnapshot.data() else { return [] }

        let questionIds = Self.stringArray(userData["questions"])
        guard !questionIds.isEmpty else { return [] }
        let defaultTeacherShare = await SettingsRemoteConfigService.shared.fetchTeacherShare()
        let pricingCurrencyById = await Self.pricingCurrencyById()
        let purchasedCurrencyCode = Self.purchasedPackageCurrencyCode(
            from: userData,
            pricingCurrencyById: pricingCurrencyById
        ) ?? LessonFormatting.defaultCurrencyCode

        var lessons: [HistoryLesson] = []
        for questionId in questionIds {
            guard let lesson = try await fetchLesson(
                questionId: questionId,
                currentUserId: uid,
                defaultTeacherShare: defaultTeacherShare,
                pricingCurrencyById: pricingCurrencyById,
                fallbackCurrencyCode: purchasedCurrencyCode
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
        defaultTeacherShare: Double,
        pricingCurrencyById: [String: String],
        fallbackCurrencyCode: String
    ) async throws -> HistoryLesson? {
        let snapshot = try await Firestore.firestore().collection("questions").document(questionId).getDocument()
        guard let data = snapshot.data() else { return nil }

        let studentId = Self.firstString(in: data, keys: ["studentId", "studentUid", "studentUID"])
        let isCurrentUserStudent = currentUserId == studentId
        let otherParticipantName: String = isCurrentUserStudent
            ? Self.firstString(in: data, keys: ["teacherName"])
            : Self.firstString(in: data, keys: ["studentName"])
        let otherParticipantImage: String = isCurrentUserStudent
            ? Self.firstString(in: data, keys: ["teacherImageURL", "teacherProfileImageURL"])
            : Self.firstString(in: data, keys: ["studentImageURL", "studentProfileImageURL"])
        let fallbackName = isCurrentUserStudent ? "Teacher" : "Student"
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
        let teacherEarningsCents = Self.teacherEarningsCents(
            from: data,
            costCents: costCents,
            defaultTeacherShare: defaultTeacherShare
        )
        let currencyCode = Self.currencyCode(
            from: data,
            pricingCurrencyById: pricingCurrencyById,
            fallbackCurrencyCode: fallbackCurrencyCode
        )

        return HistoryLesson(
            id: questionId,
            questionId: questionId,
            title: Self.lessonTitle(from: data),
            otherParticipantName: otherParticipantName.isEmpty ? fallbackName : otherParticipantName,
            otherParticipantImageURL: otherParticipantImage,
            acceptedAt: acceptedAt,
            durationSeconds: durationSeconds,
            costCents: costCents,
            teacherEarningsCents: teacherEarningsCents,
            currencyCode: currencyCode
        )
    }

    private static func lessonTitle(from data: [String: Any]) -> String {
        let title = LocalizationSupport.localized(firstString(in: data, keys: ["topic", "subject", "title", "questionText", "text", "message"]))
												  
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

    private static func pricingCurrencyById() async -> [String: String] {
        do {
            return try await PricingService.shared.fetchPricingOptions().reduce(into: [:]) { result, option in
                result[option.id] = option.currency
                if let purchaseSKU = option.purchaseSKU, !purchaseSKU.isEmpty {
                    result[purchaseSKU] = option.currency
                }
            }
        } catch {
            logger.error("[HistoryModel] failed loading pricing currencies: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "HistoryModel.pricingCurrencyById")
            return [:]
        }
    }

    private static func purchasedPackageCurrencyCode(
        from userData: [String: Any],
        pricingCurrencyById: [String: String]
    ) -> String? {
        if let explicit = explicitCurrencyCode(from: userData) {
            return explicit
        }

        let purchases = purchaseRows(from: userData["purchases"])
            + purchaseRows(from: userData["purchaseHistory"])
            + purchaseRows(from: userData["packages"])
        for purchase in purchases.reversed() {
            if let explicit = explicitCurrencyCode(from: purchase) {
                return explicit
            }
            if let packageId = packageId(from: purchase), let currency = pricingCurrencyById[packageId] {
                return currency
            }
        }

        if let packageId = packageId(from: userData), let currency = pricingCurrencyById[packageId] {
            return currency
        }
        return nil
    }

    private static func currencyCode(
        from data: [String: Any],
        pricingCurrencyById: [String: String],
        fallbackCurrencyCode: String
    ) -> String {
        if let explicit = explicitCurrencyCode(from: data) {
            return explicit
        }
        if let packageId = packageId(from: data), let currency = pricingCurrencyById[packageId] {
            return currency
        }
        return fallbackCurrencyCode
    }

    private static func explicitCurrencyCode(from data: [String: Any]) -> String? {
        let currency = firstString(in: data, keys: [
            "currencyCode",
            "currency",
            "packageCurrency",
            "pricingCurrency",
            "purchaseCurrency"
        ])
        return currency.isEmpty ? nil : currency
    }

    private static func packageId(from data: [String: Any]) -> String? {
        let id = firstString(in: data, keys: [
            "pricingOptionId",
            "pricingOptionID",
            "pricingOption",
            "packageId",
            "packageID",
            "package",
            "purchasePackageId",
            "purchasePackageID",
            "purchaseSKU"
        ])
        if !id.isEmpty { return id }

        for key in ["pricing", "package", "purchase"] {
            if let nested = data[key] as? [String: Any], let nestedId = packageId(from: nested) {
                return nestedId
            }
        }
        return nil
    }

    private static func purchaseRows(from value: Any?) -> [[String: Any]] {
        if let rows = value as? [[String: Any]] {
            return rows
        }
        if let rows = value as? [Any] {
            return rows.compactMap { row in
                if let dict = row as? [String: Any] { return dict }
                if let id = row as? String { return ["packageId": id] }
                return nil
            }
        }
        if let rows = value as? [String: Any] {
            return rows.compactMap { key, value in
                if var dict = value as? [String: Any] {
                    if packageId(from: dict) == nil {
                        dict["packageId"] = key
                    }
                    return dict
                }
                if let id = value as? String { return ["packageId": id] }
                if let quantity = intValue(value), quantity > 0 { return ["packageId": key, "quantity": quantity] }
                return nil
            }
        }
        if let id = value as? String {
            return [["packageId": id]]
        }
        return []
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

    /// Reads the authoritative `teacherEarnings` written by the backend, falling
    /// back to `costCents * teacherShare` only when the backend value is absent
    /// (legacy lessons predating the unified billing pipeline).
    private static func teacherEarningsCents(
        from data: [String: Any],
        costCents: Int,
        defaultTeacherShare: Double
    ) -> Int {
        if let cents = intValue(data["teacherEarningsCents"]) {
            return cents
        }
        if let amount = doubleValue(data["teacherEarnings"]) {
            return Int((amount * 100.0).rounded())
        }
        let share = doubleValue(data["teacherShare"])
            ?? doubleValue(data["teacherSharePercent"]).map { $0 / 100.0 }
            ?? defaultTeacherShare
        let multiplier = max(0, min(1, share))
        return Int((Double(costCents) * multiplier).rounded())
    }

    func fetchQuestionText(questionId: String) async throws -> String {
        let snapshot = try await Firestore.firestore()
            .collection("questions").document(questionId).getDocument()
        guard let data = snapshot.data() else { return "" }
        return Self.firstString(in: data, keys: ["text", "questionText", "originalQuestion", "message"])
    }

    func fetchLessonMessages(questionId: String) async throws -> [LessonMessage] {
        let snapshot = try await Firestore.firestore()
            .collection("questions")
            .document(questionId)
            .getDocument()
        guard let data = snapshot.data() else { return [] }

        return Self.lessonMessages(from: data["messages"])
            .sorted { $0.createdAt < $1.createdAt }
    }

    private static func lessonMessages(from value: Any?) -> [LessonMessage] {
        if let messages = value as? [[String: Any]] {
            return messages.enumerated().compactMap { index, data in
                lessonMessage(id: String(index), data: data)
            }
        }

        if let messages = value as? [Any] {
            return messages.enumerated().compactMap { index, value in
                guard let data = value as? [String: Any] else { return nil }
                return lessonMessage(id: String(index), data: data)
            }
        }

        if let messages = value as? [String: Any] {
            return messages.compactMap { id, value in
                guard let data = value as? [String: Any] else { return nil }
                return lessonMessage(id: id, data: data)
            }
        }

        return []
    }

    private static func lessonMessage(id fallbackId: String, data: [String: Any]) -> LessonMessage? {
        let text = firstString(in: data, keys: ["text", "message", "imageUrl", "photoUrl", "url"])
        guard !text.isEmpty else { return nil }

        let messageId = firstString(in: data, keys: ["id", "messageId"])
        let senderRole = firstString(in: data, keys: ["senderRole", "role"])
        let kind = firstString(in: data, keys: ["kind", "type"])

        return LessonMessage(
            id: messageId.isEmpty ? fallbackId : messageId,
            text: text,
            senderRole: senderRole.isEmpty ? "student" : senderRole,
            kind: kind.isEmpty ? "text" : kind,
            senderUid: firstString(in: data, keys: ["senderUid", "senderId", "uid"]),
            createdAt: dateValue(data["createdAt"]) ?? Date.distantPast
        )
    }
}
