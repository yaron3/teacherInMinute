//
//  TeacherKeepAlive.swift
//  teacher-minute
//
//  Tells the backend, once a minute, that an available teacher's app is still
//  running.
//

import Foundation

/// Repeats a keep-alive while the teacher is online.
///
/// `status: "online"` says a teacher wants questions; only a running app can
/// show them one. So the backend expects a keep-alive once a minute from every
/// online teacher, and takes an app it has not heard from for three minutes to
/// be gone (functions/src/keepAlive.ts). A teacher it can still reach by push
/// stays in the pool; one it cannot is taken offline.
///
/// What a keep-alive writes differs by platform, so the caller supplies it and
/// this only keeps time. The write re-sends `status: "online"` along with the
/// timestamp, which is how a teacher the backend took offline while the app was
/// away gets back in once it runs again.
@MainActor
final class TeacherKeepAlive {
  private let interval: UInt64
  private let send: @MainActor () -> Void
  private var loop: Task<Void, Never>?

  /// - Parameter interval: nanoseconds between keep-alives. A minute is a third
  ///   of the backend's timeout, so one late or lost write never reads as an
  ///   app that has gone.
  init(interval: UInt64 = 60 * 1_000_000_000, send: @escaping @MainActor () -> Void) {
    self.interval = interval
    self.send = send
  }

  var isRunning: Bool { loop != nil }

  /// Starts sending, the first one an interval from now: going online writes a
  /// timestamp of its own. Does nothing while already running.
  func start() {
    guard loop == nil else { return }
    let interval = self.interval
    loop = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        guard !Task.isCancelled, let self else { return }
        self.send()
      }
    }
  }

  /// Sends one now rather than on the next tick — for the app coming back to
  /// the front, when the backend may have taken the teacher offline while it
  /// was away. Does nothing while stopped, so an offline teacher stays offline.
  func sendNow() {
    guard loop != nil else { return }
    send()
  }

  func stop() {
    loop?.cancel()
    loop = nil
  }
}
