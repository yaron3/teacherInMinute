//
//  StoredSession.swift
//  TeacherMinute
//
//  The session Firebase restores at launch, checked before the app trusts it.
//
//  Firebase keeps a signed-in user on the device until told otherwise, even
//  once the account behind it is gone: a guest account deleted by the
//  inactive-guest cleanup, a disabled account, revoked tokens. Such a session
//  still reports a uid, so the app went home with it, and every call that needs
//  a token failed from then on. Attaching a photo said "Unexpected -13020 code
//  from backend" (Storage's "unauthenticated", the token server having
//  answered INVALID_REFRESH_TOKEN), the home showed no teachers online, and
//  nothing short of reinstalling the app recovered.
//

import Foundation
#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

enum StoredSession {
  /// Ends the restored session when Firebase says it can no longer get a
  /// token, so the student or teacher starts over from the welcome screen.
  /// Returns whether it did.
  ///
  /// Only an answer that the session is dead counts: offline, or with the
  /// token server unreachable, the session is kept and the app goes on as it
  /// would have.
  @MainActor
  static func endIfDead() async -> Bool {
    guard let user = Auth.auth().currentUser else { return false }
    do {
      _ = try await user.getIDToken()
      return false
    } catch {
      guard isDeadSessionError(error) else {
        logger.info("[Auth] could not refresh the stored session, keeping it: \(error.localizedDescription)")
        return false
      }
      logger.warning("[Auth] the stored session for uid=\(user.uid) is dead; signing out: \(error.localizedDescription)")
      do {
        try Auth.auth().signOut()
      } catch {
        logger.error("[Auth] could not sign out a dead session: \(error)")
      }
      return true
    }
  }

  /// The server's words for a session that is over for good.
  static let deadSessionMarkers = [
    "INVALID_REFRESH_TOKEN", "TOKEN_EXPIRED", "USER_NOT_FOUND", "USER_DISABLED",
    "user may have been deleted", "has been disabled",
  ]

  /// Firebase Auth's codes for the same: user not found (17011), user disabled
  /// (17005), user token expired (17021), invalid user token (17017).
  static let deadSessionCodes: Set<Int> = [17011, 17005, 17021, 17017]

  /// Whether `error`, from refreshing a token, says the account or its
  /// session is gone. An invalid refresh token comes back from iOS as an
  /// internal error (17999) with the server's reply in the error underneath,
  /// so the whole chain is read.
  static func isDeadSessionError(_ error: Error) -> Bool {
    var texts: [String] = []
#if !os(Android)
    var current: NSError? = error as NSError
    var depth = 0
    while let nsError = current, depth < 5 {
      if nsError.domain == AuthErrorDomain, deadSessionCodes.contains(nsError.code) {
        return true
      }
      texts.append(nsError.localizedDescription)
      if let data = nsError.userInfo["data"] as? Data, let reply = String(data: data, encoding: .utf8) {
        texts.append(reply)
      }
      current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
      depth += 1
    }
#else
    texts.append(error.localizedDescription)
    texts.append("\(error)")
#endif
    return texts.contains { text in
      deadSessionMarkers.contains { text.localizedCaseInsensitiveContains($0) }
    }
  }
}
