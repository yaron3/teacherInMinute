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
  /// Connected on this side, and waiting on this screen for the other side:
  /// both go into the lesson together, as it starts.
  var isWaitingForPeer = false
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
  /// This side has gone to Settings for a permission during this setup — on
  /// this launch, or on the one iOS closed while it was there. From then on the
  /// other side hears it is finishing setup, not that it was asked for a
  /// permission.
  private var wentToSettings = false
  /// Stopped only on a permission the user has to act on, so a return to the
  /// app retries only then — not while a system prompt is still being answered.
  private var isBlockedOnPermissions = false

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
    wentToSettings = sessionViewModel?.returnsFromSettings ?? false
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

  /// The line under the connection title. While the other side is answering a
  /// permission prompt, or finishing its setup in Settings, that is what this
  /// side is waiting on.
  var statusText: String {
    guard let sessionViewModel,
          sessionViewModel.peerAwaitedPermission != nil || sessionViewModel.isPeerFinishingSetup else {
      return setupStatusText
    }
    return sessionViewModel.waitingForPeerText
  }

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
    isBlockedOnPermissions = false
    setupStatusText = LocalizationSupport.localized("Checking device permissions")

    // Only a screen with a lesson behind it asks. The placeholder shown while a
    // teacher's accept is on its way leaves a missing permission to the
    // lesson's own setup, where the student is told the teacher is being asked.
    let asksForPermissions = sessionViewModel != nil
    if hasAudio {
      microphoneState = await capturePermission(.microphone, asks: asksForPermissions)
      logger.info("[ConnectionSetup] microphone state=\(self.microphoneState.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
    }
    if hasVideo {
      cameraState = await capturePermission(.camera, asks: asksForPermissions)
      logger.info("[ConnectionSetup] camera state=\(self.cameraState.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
    }

    guard let sessionViewModel else {
      setupStatusText = LocalizationSupport.localized("Waiting for the other side")
      logger.info("[ConnectionSetup] no session view model; showing passive setup conversationType=\(self.conversationType)")
      return
    }

    guard hasRequiredPermissions else {
      isBlockedOnPermissions = true
      setupStatusText = permissionBlockedText
      logger.info("[ConnectionSetup] blocked by permissions qid=\(sessionViewModel.questionId) mic=\(self.microphoneState.rawValue) camera=\(self.cameraState.rawValue)")
      // Still waiting on the user, so the other side goes on hearing about it.
      guard isFinishingSetupInSettings else {
        sessionViewModel.setSelfAwaitingPermission(missingPermission)
        return
      }
      await sessionViewModel.announceFinishingSetup()
      // A lesson taken on the way to Settings goes there now, once: back
      // without the permission, the teacher has the button.
      guard !wentToSettings, !Task.isCancelled, sessionViewModel.peerSetupPrompt != .cancelled else { return }
      wentToSettings = true
      logger.info("[ConnectionSetup] opening Settings to finish setup qid=\(sessionViewModel.questionId)")
      PermissionService.shared.openAppSettings()
      return
    }
    sessionViewModel.setSelfAwaitingPermission(nil)

    // The other side left while this one was answering a prompt: there is no
    // lesson left to connect to, and the screen is saying so.
    guard sessionViewModel.peerSetupPrompt != .cancelled else {
      logger.info("[ConnectionSetup] the other side left; not connecting qid=\(sessionViewModel.questionId)")
      return
    }

    guard hasMediaCredentials else {
      setupStatusText = LocalizationSupport.localized("Waiting for audio/video connection")
      logger.info("[ConnectionSetup] blocked by missing media credentials qid=\(sessionViewModel.questionId) roomEmpty=\(self.liveKitRoom.isEmpty) tokenEmpty=\(self.liveKitToken.isEmpty) conversationType=\(self.conversationType)")
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
    if let sessionViewModel {
      sessionViewModel.reportConnected()
      if !sessionViewModel.hasLessonStarted {
        // This side is connected, but the lesson starts only once the other
        // side is too, and both go into it together. Until then this screen
        // stays up, and is where anything holding the other side up is said.
        setupStatusText = sessionViewModel.waitingForPeerText
        isWaitingForPeer = true
        logger.info("[ConnectionSetup] connected; waiting for the other side qid=\(sessionViewModel.questionId)")
        return
      }
    }
    enterSession()
  }

  private func enterSession() {
    isWaitingForPeer = false
    setupStatusText = LocalizationSupport.localized("Session connected")
    didStartSession = true
    notifySessionStartedIfNeeded()
  }

  /// Holds this side on the connecting screen until the lesson has started —
  /// both sides connected — then goes into it.
  func waitForLessonStart() async {
    while isWaitingForPeer, !Task.isCancelled {
      if sessionViewModel?.hasLessonStarted ?? true {
        logger.info("[ConnectionSetup] both sides connected qid=\(self.sessionViewModel?.questionId ?? "none")")
        enterSession()
        return
      }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
  }

  private func notifySessionStartedIfNeeded() {
    guard !didNotifySessionStarted else { return }
    didNotifySessionStarted = true
    onSessionStarted?()
  }

  func startTimeoutTimer() async {
    guard hasAudio else { return }
    try? await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
    // Connected and waiting on the other side is not a connection that failed.
    if !Task.isCancelled, !isWaitingForPeer {
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
      let state = await capturePermission(kind, asks: true)
      switch kind {
      case .microphone:
        microphoneState = state
      case .camera:
        cameraState = state
      }
      logger.info("[ConnectionSetup] permission button result kind=\(kind.logName) state=\(state.rawValue) qid=\(self.sessionViewModel?.questionId ?? "none")")
      if state == .denied {
        // Off to Settings: the other side hears this one is finishing its
        // setup, and the write lands before the app is left.
        wentToSettings = true
        await sessionViewModel?.announceFinishingSetup()
        PermissionService.shared.openAppSettings()
      }
      if hasRequiredPermissions {
        attempt += 1
      } else {
        isBlockedOnPermissions = true
        if !isFinishingSetupInSettings {
          sessionViewModel?.setSelfAwaitingPermission(missingPermission)
        }
        setupStatusText = permissionBlockedText
      }
    }
  }

  /// Back in the app, perhaps from Settings: a permission turned on there lets
  /// the setup go on without another tap.
  func recheckPermissions() {
    guard isBlockedOnPermissions, !didStartSession else { return }
    if hasAudio { microphoneState = PermissionService.shared.captureStatus(for: .microphone) }
    if hasVideo { cameraState = PermissionService.shared.captureStatus(for: .camera) }
    guard hasRequiredPermissions else { return }
    logger.info("[ConnectionSetup] permissions granted outside the app qid=\(self.sessionViewModel?.questionId ?? "none")")
    retry()
  }

  /// This side is finishing its setup in Settings: it went there from this
  /// screen, or took the lesson on its way there.
  private var isFinishingSetupInSettings: Bool {
    wentToSettings || (sessionViewModel?.finishesSetupInSettings ?? false)
  }

  /// Where one capture permission stands, asking for it when `asks` and it is
  /// still missing. The other side is told before the prompt goes up: they
  /// are left waiting while it is on screen, with no other way to know why.
  /// A side finishing its setup in Settings has already told them that instead.
  private func capturePermission(_ kind: CapturePermissionKind, asks: Bool) async -> PermissionState {
    let current = PermissionService.shared.captureStatus(for: kind)
    guard asks, !current.isGranted else { return current }
    if !isFinishingSetupInSettings {
      sessionViewModel?.setSelfAwaitingPermission(kind)
    }
    return await PermissionService.shared.requestCapturePermission(for: kind)
  }

  /// The first permission this lesson still lacks.
  private var missingPermission: CapturePermissionKind? {
    if hasAudio, !microphoneState.isGranted { return .microphone }
    if hasVideo, !cameraState.isGranted { return .camera }
    return nil
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
