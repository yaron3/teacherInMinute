//
//  InviteService.swift
//  teacher-minute
//
// Listens to RTDB path:  teacherInvites/{teacherUid}/{questionId}/
//   topic     : String
//   text      : String
//   expiresAt : Double  (Unix ms)
//   wave      : Int
//
// The backend writes this node when a wave invite is sent and removes it when:
//   - the invite times out
//   - the teacher declines
//   - any teacher accepts (question taken)

import Foundation

#if SKIP

private func invLog(_ msg: String) { print(msg) }

@MainActor
final class InviteService {
  private let teacherUid: String
  private var ref: DatabaseReference?
  private var handle: UInt?
  private let onInvitesUpdated: ([IncomingInvite]) -> Void

  init(teacherUid: String, onInvitesUpdated: @escaping ([IncomingInvite]) -> Void) {
    self.teacherUid = teacherUid
    self.onInvitesUpdated = onInvitesUpdated
    self.ref = Database.database().reference(withPath: "teacherInvites/\(teacherUid)")
    invLog("[InviteService] init uid=\(teacherUid)")
  }

  func startListening() {
    guard let ref else { return }
    invLog("[InviteService] startListening uid=\(teacherUid)")
    handle = ref.observe(DataEventType.value) { [weak self] snapshot in
      guard let self else { return }
      var invites: [IncomingInvite] = []
      for child in snapshot.children {
        guard
          let snap      = child as? DataSnapshot,
          let dict      = snap.value as? [String: Any],
          let topic     = dict["topic"]     as? String,
          let text      = dict["text"]      as? String,
          let expiresAt = dict["expiresAt"] as? Double,
          let wave      = dict["wave"]      as? Int
        else { continue }
        let photoUrls = dict["photoUrls"] as? [String] ?? []
        let hasVoiceMessage = (dict["voiceMessageUrl"] as? String)?.isEmpty == false
          || (dict["audioUrl"] as? String)?.isEmpty == false
          || (dict["voiceUrl"] as? String)?.isEmpty == false
        let studentName = Self.firstString(dict, keys: ["studentName", "studentFullName", "studentDisplayName", "name"])
        let studentUid = Self.firstString(dict, keys: ["studentUid", "studentUID", "studentId"])
        let connectionFeeCents = Self.intValue(dict["connectionFeeCents"]) ?? Self.intValue(dict["connectionFee"]) ?? 0
        let pricePerMinuteCents = Self.intValue(dict["pricePerMinuteCents"])
          ?? Self.intValue(dict["ratePerMinuteCents"])
          ?? Self.intValue(dict["costPerMinuteCents"])
          ?? 50
        let invite = IncomingInvite(
          id: snap.key,
          topic: topic,
          text: text,
          expiresAt: expiresAt,
          wave: wave,
          photoUrls: photoUrls,
          hasVoiceMessage: hasVoiceMessage,
          studentUid: studentUid,
          studentName: studentName,
          connectionFeeCents: connectionFeeCents,
          pricePerMinuteCents: pricePerMinuteCents
        )
        if !invite.isExpired { invites.append(invite) }
      }
      invites.sort { $0.expiresAt < $1.expiresAt }
      self.onInvitesUpdated(invites)
    }
  }

  func stopListening() {
    guard let handle else { return }
    ref?.removeObserver(withHandle: handle)
    self.handle = nil
    invLog("[InviteService] stopListening uid=\(teacherUid)")
  }

  private static func firstString(_ dict: [String: Any], keys: [String]) -> String {
    for key in keys {
      if let value = dict[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return ""
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    if let value = value as? Double { return Int(value) }
    return nil
  }
}

#elseif !SKIP_BRIDGE

import FirebaseDatabase

@MainActor
final class InviteService {
  private let teacherUid: String
  private let ref: FirebaseDatabase.DatabaseReference
  private var handle: DatabaseHandle?
  private let onInvitesUpdated: ([IncomingInvite]) -> Void

  init(teacherUid: String, onInvitesUpdated: @escaping ([IncomingInvite]) -> Void) {
    self.teacherUid = teacherUid
    self.onInvitesUpdated = onInvitesUpdated
    self.ref = FirebaseDatabase.Database.database()
      .reference(withPath: "teacherInvites/\(teacherUid)")
    logger.info("[InviteService] init uid=\(teacherUid)")
  }

  func startListening() {
    handle = ref.observe(.value) { [weak self] snapshot in
      guard let self else { return }
      var invites: [IncomingInvite] = []
      for child in snapshot.children {
        guard
          let snap      = child as? DataSnapshot,
          let dict      = snap.value as? [String: Any],
          let topic     = dict["topic"]     as? String,
          let text      = dict["text"]      as? String,
          let expiresAt = dict["expiresAt"] as? Double,
          let wave      = dict["wave"]      as? Int
        else { continue }
        let photoUrls = dict["photoUrls"] as? [String] ?? []
        let hasVoiceMessage = (dict["voiceMessageUrl"] as? String)?.isEmpty == false
          || (dict["audioUrl"] as? String)?.isEmpty == false
          || (dict["voiceUrl"] as? String)?.isEmpty == false
        let studentName = Self.firstString(dict, keys: ["studentName", "studentFullName", "studentDisplayName", "name"])
        let studentUid = Self.firstString(dict, keys: ["studentUid", "studentUID", "studentId"])
        let connectionFeeCents = Self.intValue(dict["connectionFeeCents"]) ?? Self.intValue(dict["connectionFee"]) ?? 0
        let pricePerMinuteCents = Self.intValue(dict["pricePerMinuteCents"])
          ?? Self.intValue(dict["ratePerMinuteCents"])
          ?? Self.intValue(dict["costPerMinuteCents"])
          ?? 50
        let invite = IncomingInvite(
          id: snap.key,
          topic: topic,
          text: text,
          expiresAt: expiresAt,
          wave: wave,
          photoUrls: photoUrls,
          hasVoiceMessage: hasVoiceMessage,
          studentUid: studentUid,
          studentName: studentName,
          connectionFeeCents: connectionFeeCents,
          pricePerMinuteCents: pricePerMinuteCents
        )
        if !invite.isExpired { invites.append(invite) }
      }
      invites.sort { $0.expiresAt < $1.expiresAt }
      self.onInvitesUpdated(invites)
    }
	logger.info("[InviteService] startListening uid=\(self.teacherUid)")
  }

  func stopListening() {
    guard let handle else { return }
    ref.removeObserver(withHandle: handle)
    self.handle = nil
	logger.info("[InviteService] stopListening uid=\(self.teacherUid)")
  }

  private static func firstString(_ dict: [String: Any], keys: [String]) -> String {
    for key in keys {
      if let value = dict[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return ""
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    if let value = value as? Double { return Int(value) }
    return nil
  }
}

#endif
