//
//  IncomingInvite.swift
//  teacher-minute
//
// Mirrors the RTDB node written by the backend at:
//   teacherInvites/{teacherId}/{questionId}/
//     topic     : String
//     text      : String  (first 300 chars of the student's question)
//     expiresAt : Double  (Unix ms — the 12s wave deadline)
//     wave      : Int

import Foundation

#if SKIP

// ── Android transpiled implementation ────────────────────────────────────
// Keep computed properties simple — Skip transpiles these to Kotlin directly.

struct IncomingInvite: Identifiable {
  let id: String
  let topic: String
  let text: String
  let expiresAt: Double   // Unix ms
  let wave: Int
  let photoUrls: [String]
  let hasVoiceMessage: Bool
  let voiceMessageDurationSeconds: Int?
  let studentId: String
  let studentName: String
  let connectionFeeCents: Int
  let pricePerMinuteCents: Int
  let conversationType: String

  var secondsRemaining: Double {
    (expiresAt - Date().timeIntervalSince1970 * 1000.0) / 1000.0
  }

  var isExpired: Bool { secondsRemaining <= 0.0 }
}

#elseif !SKIP_BRIDGE

// ── iOS native implementation ─────────────────────────────────────────────

struct IncomingInvite: Identifiable {
  let id: String
  let topic: String
  let text: String
  let expiresAt: Double   // Unix ms
  let wave: Int
  let photoUrls: [String]
  let hasVoiceMessage: Bool
  let voiceMessageDurationSeconds: Int?
  let studentId: String
  let studentName: String
  let connectionFeeCents: Int
  let pricePerMinuteCents: Int
  let conversationType: String

  var secondsRemaining: Double {
    (expiresAt - Date().timeIntervalSince1970 * 1000) / 1000
  }

  var isExpired: Bool { secondsRemaining <= 0 }
}

#endif
