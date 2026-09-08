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

/// How well the room is carrying the lesson right now. Deliberately coarser
/// than either SDK's five-value enum: the header only has room to say whether
/// the connection is worth mentioning.
enum SessionMediaQuality: String {
  case unknown
  case good
  case poor
  case lost
}

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

  /// True when a video lesson connected without its camera. Both platforms let
  /// a camera that will not start fall back to audio rather than take the
  /// lesson down, which otherwise happens in silence — this is what the session
  /// header reads to say so. Latched at connect: a camera the user turns off
  /// later is not the same thing.
  private(set) var didFallBackToAudioOnly = false

  private init() {}

  func connect(roomName: String, token: String, enableVideo: Bool) async throws {
    guard !roomName.isEmpty, !token.isEmpty else {
      throw LiveKitError.missingCredentials
    }

    didFallBackToAudioOnly = false

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

    // Adopt the room before publishing so a publish failure still leaves a
    // room we can tear down instead of a connected orphan.
    room = newRoom
    roomDelegateAdapter = adapter

    do {
      _ = try await newRoom.localParticipant.setMicrophone(enabled: true)
      logger.info("[LiveKit] microphone enabled tracks=\(newRoom.localParticipant.trackPublications.count)")
    } catch {
      logger.error("[LiveKit] microphone publish failed room=\(roomName) error=\(error.localizedDescription)")
      await disconnect()
      throw error
    }

    if enableVideo {
      // A camera that will not start (simulator, hardware in use, capture
      // error) must not take the lesson down with it: publish what we can and
      // let the session run audio-only.
      do {
        _ = try await newRoom.localParticipant.setCamera(enabled: true)
        logger.info("[LiveKit] camera enabled tracks=\(newRoom.localParticipant.trackPublications.count)")
      } catch {
        didFallBackToAudioOnly = true
        logger.error("[LiveKit] camera publish failed, continuing audio-only room=\(roomName) error=\(error.localizedDescription)")
      }
    }
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
    if enableVideo {
      // The Kotlin side takes the same "publish what we can" line, so ask it
      // whether a camera actually went out.
      didFallBackToAudioOnly = !AndroidLiveKitBridge.isCameraPublished()
    }
    logger.info("[LiveKit] Android connected room=\(roomName) cameraPublished=\(!self.didFallBackToAudioOnly)")
#endif
  }

  /// The room's current connection quality, or `.unknown` when there is no room
  /// or the SDK has not scored it yet. Polled rather than pushed: Android
  /// reports quality through a Kotlin event stream that is not bridged, and one
  /// reading a second is enough for a line of text.
  func currentMediaQuality() -> SessionMediaQuality {
#if !os(Android)
    guard let room else { return .unknown }
    if room.connectionState == .reconnecting || room.connectionState == .connecting {
      return .lost
    }
    var qualities = [room.localParticipant.connectionQuality]
    qualities.append(contentsOf: room.remoteParticipants.values.map(\.connectionQuality))
    if qualities.contains(.lost) { return .lost }
    if qualities.contains(.poor) { return .poor }
    if qualities.contains(where: { $0 == .good || $0 == .excellent }) { return .good }
    return .unknown
#else
    return SessionMediaQuality(rawValue: AndroidLiveKitBridge.connectionQuality()) ?? .unknown
#endif
  }

  func disconnect() async {
    didFallBackToAudioOnly = false
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
  private static let isCameraPublishedMethod = managerClass.getStaticMethodID(
    name: "isCameraPublished",
    sig: "()Z"
  )!
  private static let connectionQualityMethod = managerClass.getStaticMethodID(
    name: "connectionQuality",
    sig: "()Ljava/lang/String;"
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

  /// Both spell their return type out for the reason `AndroidPermissionBridge`
  /// documents: `callStatic` picks its JNI call from the type it is asked for,
  /// and a mismatch aborts the process rather than failing gracefully.
  static func isCameraPublished() -> Bool {
    let published: Bool? = try? jniContext {
      let value: Bool = try managerClass.callStatic(
        method: isCameraPublishedMethod,
        options: [.kotlincompat],
        args: []
      )
      return value
    }
    return published ?? false
  }

  static func connectionQuality() -> String {
    let quality: String? = try? jniContext {
      let value: String = try managerClass.callStatic(
        method: connectionQualityMethod,
        options: [.kotlincompat],
        args: []
      )
      return value
    }
    return quality ?? "unknown"
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
