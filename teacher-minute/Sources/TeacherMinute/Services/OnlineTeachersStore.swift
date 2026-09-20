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
  /// Presence changes are not as time-critical as the 2s invite poll, and each
  /// tick is one RTDB read, so this trades a little latency for far less work.
  private static let pollInterval: UInt64 = 5_000_000_000

  private let onPresenceUpdated: ([OnlineTeacherPresence]) -> Void
  private var pollingTask: Task<Void, Never>?
  /// Signature of the last emitted set, so an unchanged poll costs nothing
  /// downstream. This matters: each emission makes the view model fetch a
  /// Firestore profile per online teacher, which must not happen every tick.
  private var lastSignature: String?

  init(onPresenceUpdated: @escaping ([OnlineTeacherPresence]) -> Void) {
    self.onPresenceUpdated = onPresenceUpdated
  }

  /// Polls rather than observing: the Firebase listener lives in Kotlin and
  /// there is no callback path back across the JNI bridge, so this mirrors
  /// `startAndroidInvitePolling` in TeacherDashboardViewModel — the same
  /// approach the app already uses for live data on Android.
  func startListening() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        let json = await Self.fetchOnlineTeachersJSON()
        guard !Task.isCancelled, let self else { return }

        let presences = Self.presences(fromJSON: json)
        let signature = Self.signature(for: presences)
        if signature != self.lastSignature {
          self.lastSignature = signature
          logger.info("[OnlineTeachers] Android presence changed count=\(presences.count)")
          self.onPresenceUpdated(presences)
        }

        try? await Task.sleep(nanoseconds: Self.pollInterval)
      }
    }
  }

  func stopListening() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  /// Order-independent, so a reshuffled read is not mistaken for a change.
  private static func signature(for presences: [OnlineTeacherPresence]) -> String {
    presences
      .map { "\($0.id):\($0.subjects.sorted().joined(separator: ","))" }
      .sorted()
      .joined(separator: "|")
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
        OnlineTeacherPresence(
          id: id,
          subjects: row["subjects"] as? [String] ?? [],
          displayName: row["displayName"] as? String ?? "",
          photoUrl: row["photoUrl"] as? String ?? ""
        )
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
    self.ref = FirebaseDatabase.Database.database().reference(withPath: "onlineTeachers")
  }

  func startListening() {
    handle = ref.observe(.value) { [weak self] snapshot in
      guard let self else { return }
      // Every entry in the projection is online by construction — the backend
      // removes it when a teacher goes offline — so there is no status to filter.
      var presences: [OnlineTeacherPresence] = []
      for child in snapshot.children {
        guard
          let snap = child as? DataSnapshot,
          let dict = snap.value as? [String: Any]
        else { continue }
        presences.append(
          OnlineTeacherPresence(
            id: snap.key,
            subjects: dict["subjects"] as? [String] ?? [],
            displayName: dict["displayName"] as? String ?? "",
            photoUrl: dict["photoUrl"] as? String ?? ""
          )
        )
      }
      logger.info("[OnlineTeachers] presence updated count=\(presences.count)")
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
