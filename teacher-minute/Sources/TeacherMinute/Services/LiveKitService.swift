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

/// Where the room's connection stands. The connect is owned by
/// `LiveKitService` rather than by the screen that asked for it, so a student
/// who starts a lesson by chat leaves it running in the background.
enum MediaConnectionPhase: String {
  case idle
  case connecting
  case connected
  case failed
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

  /// How many times one connect is tried before it is reported failed. A first
  /// attempt lost to a flaky network usually succeeds on the next, which beats
  /// sending the user to the timeout screen.
  static let maxConnectAttempts = 3

  private(set) var connectionPhase: MediaConnectionPhase = .idle
  private var connectTask: Task<Bool, Never>?
  /// Bumped by every new connect and by every disconnect, so an attempt that
  /// was overtaken can tell, once it finally returns, that its room is unwanted.
  private var connectGeneration = 0
  private var connectingRoomName = ""

  private init() {}

  /// Starts connecting in a task this service owns, so the connection carries
  /// on after the screen that asked for it goes away. Asking again for a room
  /// that is already connecting or connected joins that attempt.
  func startConnecting(roomName: String, token: String, enableVideo: Bool) {
    if roomName == connectingRoomName, connectionPhase == .connecting || connectionPhase == .connected {
      return
    }

    connectGeneration += 1
    let generation = connectGeneration
    let previous = connectTask
    previous?.cancel()
    connectingRoomName = roomName
    connectionPhase = .connecting
    connectTask = Task { [weak self] in
      // An overtaken attempt unwinds first: Android cannot interrupt one, and
      // two connects at once would fight over the same room.
      _ = await previous?.value
      guard let self else { return false }
      return await self.connectWithRetries(
        roomName: roomName,
        token: token,
        enableVideo: enableVideo,
        generation: generation
      )
    }
  }

  /// Waits for the current connect to settle; true once the room is connected.
  func waitUntilConnected() async -> Bool {
    guard let connectTask else { return connectionPhase == .connected }
    return await connectTask.value
  }

  private func connectWithRetries(roomName: String, token: String, enableVideo: Bool, generation: Int) async -> Bool {
    for attempt in 1...Self.maxConnectAttempts {
      guard generation == connectGeneration, !Task.isCancelled else { return false }
      if attempt > 1 {
        try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * 1_000_000_000)
        guard generation == connectGeneration, !Task.isCancelled else { return false }
      }
      do {
        try await connectOnce(roomName: roomName, token: token, enableVideo: enableVideo, generation: generation)
        guard generation == connectGeneration else { return false }
        connectionPhase = .connected
        return true
      } catch {
        logger.error("[LiveKit] connect attempt \(attempt)/\(Self.maxConnectAttempts) failed room=\(roomName) error=\(error.localizedDescription)")
      }
    }
    guard generation == connectGeneration else { return false }
    connectionPhase = .failed
    return false
  }

  private func connectOnce(roomName: String, token: String, enableVideo: Bool, generation: Int) async throws {
    guard !roomName.isEmpty, !token.isEmpty else {
      throw LiveKitError.missingCredentials
    }

    didFallBackToAudioOnly = false

#if !os(Android)
    await tearDownRoom()

    let newRoom = Room()
    let adapter = RoomDelegateAdapter { [weak self] in
      self?.onTracksUpdated?()
    }
    newRoom.add(delegate: adapter)

    logger.info("[LiveKit] connecting room=\(roomName) video=\(enableVideo) url=\(Self.serverUrl)")
    // The microphone is started while the room connects rather than published
    // after it, which saves the round trip a separate publish costs. A mic that
    // will not publish still fails the connect, as it did before.
    try await newRoom.connect(
      url: Self.serverUrl,
      token: token,
      connectOptions: ConnectOptions(enableMicrophone: true)
    )
    logger.info("[LiveKit] room.connect returned state=\(String(describing: newRoom.connectionState)) localIdentity=\(String(describing: newRoom.localParticipant.identity)) remoteCount=\(newRoom.remoteParticipants.count) localTracks=\(newRoom.localParticipant.trackPublications.count)")

    // A disconnect that landed while this attempt was in flight wants no room.
    guard generation == connectGeneration else {
      newRoom.remove(delegate: adapter)
      await newRoom.disconnect()
      throw CancellationError()
    }

    room = newRoom
    roomDelegateAdapter = adapter

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
    // A disconnect that landed while the blocking connect ran wants no room.
    // The next attempt waits for this one, so this cannot take down a newer room.
    guard generation == connectGeneration else {
      try? await Task.detached(priority: .userInitiated) {
        try AndroidLiveKitBridge.disconnect()
      }.value
      throw CancellationError()
    }
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

  /// Ends the lesson's media: stops a connect still in flight and leaves the room.
  func disconnect() async {
    connectGeneration += 1
    connectTask?.cancel()
    connectingRoomName = ""
    connectionPhase = .idle
    await tearDownRoom()
  }

  private func tearDownRoom() async {
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
