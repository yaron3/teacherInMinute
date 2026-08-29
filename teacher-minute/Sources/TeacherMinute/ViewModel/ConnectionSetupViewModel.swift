import Foundation
import Observation

@Observable
@MainActor
final class ConnectionSetupViewModel {
  static let timeoutSeconds: UInt64 = 30

  let participantName: String
  /// The other side's uid, when known. Only a teacher's is looked up: the
  /// student sees who they are about to be taught by, and students have no
  /// public rating.
  let participantTeacherId: String
  var conversationType: String
  let footerText: String
  let liveKitRoom: String
  let liveKitToken: String
  private let onSessionStarted: (@MainActor @Sendable () -> Void)?
  private let sessionViewModel: (any ChatSessionViewModeling)?
  private var didNotifySessionStarted = false

  /// The teacher's real reputation, loaded once the screen appears. Stays at
  /// zero for a teacher with no reviews and whenever there is no teacher to
  /// look up, and `showsRating` gates the row on it.
  var participantRating: Double = 0
  var participantReviewCount: Int = 0

  var showsRating: Bool { participantReviewCount > 0 }

  var hasTimedOut = false
  var attempt = 0
  var microphoneState: PermissionState = .notDetermined
  var cameraState: PermissionState = .notDetermined
  var setupStatusText = LocalizationSupport.localized("Checking session requirements")
  var isStartingSession = false
  var didStartSession = false

  init(
    participantName: String,
    participantTeacherId: String = "",
    conversationType: String,
    footerText: String = LocalizationSupport.localized("Your teacher will join shortly"),
    sessionViewModel: (any ChatSessionViewModeling)? = nil,
    liveKitRoom: String = "",
    liveKitToken: String = "",
    onSessionStarted: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.participantName = participantName
    self.participantTeacherId = participantTeacherId
    self.conversationType = conversationType
    self.footerText = footerText
    self.sessionViewModel = sessionViewModel
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onSessionStarted = onSessionStarted
  }

  var hasAudio: Bool { conversationType == "audio" || conversationType == "video" }
  var hasVideo: Bool { conversationType == "video" }
  var connectionTitle: String {
    hasAudio ? LocalizationSupport.localized("connection_setup_connecting_audio") : LocalizationSupport.localized("connection_setup_connecting")
  }
  var timerKey: String { "\(conversationType)-\(attempt)" }
  var sessionStartKey: String { "\(sessionViewModel?.questionId ?? "no-session")-\(conversationType)-\(attempt)" }
  var hasRequiredPermissions: Bool {
    (!hasAudio || microphoneState.isGranted) && (!hasVideo || cameraState.isGranted)
  }
  var hasMediaCredentials: Bool {
    !hasAudio || (!liveKitRoom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !liveKitToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }
  var statusTextColorNeedsAttention: Bool { !hasRequiredPermissions || !hasMediaCredentials || (hasAudio && !isStartingSession) }

  var permissionBlockedText: String {
    if hasVideo {
      return LocalizationSupport.localized("Microphone and camera access are required for this video session.")
    }
    return LocalizationSupport.localized("Microphone access is required for this audio session.")
  }

  var microphoneButtonTitle: String {
    switch microphoneState {
    case .granted: return LocalizationSupport.localized("Microphone Enabled")
    case .denied: return LocalizationSupport.localized("Open Microphone Settings")
    case .notDetermined: return LocalizationSupport.localized("Allow Microphone")
    }
  }

  var cameraButtonTitle: String {
    switch cameraState {
    case .granted: return LocalizationSupport.localized("Camera Enabled")
    case .denied: return LocalizationSupport.localized("Open Camera Settings")
    case .notDetermined: return LocalizationSupport.localized("Allow Camera")
    }
  }

  /// Fetches the waiting teacher's star average and review count. Quiet on
  /// failure: a rating is nice to see while connecting, never worth an error.
  func loadParticipantRating() async {
    let teacherId = participantTeacherId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !teacherId.isEmpty, participantReviewCount == 0 else { return }

    do {
      let summary = try await FunctionsService.shared.teacherRatingSummary(teacherId: teacherId)
      participantRating = summary.averageRating
      participantReviewCount = summary.ratingCount
      logger.info("[ConnectionSetup] teacher rating=\(summary.averageRating) reviews=\(summary.ratingCount)")
    } catch {
      logger.error("[ConnectionSetup] failed loading teacher rating: \(error.localizedDescription)")
    }
  }

  func runSetupAttempt() async {
    logger.info("[ConnectionSetup] attempt start qid=\(self.sessionViewModel?.questionId ?? "none") role=\(self.sessionViewModel?.role ?? "unknown") conversationType=\(self.conversationType) attempt=\(self.attempt)")
    setupStatusText = LocalizationSupport.localized("Checking device permissions")

    if hasAudio {
      microphoneState = await PermissionService.shared.requestCapturePermission(for: .microphone)
      logger.info("[ConnectionSetup] microphone state=\(self.microphoneState.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
    }
    if hasVideo {
      cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
      logger.info("[ConnectionSetup] camera state=\(self.cameraState.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
    }

    guard hasRequiredPermissions else {
      setupStatusText = permissionBlockedText
      logger.info("[ConnectionSetup] blocked by permissions qid=\(self.sessionViewModel?.questionId ?? "none") mic=\(self.microphoneState.rawValue) camera=\(self.cameraState.rawValue)")
      return
    }

    guard hasMediaCredentials else {
      setupStatusText = LocalizationSupport.localized("Waiting for audio/video connection")
      logger.info("[ConnectionSetup] blocked by missing media credentials qid=\(self.sessionViewModel?.questionId ?? "none") roomEmpty=\(self.liveKitRoom.isEmpty) tokenEmpty=\(self.liveKitToken.isEmpty) conversationType=\(self.conversationType)")
      return
    }

    guard let sessionViewModel else {
      setupStatusText = LocalizationSupport.localized("Waiting for the other side")
      logger.info("[ConnectionSetup] no session view model; showing passive setup conversationType=\(self.conversationType)")
      return
    }

    guard await connectMediaSessionIfNeeded(questionId: sessionViewModel.questionId) else {
      return
    }

    setupStatusText = LocalizationSupport.localized("Starting your session")
    isStartingSession = true
    sessionViewModel.onConnectingUpdated = { [weak self, weak sessionViewModel] isConnecting in
      guard let self, let sessionViewModel else { return }
      logger.info("[ConnectionSetup] connecting update qid=\(sessionViewModel.questionId) isConnecting=\(isConnecting)")
      guard !isConnecting else { return }
      isStartingSession = false
      hasTimedOut = false
      setupStatusText = LocalizationSupport.localized("Session connected")
      didStartSession = true
      notifySessionStartedIfNeeded()
    }
    logger.info("[ConnectionSetup] invoking ChatSessionViewModel.start qid=\(sessionViewModel.questionId) role=\(sessionViewModel.role) conversationType=\(self.conversationType)")
    sessionViewModel.start()
  }

  private func notifySessionStartedIfNeeded() {
    guard !didNotifySessionStarted else { return }
    didNotifySessionStarted = true
    onSessionStarted?()
  }

  private func connectMediaSessionIfNeeded(questionId: String) async -> Bool {
    guard hasAudio else { return true }

    setupStatusText = LocalizationSupport.localized("Connecting audio/video")
    logger.info("[ConnectionSetup] connecting livekit qid=\(questionId) room=\(self.liveKitRoom) hasVideo=\(self.hasVideo)")

    do {
      try await LiveKitService.shared.connect(
        roomName: liveKitRoom,
        token: liveKitToken,
        enableVideo: hasVideo
      )
      logger.info("[ConnectionSetup] livekit connected qid=\(questionId)")
      return true
    } catch {
      setupStatusText = LocalizationSupport.localized("Audio/video connection is not ready")
      logger.error("[ConnectionSetup] livekit connect failed qid=\(questionId) error=\(error.localizedDescription)")
      return false
    }
  }

  func startTimeoutTimer() async {
    guard hasAudio else { return }
    try? await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
    if !Task.isCancelled {
	  logger.info("[ConnectionSetup] timeout")
      hasTimedOut = true
    }
  }

  func retry() {
    hasTimedOut = false
    attempt += 1
  }

  func continueAsText() {
	logger.info("[ConnectionSetup] continue as text")
    hasTimedOut = false
    conversationType = "text"
    attempt += 1
  }

  func requestPermission(_ kind: CapturePermissionKind) {
    Task {
      let state = await PermissionService.shared.requestCapturePermission(for: kind)
      switch kind {
      case .microphone:
        microphoneState = state
      case .camera:
        cameraState = state
      }
      logger.info("[ConnectionSetup] permission button result kind=\(kind.logName) state=\(state.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
      if state == .denied {
        PermissionService.shared.openAppSettings()
      }
      if hasRequiredPermissions {
        attempt += 1
      } else {
        setupStatusText = permissionBlockedText
      }
    }
  }
}

private extension CapturePermissionKind {
  var logName: String {
    switch self {
    case .microphone: return "microphone"
    case .camera: return "camera"
    }
  }
}
