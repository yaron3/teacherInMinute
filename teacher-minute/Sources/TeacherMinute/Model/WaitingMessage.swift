//
//  WaitingMessage.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 08/05/2026.
//

import Foundation

// MARK: - Firebase Realtime DB structure
//
// teachers/
//   {teacherUID}/
//     status: "online" | "offline"
//     subjects: ["Calculus", "Algebra II"]
//     waitingMessages/
//       {messageID}/
//         id:           String   — same as the node key
//         studentUID:   String
//         studentName:  String
//         topic:        String   — e.g. "Calculus • Derivatives"
//         subject:      String   — e.g. "Calculus"
//         isHighPriority: Bool
//         createdAt:    Double  — Unix timestamp (seconds)
//         status:       "waiting" | "accepted" | "rejected"

/// Canonical model for a student help request sitting in the teacher's queue.
struct WaitingMessage: Identifiable, Codable {
    let id: String
    let studentUID: String
    let studentName: String
    let topic: String
    let subject: String
    let isHighPriority: Bool
    let createdAt: TimeInterval   // Unix timestamp
    var status: MessageStatus

    enum MessageStatus: String, Codable {
        case waiting
        case accepted
        case rejected
    }

    /// Convenience initialiser from a raw Firebase dictionary.
    init?(id: String, data: [String: Any]) {
        guard
            let studentUID  = data["studentUID"]   as? String,
            let studentName = data["studentName"]  as? String,
            let topic       = data["topic"]        as? String,
            let subject     = data["subject"]      as? String,
            let createdAt   = data["createdAt"]    as? Double
        else { return nil }

        self.id            = id
        self.studentUID    = studentUID
        self.studentName   = studentName
        self.topic         = topic
        self.subject       = subject
        self.isHighPriority = data["isHighPriority"] as? Bool ?? false
        self.createdAt     = createdAt
        let statusRaw      = data["status"] as? String ?? "waiting"
        self.status        = MessageStatus(rawValue: statusRaw) ?? .waiting
    }

    /// Serialised form written back to Firebase.
    var firebaseData: [String: Any] {
        [
            "id":             id,
            "studentUID":     studentUID,
            "studentName":    studentName,
            "topic":          topic,
            "subject":        subject,
            "isHighPriority": isHighPriority,
            "createdAt":      createdAt,
            "status":         status.rawValue,
        ]
    }

    /// Human-readable waiting duration relative to now.
    var waitingTimeLabel: String {
        let elapsed = Date().timeIntervalSince1970 - createdAt
        let minutes = Int(elapsed / 60)
        return minutes <= 0 ? "Just now" : "Waiting \(minutes)m"
    }
}
