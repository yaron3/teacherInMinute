//
//  OnlineTeachersStore.swift
//  teacher-minute
//
// Listens to RTDB path: teachers/{uid}/
//   status   : String ("online" | "offline")
//   subjects : [String]
//
// Emits the live list of teachers currently online, for the student home
// "Teachers online now" grid.

import Foundation

#if SKIP

@MainActor
final class OnlineTeachersStore {
  private var ref: DatabaseReference?
  private var handle: UInt?
  private let onPresenceUpdated: ([OnlineTeacherPresence]) -> Void

  init(onPresenceUpdated: @escaping ([OnlineTeacherPresence]) -> Void) {
    self.onPresenceUpdated = onPresenceUpdated
    self.ref = Database.database().reference(withPath: "teachers")
  }

  func startListening() {
    guard let ref else { return }
    handle = ref.observe(DataEventType.value) { [weak self] snapshot in
      guard let self else { return }
      var presences: [OnlineTeacherPresence] = []
      for child in snapshot.children {
        guard
          let snap = child as? DataSnapshot,
          let dict = snap.value as? [String: Any],
          let status = dict["status"] as? String,
          status == "online"
        else { continue }
        let subjects = dict["subjects"] as? [String] ?? []
        presences.append(OnlineTeacherPresence(id: snap.key, subjects: subjects))
      }
      self.onPresenceUpdated(presences)
    }
  }

  func stopListening() {
    guard let handle else { return }
    ref?.removeObserver(withHandle: handle)
    self.handle = nil
  }
}

#elseif !SKIP_BRIDGE

import FirebaseDatabase

@MainActor
final class OnlineTeachersStore {
  private let ref: FirebaseDatabase.DatabaseReference
  private var handle: DatabaseHandle?
  private let onPresenceUpdated: ([OnlineTeacherPresence]) -> Void

  init(onPresenceUpdated: @escaping ([OnlineTeacherPresence]) -> Void) {
    self.onPresenceUpdated = onPresenceUpdated
    self.ref = FirebaseDatabase.Database.database().reference(withPath: "teachers")
  }

  func startListening() {
    handle = ref.observe(.value) { [weak self] snapshot in
      guard let self else { return }
      var presences: [OnlineTeacherPresence] = []
      for child in snapshot.children {
        guard
          let snap = child as? DataSnapshot,
          let dict = snap.value as? [String: Any],
          let status = dict["status"] as? String,
          status == "online"
        else { continue }
        let subjects = dict["subjects"] as? [String] ?? []
        presences.append(OnlineTeacherPresence(id: snap.key, subjects: subjects))
      }
      self.onPresenceUpdated(presences)
    }
  }

  func stopListening() {
    guard let handle else { return }
    ref.removeObserver(withHandle: handle)
    self.handle = nil
  }
}

#endif
