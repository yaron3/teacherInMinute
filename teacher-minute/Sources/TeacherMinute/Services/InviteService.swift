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
        let invite = IncomingInvite(
          id: snap.key,
          topic: topic,
          text: text,
          expiresAt: expiresAt,
          wave: wave
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
        let invite = IncomingInvite(
          id: snap.key,
          topic: topic,
          text: text,
          expiresAt: expiresAt,
          wave: wave
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
}

#endif
