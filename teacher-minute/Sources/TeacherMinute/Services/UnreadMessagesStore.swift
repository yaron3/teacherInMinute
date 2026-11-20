import Foundation
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
import FirebaseFirestore
#else
import SkipFirebaseAuth
import SkipFirebaseFirestore
#endif

/// Whether the signed-in user has a message they have not opened, for the
/// bell's badge on the student home and the teacher dashboard.
///
/// Kept live rather than read once: it listens to the places a message for the
/// user lands — their `incomingMessages` and `generalMessages` collections and
/// their own document, which also lists general messages and when each was
/// read — and re-counts whenever any of them changes. So the badge appears as
/// a message arrives and goes once the inbox has marked it read. The listeners
/// follow the signed-in account, and stop on sign-out.
@Observable
@MainActor
final class UnreadMessagesStore {
  static let shared = UnreadMessagesStore()

  var hasUnreadMessages = false

  @ObservationIgnored private var authListener: Any?
  @ObservationIgnored private var listeners: [ListenerRegistration] = []
  @ObservationIgnored private var listeningUID: String?
  @ObservationIgnored private var recountTask: Task<Void, Never>?

  private init() {}

  /// Starts following the signed-in account. Safe to call on every appearance.
  func start() {
    guard authListener == nil else { return }
    authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      let uid = user?.uid
      Task { @MainActor in self?.listen(uid: uid) }
    }
    listen(uid: Auth.auth().currentUser?.uid)
  }

  /// Re-counts now, as after the inbox closes, without waiting for a listener.
  func refresh() {
    guard let uid = listeningUID else { return }
    scheduleRecount(uid: uid)
  }

  private func listen(uid: String?) {
    guard uid != listeningUID else { return }
    stopListening()
    listeningUID = uid
    guard let uid else {
      hasUnreadMessages = false
      return
    }

    let user = Firestore.firestore().collection("users").document(uid)
    let onChange: (Error?) -> Void = { [weak self] error in
      Task { @MainActor in
        guard let self, self.listeningUID == uid else { return }
        if let error {
          // Signing out revokes the read before the auth listener moves on.
          logger.info("[UnreadMessages] listener stopped: \(error.localizedDescription)")
          return
        }
        self.scheduleRecount(uid: uid)
      }
    }
    listeners = [
      user.collection("incomingMessages").addSnapshotListener { _, error in onChange(error) },
      user.collection("generalMessages").addSnapshotListener { _, error in onChange(error) },
      user.addSnapshotListener { _, error in onChange(error) },
    ]
  }

  /// Several listeners report at once (each fires as it attaches), so the
  /// re-count waits a beat and runs once for all of them.
  private func scheduleRecount(uid: String) {
    recountTask?.cancel()
    recountTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard !Task.isCancelled else { return }
      let hasUnread = await UserService.shared.hasUnreadMessages(uid: uid)
      guard !Task.isCancelled, let self, self.listeningUID == uid else { return }
      self.hasUnreadMessages = hasUnread
    }
  }

  private func stopListening() {
    recountTask?.cancel()
    recountTask = nil
    listeners.forEach { $0.remove() }
    listeners = []
  }
}
