//
//  LessonPresence.swift
//  teacher-minute
//
//  Whether each side of a running lesson is still in it. Once the lesson has
//  started, each side's app keeps its own entry under
//  `lessonPresence/{qid}/{role}`: a connection entry that the database server
//  removes when that connection drops, `lostAt` that the server stamps then,
//  and `leftAt` stamped as the side leaves on purpose.
//
//  The lesson ends with the first side to go — the moment it left, or lost its
//  connection and did not come back within the grace period — and the backend
//  bills it to that moment (see migrateQuestionToFirestore in
//  functions/src/lessons.ts). While a side that dropped still has time, the
//  other side is shown that it is reconnecting.
//

import Foundation

/// One side's presence, as read from `lessonPresence/{qid}/{role}`.
struct LessonPresenceReading: Equatable {
  /// At least one of its connections is live.
  var isConnected: Bool
  /// When its connection last dropped, in epoch milliseconds on the server's
  /// clock. Only meaningful while no connection is live.
  var lostAt: Double?
  /// When it left on purpose, in epoch milliseconds on the server's clock.
  var leftAt: Double?

  init(isConnected: Bool = false, lostAt: Double? = nil, leftAt: Double? = nil) {
    self.isConnected = isConnected
    self.lostAt = lostAt
    self.leftAt = leftAt
  }

  /// Reads one side's node. Nil for a side that has published nothing: one not
  /// in the lesson yet, or an app from before presence existed.
  init?(value: Any?) {
    guard let row = value as? [String: Any] else { return nil }
    let connections = row["connections"] as? [String: Any] ?? [:]
    self.init(
      isConnected: !connections.isEmpty,
      lostAt: Self.milliseconds(row["lostAt"]),
      leftAt: Self.milliseconds(row["leftAt"])
    )
  }

  /// Reads the whole lesson's node, keyed by role.
  static func sides(from value: Any?) -> [String: LessonPresenceReading] {
    guard let row = value as? [String: Any] else { return [:] }
    var sides: [String: LessonPresenceReading] = [:]
    for (role, side) in row {
      if let reading = LessonPresenceReading(value: side) {
        sides[role] = reading
      }
    }
    return sides
  }

  /// Left the lesson on purpose.
  var hasLeft: Bool { leftAt != nil }

  /// Cut off: its connection dropped and none has come back. A dropped
  /// connection's handler can fire after the app has already reconnected, so
  /// `lostAt` alone does not make a side lost while it has a live connection.
  var isLost: Bool { !hasLeft && !isConnected && lostAt != nil }

  /// Server timestamps arrive as whichever number type the platform decodes.
  private static func milliseconds(_ value: Any?) -> Double? {
    let number: Double?
    if let value = value as? Double {
      number = value
    } else if let value = value as? Int {
      number = Double(value)
    } else if let value = value as? Int64 {
      number = Double(value)
    } else if let value = value as? NSNumber {
      number = value.doubleValue
    } else {
      number = nil
    }
    guard let number, number > 0 else { return nil }
    return number
  }
}

/// What this side makes of the other one while the lesson runs, fed each
/// reading of the other side's presence. A side that dropped is given
/// `graceSeconds` to come back, counted on this device's clock from when this
/// side first saw it cut off.
struct PeerPresenceTracker: Equatable {
  /// Matches LESSON_RECONNECT_GRACE_SECONDS in functions/src/types.ts.
  static let graceSeconds: TimeInterval = 30

  /// When this side first saw the other one cut off, while it still is.
  private(set) var lostSince: Date?
  /// The other side left the lesson on purpose. Final.
  private(set) var hasLeft = false

  mutating func receive(_ reading: LessonPresenceReading?, at now: Date) {
    guard !hasLeft else { return }
    guard let reading else {
      // Nothing published: not in the lesson yet, or its presence was
      // removed with the lesson.
      lostSince = nil
      return
    }
    if reading.hasLeft {
      hasLeft = true
      lostSince = nil
    } else if reading.isLost {
      if lostSince == nil { lostSince = now }
    } else {
      lostSince = nil
    }
  }

  /// Whole seconds the other side still has to come back, while it is cut off.
  func secondsToReconnect(at now: Date) -> Int? {
    guard !hasLeft, let lostSince else { return nil }
    let remaining = Self.graceSeconds - now.timeIntervalSince(lostSince)
    return max(0, Int(remaining.rounded(.up)))
  }

  /// The other side is gone for good: it left, or stayed cut off for the whole
  /// grace period.
  func isGone(at now: Date) -> Bool {
    if hasLeft { return true }
    guard let lostSince else { return false }
    return now.timeIntervalSince(lostSince) >= Self.graceSeconds
  }
}
