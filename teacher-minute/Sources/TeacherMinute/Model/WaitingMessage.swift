//
//  WaitingMessage.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 08/05/2026.
//

import Foundation

// MARK: - WaitingMessage
//
// Conditional compilation pattern:
//   #if SKIP          → simple Android struct (transpiled; no enums/failable inits)
//   #elseif !SKIP_BRIDGE → full iOS struct (MessageStatus enum + [String: Any] init)
//   #else             → Android bridge-mode stub so Swift compiles

#if SKIP

// ── Android transpiled implementation ────────────────────────────────────
// Skip cannot transpile RawRepresentable failable inits or [String: Any].
// Status is stored as a plain String; dictionary parsing lives in
// TeacherPresenceService's #if SKIP block.

struct WaitingMessage: Identifiable {
  
  let id: String
  let studentUID: String
  let studentName: String
  let topic: String
  let subject: String
  let isHighPriority: Bool
  let createdAt: Double   // Unix timestamp (seconds)
  var statusRaw: String   // "waiting" | "accepted" | "rejected"
  
  // Simple memberwise init — no [String: Any], no failable init.
  init(
	id: String,
	studentUID: String,
	studentName: String,
	topic: String,
	subject: String,
	isHighPriority: Bool,
	createdAt: Double,
	statusRaw: String
  ) {
	self.id             = id
	self.studentUID     = studentUID
	self.studentName    = studentName
	self.topic          = topic
	self.subject        = subject
	self.isHighPriority = isHighPriority
	self.createdAt      = createdAt
	self.statusRaw      = statusRaw
  }
  
  var isWaiting: Bool { statusRaw == "waiting" }
  
  var waitingTimeLabel: String {
	let elapsed = Date().timeIntervalSince1970 - createdAt
	let minutes = Int(elapsed / 60.0)
	return minutes <= 0 ? "Just now" : "Waiting \(minutes)m"
  }
}

#elseif !SKIP_BRIDGE

// ── iOS native implementation ─────────────────────────────────────────────

struct WaitingMessage: Identifiable, Codable {
  
  let id: String
  let studentUID: String
  let studentName: String
  let topic: String
  let subject: String
  let isHighPriority: Bool
  let createdAt: TimeInterval   // Unix timestamp (seconds)
  var status: MessageStatus
  
  enum MessageStatus: String, Codable {
	case waiting
	case accepted
	case rejected
  }
  
  init(
	id: String,
	studentUID: String,
	studentName: String,
	topic: String,
	subject: String,
	isHighPriority: Bool,
	createdAt: Double,
	statusRaw: String
  ) {
	self.id            = id
	self.studentUID    = studentUID
	self.studentName   = studentName
	self.topic         = topic
	self.subject       = subject
	self.isHighPriority = isHighPriority
	self.createdAt     = createdAt
	self.status        = MessageStatus(rawValue: statusRaw) ?? .waiting
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
  
  var waitingTimeLabel: String {
	let elapsed = Date().timeIntervalSince1970 - createdAt
	let minutes = Int(elapsed / 60)
	return minutes <= 0 ? "Just now" : "Waiting \(minutes)m"
  }
}

//#else
//
//// ── Android bridge-mode stub ──────────────────────────────────────────────
//// Minimal definition so the Swift JNI binary compiles.
//// Firebase queue data flows through the transpiled Kotlin path (#if SKIP).
//
//struct WaitingMessage: Identifiable {
//  let id: String
//  let studentUID: String
//  let studentName: String
//  let topic: String
//  let subject: String
//  let isHighPriority: Bool
//  let createdAt: Double
//  var status: MessageStatus
//  
//  enum MessageStatus: String {
//	case waiting, accepted, rejected
//  }
//  
//  init(id: String, studentUID: String, studentName: String, topic: String,
//	   subject: String, isHighPriority: Bool, createdAt: Double, statusRaw: String) {
//	self.id = id; self.studentUID = studentUID; self.studentName = studentName
//	self.topic = topic; self.subject = subject; self.isHighPriority = isHighPriority
//	self.createdAt = createdAt
//	self.status = MessageStatus(rawValue: statusRaw) ?? .waiting
//  }
//  
//  init?(id: String, data: [String: Any]) { return nil }
//  
//  var waitingTimeLabel: String { "" }
//  var firebaseData: [String: Any] { [:] }
//}

#endif // SKIP / !SKIP_BRIDGE / else
