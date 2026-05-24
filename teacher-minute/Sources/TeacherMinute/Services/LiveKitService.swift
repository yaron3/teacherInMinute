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
  private var roomDelegateAdapter: RoomDelegateAdapter?
  private var diagnosticsTask: Task<Void, Never>?

  /// Notified on the main actor whenever local or remote tracks change.
  var onTracksUpdated: (@MainActor @Sendable () -> Void)?

  var localCameraVideoTrack: VideoTrack? {
    room?.localParticipant.firstCameraVideoTrack
  }

  var remoteCameraVideoTrack: VideoTrack? {
    guard let room else { return nil }
    return room.remoteParticipants.values.lazy.compactMap { $0.firstCameraVideoTrack }.first
  }
#endif

  private init() {}

  func connect(roomName: String, token: String, enableVideo: Bool) async throws {
    guard !roomName.isEmpty, !token.isEmpty else {
      throw LiveKitError.missingCredentials
    }

#if !os(Android)
    await disconnect()

    let newRoom = Room()
    let adapter = RoomDelegateAdapter { [weak self] in
      self?.onTracksUpdated?()
    }
    newRoom.add(delegate: adapter)

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
    roomDelegateAdapter = adapter
    onTracksUpdated?()
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
    if let adapter = roomDelegateAdapter {
      room.remove(delegate: adapter)
    }
    roomDelegateAdapter = nil
    await room.disconnect()
    self.room = nil
    onTracksUpdated?()
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

  func setMicrophoneEnabled(_ enabled: Bool) async {
#if !os(Android)
    guard let room else { return }
    do {
      _ = try await room.localParticipant.setMicrophone(enabled: enabled)
      logger.info("[LiveKit] setMicrophone enabled=\(enabled)")
      onTracksUpdated?()
    } catch {
      logger.error("[LiveKit] setMicrophone failed enabled=\(enabled) error=\(error.localizedDescription)")
    }
#else
    do {
      try await Task.detached(priority: .userInitiated) {
        try AndroidLiveKitBridge.setMicrophoneEnabled(enabled)
      }.value
      logger.info("[LiveKit] Android setMicrophone enabled=\(enabled)")
    } catch {
      logger.error("[LiveKit] Android setMicrophone failed enabled=\(enabled) error=\(error.localizedDescription)")
    }
#endif
  }

  func setCameraEnabled(_ enabled: Bool) async {
#if !os(Android)
    guard let room else { return }
    do {
      _ = try await room.localParticipant.setCamera(enabled: enabled)
      logger.info("[LiveKit] setCamera enabled=\(enabled)")
      onTracksUpdated?()
    } catch {
      logger.error("[LiveKit] setCamera failed enabled=\(enabled) error=\(error.localizedDescription)")
    }
#else
    do {
      try await Task.detached(priority: .userInitiated) {
        try AndroidLiveKitBridge.setCameraEnabled(enabled)
      }.value
      logger.info("[LiveKit] Android setCamera enabled=\(enabled)")
    } catch {
      logger.error("[LiveKit] Android setCamera failed enabled=\(enabled) error=\(error.localizedDescription)")
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

#if !os(Android)
/// Bridges LiveKit `RoomDelegate` callbacks (which can fire on background
/// threads) onto the main actor so the SwiftUI layer can re-read tracks.
final class RoomDelegateAdapter: NSObject, RoomDelegate, @unchecked Sendable {
  private let onUpdate: @MainActor @Sendable () -> Void

  init(onUpdate: @escaping @MainActor @Sendable () -> Void) {
    self.onUpdate = onUpdate
  }

  private func notify() {
    Task { @MainActor in onUpdate() }
  }

  func room(_ room: Room, participantDidConnect participant: RemoteParticipant) { notify() }
  func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) { notify() }
  func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) { notify() }
  func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) { notify() }
  func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) { notify() }
  func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) { notify() }
  func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) { notify() }
}
#endif

#if os(Android)
/// Wraps an arbitrary Kotlin object pointer so it can travel through the
/// `JConvertible` machinery and be embedded into the SwiftUI view tree via
/// `JavaBackedView`.
final class AndroidJavaObject: JObject, JConvertible, @unchecked Sendable {
  static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> AndroidJavaObject {
    AndroidJavaObject(obj!)
  }

  func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
    safePointer()
  }
}

enum AndroidLiveKitBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidLiveKitManager")
  private static let videoViewClass = try! JClass(name: "teacher/minute/AndroidLiveKitVideoView")
  private static let createVideoViewMethod = videoViewClass.getStaticMethodID(
    name: "create",
    sig: "(Ljava/lang/String;Z)Lskip/ui/ComposeView;"
  )!
  private static let connectMethod = managerClass.getStaticMethodID(
    name: "connect",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)V"
  )!
  private static let disconnectMethod = managerClass.getStaticMethodID(
    name: "disconnect",
    sig: "()V"
  )!
  private static let setMicrophoneEnabledMethod = managerClass.getStaticMethodID(
    name: "setMicrophoneEnabled",
    sig: "(Z)V"
  )!
  private static let setCameraEnabledMethod = managerClass.getStaticMethodID(
    name: "setCameraEnabled",
    sig: "(Z)V"
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

  static func setMicrophoneEnabled(_ enabled: Bool) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setMicrophoneEnabledMethod,
        options: [.kotlincompat],
        args: [enabled.toJavaParameter(options: [.kotlincompat])]
      )
    }
  }

  static func setCameraEnabled(_ enabled: Bool) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setCameraEnabledMethod,
        options: [.kotlincompat],
        args: [enabled.toJavaParameter(options: [.kotlincompat])]
      )
    }
  }

  static func makeVideoComposer(mode: String, mirror: Bool) throws -> AndroidJavaObject {
    try jniContext {
      try videoViewClass.callStatic(
        method: createVideoViewMethod,
        options: [.kotlincompat],
        args: [
          mode.toJavaParameter(options: [.kotlincompat]),
          mirror.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }
}
#endif
