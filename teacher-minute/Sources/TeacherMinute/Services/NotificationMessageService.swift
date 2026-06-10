import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

struct NotificationMessage: Identifiable, Hashable {
    enum Source: Hashable {
        case incoming(documentID: String)
        case general(userDocumentID: String, messageID: String)
    }

    let id: String
    let source: Source
    let title: String
    let text: String
    let timestamp: Date
    let readTimestamp: Date?

    var isRead: Bool {
        readTimestamp != nil
    }
}

@MainActor
final class NotificationMessageService {
    static let shared = NotificationMessageService()

    private init() {}

    func fetchMessages(uid: String) async throws -> [NotificationMessage] {
        let incoming = (try? await fetchIncomingMessages(uid: uid)) ?? []
        let general = (try? await fetchGeneralMessages(uid: uid)) ?? []
        return (incoming + general).sorted { $0.timestamp > $1.timestamp }
    }

    func markRead(_ message: NotificationMessage, uid: String) async throws {
        guard !message.isRead else { return }

        let now = FieldValue.serverTimestamp()
        switch message.source {
        case .incoming(let documentID):
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("incomingMessages")
                .document(documentID)
                .setData(["readTimestamp": now], merge: true)

        case .general(let userDocumentID, _):
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("generalMessages")
                .document(userDocumentID)
                .setData(["readTimestamp": now], merge: true)
        }
    }

    func delete(_ message: NotificationMessage, uid: String) async throws {
        switch message.source {
        case .incoming(let documentID):
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("incomingMessages")
                .document(documentID)
                .delete()

        case .general(let userDocumentID, _):
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("generalMessages")
                .document(userDocumentID)
                .delete()
        }
    }

    private func fetchIncomingMessages(uid: String) async throws -> [NotificationMessage] {
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("incomingMessages")
            .getDocuments()

        return snapshot.documents.compactMap { document in
            Self.message(
                id: "incoming-\(document.documentID)",
                source: .incoming(documentID: document.documentID),
                data: document.data(),
                fallbackTimestamp: Self.dateValue(document.documentID)
            )
        }
    }

    private func fetchGeneralMessages(uid: String) async throws -> [NotificationMessage] {
        let userSnapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument()
        let userData = userSnapshot.data() ?? [:]

        var messages: [NotificationMessage] = []
        var seenMessageIDs = Set<String>()

        if let snapshot = try? await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("generalMessages")
            .getDocuments() {
            for document in snapshot.documents {
                let referenceData = document.data()
                let messageID = Self.firstString(in: referenceData, keys: ["messageID", "messageId", "id"])
                    .nilIfEmpty ?? document.documentID
                guard seenMessageIDs.insert(messageID).inserted else { continue }
                if let message = try await fetchGeneralMessage(
                    messageID: messageID,
                    userDocumentID: document.documentID,
                    userData: referenceData
                ) {
                    messages.append(message)
                }
            }
        }

        for messageID in Self.generalMessageIDs(from: userData) where seenMessageIDs.insert(messageID).inserted {
            if let message = try await fetchGeneralMessage(
                messageID: messageID,
                userDocumentID: messageID,
                userData: userData
            ) {
                messages.append(message)
            }
        }
        return messages
    }

    private func fetchGeneralMessage(
        messageID: String,
        userDocumentID: String,
        userData: [String: Any]
    ) async throws -> NotificationMessage? {
        let messageSnapshot = try await Firestore.firestore()
            .collection("generalMessages")
            .document(messageID)
            .getDocument()
        guard var messageData = messageSnapshot.data() else { return nil }
        messageData["readTimestamp"] = Self.readTimestamp(for: messageID, in: userData)
        return Self.message(
            id: "general-\(messageID)",
            source: .general(userDocumentID: userDocumentID, messageID: messageID),
            data: messageData,
            fallbackTimestamp: Self.dateValue(messageID)
        )
    }

    private static func message(
        id: String,
        source: NotificationMessage.Source,
        data: [String: Any],
        fallbackTimestamp: Date?
    ) -> NotificationMessage? {
        let title = firstString(in: data, keys: ["title", "subject", "heading"])
        let text = firstString(in: data, keys: ["text", "message", "body", "description"])
        guard !title.isEmpty || !text.isEmpty else { return nil }

        return NotificationMessage(
            id: id,
            source: source,
            title: title.isEmpty ? LocalizationSupport.localized("Message") : title,
            text: text,
            timestamp: dateValue(data["createdAt"])
                ?? dateValue(data["timestamp"])
                ?? dateValue(data["sentAt"])
                ?? fallbackTimestamp
                ?? Date.distantPast,
            readTimestamp: dateValue(data["readTimestamp"])
                ?? dateValue(data["readAt"])
        )
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

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Timestamp { return value.dateValue() }
        if let value = value as? String {
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            if let number = Double(value) { return normalizedDate(millisecondsOrSeconds: number) }
        }
        if let value = value as? Double { return normalizedDate(millisecondsOrSeconds: value) }
        if let value = value as? NSNumber { return normalizedDate(millisecondsOrSeconds: value.doubleValue) }
        return nil
    }

    private static func normalizedDate(millisecondsOrSeconds value: Double) -> Date? {
        guard value > 0 else { return nil }
        let seconds = value < 10_000_000_000 ? value : value / 1000.0
        return Date(timeIntervalSince1970: seconds)
    }

    private static func generalMessageIDs(from userData: [String: Any]) -> [String] {
        if let values = userData["generalMessages"] as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let values = userData["generalMessages"] as? [Any] {
            return values.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let values = userData["generalMessages"] as? [String: Any] {
            return values.keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static func readTimestamp(for messageID: String, in userData: [String: Any]) -> Any? {
        if let direct = userData["readTimestamp"] {
            return direct
        }
        if let values = userData["generalMessages"] as? [String: Any] {
            if let row = values[messageID] as? [String: Any] {
                return row["readTimestamp"] ?? row["readAt"]
            }
            if let isRead = values[messageID] as? Bool, isRead {
                return Date()
            }
        }
        if let readIDs = userData["readGeneralMessages"] as? [String], readIDs.contains(messageID) {
            return Date()
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
