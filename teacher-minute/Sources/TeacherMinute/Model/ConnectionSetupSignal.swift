//
//  ConnectionSetupSignal.swift
//  teacher-minute
//
//  What one side of a lesson tells the other while the lesson is still
//  connecting. Each side writes its own entry under
//  `questions/{qid}/connectionSetup/{role}` and reads the other's; no entry
//  means there is nothing to tell, and that side is connecting as usual.
//

import Foundation

enum ConnectionSetupSignal: String {
  /// Waiting on this side's microphone permission: the system prompt is up, or
  /// access was refused and has to be allowed in Settings.
  case microphonePermission = "microphone"
  /// The same, for the camera.
  case cameraPermission = "camera"
  /// This side left before the lesson started.
  case cancelled

  /// How long a side that cancelled leaves the question up after saying so
  /// before ending the lesson, which removes the question and the signal with
  /// it. Android reads the other side's signal once a second.
  static let cancelledAnnouncementNanos: UInt64 = 1_500_000_000

  static func awaiting(_ kind: CapturePermissionKind) -> ConnectionSetupSignal {
    switch kind {
    case .microphone: return .microphonePermission
    case .camera: return .cameraPermission
    }
  }

  /// The permission this side is waiting on, when that is what it says.
  var awaitedPermission: CapturePermissionKind? {
    switch self {
    case .microphonePermission: return .microphone
    case .cameraPermission: return .camera
    case .cancelled: return nil
    }
  }
}

/// What the lesson screen puts to this side about the other one.
enum PeerSetupPrompt: Equatable {
  /// The other side was asked for a permission: wait for them, or cancel.
  case awaitingPermission(CapturePermissionKind)
  /// The other side left before the lesson started.
  case cancelled
}

/// What this side knows about the other one's setup, and what to ask the user
/// about it. Kept apart from the session so the decisions can be tested without
/// a database behind them.
struct PeerSetupTracker: Equatable {
  /// The other side's latest signal.
  private(set) var peerSignal: ConnectionSetupSignal?
  /// Sticky: once the other side has left, nothing read afterwards brings the
  /// lesson back.
  private(set) var peerCancelled = false
  /// This side chose to wait out the other side's permission prompt, and is not
  /// asked again until that prompt is over.
  private(set) var isWaitingForPeerPermission = false

  mutating func receive(_ signal: ConnectionSetupSignal?) {
    if signal == .cancelled {
      peerCancelled = true
    }
    if signal?.awaitedPermission == nil {
      // The prompt is over, one way or another. A later one asks again.
      isWaitingForPeerPermission = false
    }
    peerSignal = signal
  }

  /// The question went away, or reached an end state, and this side did not end
  /// it. While this side is still connecting, or the other side was last heard
  /// waiting on a permission, that is the other side leaving before the lesson
  /// started. Otherwise it is an ordinary end.
  ///
  /// The other side announces a cancel before it ends the lesson, but that
  /// write can be missed: Android reads it on a timer, and the question may be
  /// gone by the next reading.
  mutating func questionEnded(whileConnecting isConnecting: Bool) {
    if isConnecting || peerSignal?.awaitedPermission != nil {
      peerCancelled = true
    }
  }

  mutating func waitForPeerPermission() {
    guard peerSignal?.awaitedPermission != nil else { return }
    isWaitingForPeerPermission = true
  }

  var prompt: PeerSetupPrompt? {
    if peerCancelled { return .cancelled }
    if let kind = peerSignal?.awaitedPermission, !isWaitingForPeerPermission {
      return .awaitingPermission(kind)
    }
    return nil
  }

  /// The permission the other side is being asked for, while they still are.
  var peerAwaitedPermission: CapturePermissionKind? {
    peerCancelled ? nil : peerSignal?.awaitedPermission
  }
}
