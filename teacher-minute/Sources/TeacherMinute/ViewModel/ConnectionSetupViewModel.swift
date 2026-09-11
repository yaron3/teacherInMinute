import Foundation
import Observation
import SkipFuse

@Observable
@MainActor
final class ConnectionSetupViewModel {
  static let timeoutSeconds: UInt64 = 30
  /// How long audio may take to connect before the student is offered to
  /// start the lesson by chat rather than keep waiting on it.
  static let chatOfferDelaySeconds: UInt64 = 5

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
  /// True while the room is being connected. The chat offer only counts down
  /// during this, so time spent on a permission prompt is not held against
  /// the connection.
  var isConnectingMedia = false
  var showsChatOffer = false
  private var didAnswerChatOffer = false
  private var chatStartAttempt: Int?
  private var isChatReady = false
  private var isMediaReady = false
  /// Set once the lesson may go ahead without audio: the student chose chat,
  /// or, on the teacher's side, the student is already in the lesson by chat.
  private var skipsMediaWait = false

  init(
    participantName: String,
    participantTeacherId: String = "",
    conversationType: String,
    footerText: String? = nil,
    sessionViewModel: (any ChatSessionViewModeling)? = nil,
    liveKitRoom: String = "",
    liveKitToken: String = "",
    onSessionStarted: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.participantName = participantName
    self.participantTeacherId = participantTeacherId
    self.conversationType = conversationType
    self.footerText = footerText ?? LocalizationSupport.localized("Your teacher will join shortly")
    self.sessionViewModel = sessionViewModel
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onSessionStarted = onSessionStarted
  }

  var hasAudio: Bool { conversationType == "audio" || conversationType == "video" }
  var hasVideo: Bool { conversationType == "video" }
  /// The student decides whether a slow connection starts by chat. The teacher
  /// is never asked, and follows whatever the student picks.
  var isStudent: Bool { sessionViewModel?.role == "student" }
  var offersChatWhileConnecting: Bool { hasAudio && isStudent }
  var connectionTitle: String {
    hasAudio ? LocalizationSupport.localized("connection_setup_connecting_audio") : LocalizationSupport.localized("connection_setup_connecting")
  }
  var timerKey: String { "\(conversationType)-\(attempt)" }
  var chatOfferTimerKey: String { "\(isConnectingMedia)-\(attempt)" }
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

  // MARK: - View strings

  var cancelSessionLabel: String { LocalizationSupport.localized("Cancel Session") }
  var cancelLabel: String { LocalizationSupport.localized("Cancel") }
  var retryLabel: String { LocalizationSupport.localized("Retry") }
  var continueWithTextOnlyLabel: String { LocalizationSupport.localized("Continue with text only") }
  var connectionSlowTitle: String { LocalizationSupport.localized("Connection is taking longer than usual") }

  var connectionSlowMessage: String {
    hasVideo
      ? LocalizationSupport.localized("We couldn't establish a video connection. Retry, continue with text only, or cancel.")
      : LocalizationSupport.localized("We couldn't establish an audio connection. Retry, continue with text only, or cancel.")
  }

  var chatOfferTitle: String {
    hasVideo
      ? LocalizationSupport.localized("Video is taking longer than usual")
      : LocalizationSupport.localized("Audio is taking longer than usual")
  }

  var chatOfferMessage: String {
    LocalizationSupport.localized("You can start with your teacher by chat now. We'll keep connecting in the background.")
  }

  var startWithChatLabel: String { LocalizationSupport.localized("Start with chat") }
  var keepWaitingLabel: String { LocalizationSupport.localized("Keep waiting") }

  var microphonePermissionTitle: String { LocalizationSupport.localized("Microphone Permission") }
  var microphonePermissionMessage: String {
    LocalizationSupport.localized("Make sure your microphone is enabled for the best learning experience.")
  }
  var cameraPermissionTitle: String { LocalizationSupport.localized("Camera Permission") }
  var cameraPermissionMessage: String {
    LocalizationSupport.localized("Make sure your camera is enabled so your teacher can see your work.")
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
    isConnectingMedia = false
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

    // The chat side starts alongside the media connection rather than after
    // it, so a lesson is only ever as slow as the slower of the two.
    setupStatusText = LocalizationSupport.localized("Starting your session")
    startChatSessionIfNeeded(sessionViewModel)
    guard hasAudio, !isMediaReady else {
      finishIfReady()
      return
    }
    await connectMediaSession(questionId: sessionViewModel.questionId)
  }

  /// Starts the chat side at most once per attempt: a retry restarts one that
  /// never came up, and leaves one that did alone.
  private func startChatSessionIfNeeded(_ sessionViewModel: any ChatSessionViewModeling) {
    guard !isChatReady, chatStartAttempt != attempt else { return }
    chatStartAttempt = attempt
    isStartingSession = true
    sessionViewModel.onConnectingUpdated = { [weak self, weak sessionViewModel] isConnecting in
      guard let self, let sessionViewModel else { return }
      logger.info("[ConnectionSetup] connecting update qid=\(sessionViewModel.questionId) isConnecting=\(isConnecting)")
      guard !isConnecting else { return }
      isStartingSession = false
      isChatReady = true
      finishIfReady()
    }
    if !isStudent {
      // A student who chose to start by chat is already in the lesson. The
      // teacher joins them there instead of waiting on their own audio, which
      // keeps connecting in the background.
      sessionViewModel.onMediaPendingUpdated = { [weak self, weak sessionViewModel] _ in
        guard let self, let sessionViewModel, sessionViewModel.peerMediaPending(), !skipsMediaWait else { return }
        logger.info("[ConnectionSetup] student is in the lesson without audio; joining by chat qid=\(sessionViewModel.questionId)")
        skipsMediaWait = true
        finishIfReady()
      }
    }
    logger.info("[ConnectionSetup] invoking ChatSessionViewModel.start qid=\(sessionViewModel.questionId) role=\(sessionViewModel.role) conversationType=\(self.conversationType)")
    sessionViewModel.start()
  }

  private func connectMediaSession(questionId: String) async {
    setupStatusText = LocalizationSupport.localized("Connecting audio/video")
    logger.info("[ConnectionSetup] connecting livekit qid=\(questionId) room=\(self.liveKitRoom) hasVideo=\(self.hasVideo)")

    isConnectingMedia = true
    LiveKitService.shared.startConnecting(roomName: liveKitRoom, token: liveKitToken, enableVideo: hasVideo)
    let connected = await LiveKitService.shared.waitUntilConnected()
    // Cancelled when this screen went away — the student started by chat, say.
    // The connect itself belongs to LiveKitService and carries on without it.
    guard !Task.isCancelled else { return }
    isConnectingMedia = false
    showsChatOffer = false

    if connected {
      logger.info("[ConnectionSetup] livekit connected qid=\(questionId)")
      isMediaReady = true
      finishIfReady()
    } else {
      setupStatusText = LocalizationSupport.localized("Audio/video connection is not ready")
      logger.error("[ConnectionSetup] livekit connect failed after retries qid=\(questionId)")
      // Every retry is spent, so say so now rather than at the timeout.
      if !didStartSession {
        hasTimedOut = true
      }
    }
  }

  private func finishIfReady() {
    guard isChatReady, !hasAudio || isMediaReady || skipsMediaWait else { return }
    hasTimedOut = false
    showsChatOffer = false
    isStartingSession = false
    setupStatusText = LocalizationSupport.localized("Session connected")
    didStartSession = true
    notifySessionStartedIfNeeded()
  }

  private func notifySessionStartedIfNeeded() {
    guard !didNotifySessionStarted else { return }
    didNotifySessionStarted = true
    onSessionStarted?()
  }

  func startTimeoutTimer() async {
    guard hasAudio else { return }
    try? await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
    if !Task.isCancelled {
	  logger.info("[ConnectionSetup] timeout")
      hasTimedOut = true
    }
  }

  /// Counts down while the room connects, and offers the student to start by
  /// chat once it has taken longer than `chatOfferDelaySeconds`.
  func startChatOfferTimer() async {
    guard offersChatWhileConnecting, isConnectingMedia, !didAnswerChatOffer else { return }
    try? await Task.sleep(nanoseconds: Self.chatOfferDelaySeconds * 1_000_000_000)
    guard !Task.isCancelled, isConnectingMedia, !didStartSession, !hasTimedOut else { return }
    logger.info("[ConnectionSetup] offering chat while media connects qid=\(self.sessionViewModel?.questionId ?? "none")")
    showsChatOffer = true
  }

  /// The student's yes to the chat offer: go ahead by chat now, and let audio
  /// carry on connecting in the background and join when it is ready.
  func startWithChat() {
    logger.info("[ConnectionSetup] student starts by chat while media connects qid=\(self.sessionViewModel?.questionId ?? "none")")
    didAnswerChatOffer = true
    showsChatOffer = false
    skipsMediaWait = true
    // Raised now rather than once the lesson screen polls, so a teacher still
    // waiting on their own audio is let in without that delay.
    sessionViewModel?.setSelfMediaPending(true)
    setupStatusText = LocalizationSupport.localized("Starting your session")
    finishIfReady()
  }

  func keepWaitingForMedia() {
    logger.info("[ConnectionSetup] student keeps waiting for media qid=\(self.sessionViewModel?.questionId ?? "none")")
    didAnswerChatOffer = true
    showsChatOffer = false
  }

  func retry() {
    hasTimedOut = false
    showsChatOffer = false
    didAnswerChatOffer = false
    attempt += 1
  }

  func continueAsText() {
	logger.info("[ConnectionSetup] continue as text")
    hasTimedOut = false
    showsChatOffer = false
    conversationType = "text"
    // The student has given up on audio for this lesson: stop the connect that
    // would otherwise carry on in the background, and tell the teacher.
    sessionViewModel?.setSelfMediaPending(true)
    Task {
      await LiveKitService.shared.disconnect()
    }
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
