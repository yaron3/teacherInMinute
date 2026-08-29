//
//  OnlineTeachersStore.swift
//  teacher-minute
//
// Reads RTDB path: teachers/{uid}/
//   status   : String ("online" | "offline")
//   subjects : [String]
//
// Supplies the teachers currently online for the student home
// "Teachers online now" grid.
//
// Platform split follows TeacherAvailabilityStore, which reads the same node:
//   iOS     — FirebaseDatabase directly, with a live `.observe` listener.
//   Android — a JNI call into AndroidTeacherPresenceManager. The transpiled
//             `#if SKIP` route is deliberately not used here; this app reaches
//             Firebase from Android through hand-written Kotlin managers, and a
//             transpiled Swift class bridges as Kotlin `internal`, whose
//             name-mangled methods JNI cannot resolve at runtime.

import Foundation

#if os(Android)
import SkipBridge

@MainActor
final class OnlineTeachersStore {
  private let onPresenceUpdated: ([OnlineTeacherPresence]) -> Void
  private var isStopped = false

  init(onPresenceUpdated: @escaping ([OnlineTeacherPresence]) -> Void) {
    self.onPresenceUpdated = onPresenceUpdated
  }

  /// One-shot read rather than a live listener: bridging a continuous Firebase
  /// callback across JNI buys little here, since the grid is refreshed when the
  /// home screen loads and on pull-to-refresh.
  func startListening() {
    Task { [weak self] in
      let json = await Self.fetchOnlineTeachersJSON()
      guard let self, !self.isStopped else { return }
      self.onPresenceUpdated(Self.presences(fromJSON: json))
    }
  }

  func stopListening() {
    isStopped = true
  }

  private static func fetchOnlineTeachersJSON() async -> String {
    do {
      return try await Task.detached(priority: .userInitiated) {
        try AndroidOnlineTeachersBridge.onlineTeachersJSON()
      }.value
    } catch {
      logger.error("[OnlineTeachers] Android fetch failed: \(error)")
      return "[]"
    }
  }

  private static func presences(fromJSON json: String) -> [OnlineTeacherPresence] {
    guard let data = json.data(using: .utf8),
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }

    var presences: [OnlineTeacherPresence] = []
    for row in rows {
      guard let id = row["id"] as? String, !id.isEmpty else { continue }
      presences.append(
        OnlineTeacherPresence(id: id, subjects: row["subjects"] as? [String] ?? [])
      )
    }
    return presences
  }
}

private enum AndroidOnlineTeachersBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidTeacherPresenceManager")
  private static let onlineTeachersJSONMethod = managerClass.getStaticMethodID(
    name: "onlineTeachersJSON",
    sig: "()Ljava/lang/String;"
  )!

  static func onlineTeachersJSON() throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: onlineTeachersJSONMethod,
        options: [.kotlincompat],
        args: []
      )
    }
  }
}

#else
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
