//
//  DatabaseConnectionMonitor.swift
//  teacher-minute
//
//  Watches the Realtime Database's own `.info/connected` flag — the socket the
//  teacher's invite listener rides on. When it drops, the app looks unchanged
//  but no question can arrive, which is the one failure a teacher has to be
//  told about rather than left to discover.
//

import Foundation

#if SKIP

// ── Android transpiled implementation ─────────────────────────────────────

@MainActor
final class DatabaseConnectionMonitor {
  private var ref: DatabaseReference?
  private var handle: UInt?
  private let onConnectionChanged: (Bool) -> Void

  init(onConnectionChanged: @escaping (Bool) -> Void) {
    self.onConnectionChanged = onConnectionChanged
    self.ref = Database.database().reference(withPath: ".info/connected")
  }

  func startListening() {
    guard let ref else { return }
    handle = ref.observe(DataEventType.value) { [weak self] snapshot in
      guard let self else { return }
      let connected = (snapshot.value as? Bool) ?? false
      self.onConnectionChanged(connected)
      ()
    }
  }

  func stopListening() {
    guard let handle else { return }
    ref?.removeObserver(withHandle: handle)
    self.handle = nil
  }
}

#elseif !SKIP_BRIDGE

// ── iOS native implementation ─────────────────────────────────────────────

import FirebaseDatabase

@MainActor
final class DatabaseConnectionMonitor {
  private let ref: FirebaseDatabase.DatabaseReference
  private var handle: DatabaseHandle?
  private let onConnectionChanged: (Bool) -> Void

  init(onConnectionChanged: @escaping (Bool) -> Void) {
    self.onConnectionChanged = onConnectionChanged
    self.ref = FirebaseDatabase.Database.database()
      .reference(withPath: ".info/connected")
  }

  func startListening() {
    handle = ref.observe(.value) { [weak self] snapshot in
      guard let self else { return }
      let connected = (snapshot.value as? Bool) ?? false
      logger.info("[Connection] .info/connected = \(connected)")
      self.onConnectionChanged(connected)
    }
  }

  func stopListening() {
    guard let handle else { return }
    ref.removeObserver(withHandle: handle)
    self.handle = nil
  }
}

#endif // SKIP / !SKIP_BRIDGE
