//
//  OnlineTeacher.swift
//  teacher-minute
//

import Foundation

#if SKIP

// ── Android transpiled implementation ────────────────────────────────────

/// A teacher currently online, ready to be shown in the student home "Teachers
/// online now" grid. Built by joining an `OnlineTeacherPresence` (from RTDB)
/// with that teacher's Firestore profile (name, photo).
struct OnlineTeacher: Identifiable {
  let id: String
  let name: String
  let subject: String
  let profileImageURL: String

  var initial: String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
  }
}

/// A teacher's live RTDB presence at `teachers/{uid}`: `status` and `subjects`.
struct OnlineTeacherPresence: Identifiable {
  let id: String
  let subjects: [String]
}

#elseif !SKIP_BRIDGE

// ── iOS native implementation ─────────────────────────────────────────────

struct OnlineTeacher: Identifiable {
  let id: String
  let name: String
  let subject: String
  let profileImageURL: String

  var initial: String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
  }
}

struct OnlineTeacherPresence: Identifiable {
  let id: String
  let subjects: [String]
}

#endif
