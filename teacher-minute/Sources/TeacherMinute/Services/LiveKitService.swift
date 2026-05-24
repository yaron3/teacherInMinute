//
//  LiveKitService.swift
//  teacher-minute
//
//  Connects to a LiveKit room and publishes local audio (and optionally video).
//  iOS uses the native LiveKit Swift SDK. Android uses a JNI bridge to the
//  native LiveKit Android SDK.
//

import Foundation

#if !os(Android)
import LiveKit
#else
import SkipBridge
#endif

enum LiveKitError: Error, LocalizedError {
  case missingCredentials

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      return "Missing LiveKit room or token."
    }
  }
}

@MainActor
final class LiveKitService {
  static let shared = LiveKitService()

  // TODO: Move to backend response (acceptInvite / getQuestionStatus) or
  // RemoteConfig once we support multiple environments.
  static let serverUrl = "wss://teacher-in-a-moment-qx23966i.livekit.cloud"

#if !os(Android)
  private(set) var room: Room?
  private var diagnosticsTask: Task<Void, Never>?
#endif

  private init() {}

  func connect(roomName: String, token: String, enableVideo: Bool) async throws {
    guard !roomName.isEmpty, !token.isEmpty else {
      throw LiveKitError.missingCredentials
    }

#if !os(Android)
    await disconnect()

    let newRoom = Room()
    logger.info("[LiveKit] connecting room=\(roomName) video=\(enableVideo) url=\(Self.serverUrl)")
    try await newRoom.connect(url: Self.serverUrl, token: token)
    logger.info("[LiveKit] room.connect returned state=\(String(describing: newRoom.connectionState)) localIdentity=\(String(describing: newRoom.localParticipant.identity)) remoteCount=\(newRoom.remoteParticipants.count)")

    _ = try await newRoom.localParticipant.setMicrophone(enabled: true)
    logger.info("[LiveKit] microphone enabled tracks=\(newRoom.localParticipant.trackPublications.count)")

    if enableVideo {
      _ = try await newRoom.localParticipant.setCamera(enabled: true)
      logger.info("[LiveKit] camera enabled tracks=\(newRoom.localParticipant.trackPublications.count)")
    }

    room = newRoom
    startDiagnostics(roomName: roomName)
#else
    let serverUrl = Self.serverUrl
    logger.info("[LiveKit] Android connecting room=\(roomName) video=\(enableVideo) url=\(serverUrl)")
    try await Task.detached(priority: .userInitiated) {
      try AndroidLiveKitBridge.connect(
        serverUrl: serverUrl,
        roomName: roomName,
        token: token,
        enableVideo: enableVideo
      )
    }.value
    logger.info("[LiveKit] Android connected room=\(roomName)")
#endif
  }

  func disconnect() async {
#if !os(Android)
    diagnosticsTask?.cancel()
    diagnosticsTask = nil
    guard let room else { return }
    logger.info("[LiveKit] disconnecting room")
    await room.disconnect()
    self.room = nil
#else
    do {
      try await Task.detached(priority: .userInitiated) {
        try AndroidLiveKitBridge.disconnect()
      }.value
    } catch {
      logger.error("[LiveKit] Android disconnect failed: \(error.localizedDescription)")
    }
#endif
  }

#if !os(Android)
  private func startDiagnostics(roomName: String) {
    diagnosticsTask?.cancel()
    diagnosticsTask = Task { [weak self] in
      for tick in 1...10 {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if Task.isCancelled { return }
        guard let self, let room = self.room else { return }
        logger.info("[LiveKit] poll t=\(tick) room=\(roomName) state=\(String(describing: room.connectionState)) remoteCount=\(room.remoteParticipants.count) localTracks=\(room.localParticipant.trackPublications.count)")
      }
    }
  }
#endif
}

#if os(Android)
private enum AndroidLiveKitBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidLiveKitManager")
  private static let connectMethod = managerClass.getStaticMethodID(
    name: "connect",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)V"
  )!
  private static let disconnectMethod = managerClass.getStaticMethodID(
    name: "disconnect",
    sig: "()V"
  )!

  static func connect(serverUrl: String, roomName: String, token: String, enableVideo: Bool) throws {
    try jniContext {
      try managerClass.callStatic(
        method: connectMethod,
        options: [.kotlincompat],
        args: [
          serverUrl.toJavaParameter(options: [.kotlincompat]),
          roomName.toJavaParameter(options: [.kotlincompat]),
          token.toJavaParameter(options: [.kotlincompat]),
          enableVideo.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func disconnect() throws {
    try jniContext {
      try managerClass.callStatic(
        method: disconnectMethod,
        options: [.kotlincompat],
        args: []
      )
    }
  }
}
#endif
