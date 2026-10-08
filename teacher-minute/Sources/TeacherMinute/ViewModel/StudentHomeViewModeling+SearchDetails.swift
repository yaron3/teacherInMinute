//
//  StudentHomeViewModeling+SearchDetails.swift
//  teacher-minute
//
//  What a student tells the teachers while their question is being offered
//  (`SearchDetailsView`): what it is about, why they are stuck, and how they
//  would like to start. Each answer goes out to the teachers as it is given.
//

import Foundation

/// The search's screens, in order.
enum SearchDetailsStep: Int {
  /// What the question is about.
  case topic
  /// Why the student is stuck.
  case struggle
  /// How they would like the lesson to start.
  case start
  /// Nothing left to ask: waiting for a teacher.
  case waiting
}

/// What the student has told the teachers so far, and where they are in
/// telling them. Every question starts afresh.
struct SearchDetails {
  var step: SearchDetailsStep = .topic
  /// A topic the backend matches teachers by, once chosen.
  var topic: String?
  /// Why the student is stuck, once chosen.
  var struggle: String?
  /// "audio" or "video": a start the student chose that waits on the
  /// permission it needs.
  var pendingStart: String?
  /// Why that start could not be had, until the student has read it.
  var startDeniedMessage: String?
}

extension StudentHomeViewModeling {

  // MARK: Search details — the choices

  /// The subjects on offer, in the rows the design sets them in. Each is a
  /// topic the backend matches teachers by (`QUESTION_TOPICS`).
  var searchTopicRows: [[String]] {
    [["geometry", "algebra", "trigonometry"], ["calculus"]]
  }

  /// Why the student is stuck, in the design's rows, as the backend takes
  /// them (`QUESTION_STRUGGLES`).
  var searchStruggleRows: [[String]] {
    [["cant_solve", "other"], ["different_results"], ["repeating_mistake"]]
  }

  /// How the lesson may start.
  var searchStartRows: [[String]] {
    [[ConversationType.text.rawValue, ConversationType.audio.rawValue, ConversationType.video.rawValue]]
  }

  func isSearchTopicChosen(_ topic: String) -> Bool {
    searchDetails.topic == topic
  }

  func isSearchStruggleChosen(_ struggle: String) -> Bool {
    searchDetails.struggle == struggle
  }

  func isSearchStartChosen(_ conversationType: String) -> Bool {
    activeConversationType == conversationType
  }

  /// The subject goes out as soon as it is chosen: the teachers holding the
  /// question who do not teach it are released, and others who do are asked
  /// in their place.
  func chooseSearchTopic(_ topic: String) {
    guard searchDetails.topic != topic else { return }
    searchDetails.topic = topic
    logSearchDetailChosen("topic", value: topic)
    sendSearchDetails(topic: topic, struggle: nil, conversationType: nil)
  }

  func chooseSearchStruggle(_ struggle: String) {
    guard searchDetails.struggle != struggle else { return }
    searchDetails.struggle = struggle
    logSearchDetailChosen("struggle", value: struggle)
    sendSearchDetails(topic: nil, struggle: struggle, conversationType: nil)
  }

  /// Audio needs the microphone, and video the camera as well. While one of
  /// them has not been granted, the choice waits on the permission prompt
  /// (`SearchDetails.pendingStart`) instead of going out.
  func chooseSearchStart(_ conversationType: String) {
    guard conversationType != activeConversationType,
          let type = ConversationType(rawValue: conversationType) else { return }
    if missingSearchPermissions(for: type).isEmpty {
      applySearchStart(conversationType)
    } else {
      searchDetails.pendingStart = conversationType
    }
  }

  /// The prompt's "Check permission": asks for what the waiting start needs —
  /// or, for a permission the system will no longer ask about, opens the
  /// app's settings — and takes the start once it has it.
  func checkSearchStartPermission() async {
    guard let conversationType = searchDetails.pendingStart,
          let type = ConversationType(rawValue: conversationType) else { return }
    for permission in missingSearchPermissions(for: type) {
      let state = await PermissionService.shared.resolveCapturePermission(for: permission)
      guard state.isGranted else {
        AnalyticsService.shared.logEvent(AnalyticsEvent.permissionDenied, parameters: [
          "permission_type": permission == .camera ? "camera" : "microphone",
          "conversation_type": conversationType
        ])
        searchDetails.pendingStart = nil
        searchDetails.startDeniedMessage = type == .video
          ? LocalizationSupport.localized("Microphone and camera access are required for a video session. Enable them in Settings.")
          : LocalizationSupport.localized("Microphone access is required for an audio session. Enable it in Settings.")
        return
      }
    }
    searchDetails.pendingStart = nil
    applySearchStart(conversationType)
  }

  /// "Not now", or a tap beside the prompt: the start stays as it was.
  func declineSearchStartPermission() {
    searchDetails.pendingStart = nil
  }

  func dismissSearchStartDenied() {
    searchDetails.startDeniedMessage = nil
  }

  func openSearchPermissionSettings() {
    searchDetails.startDeniedMessage = nil
    PermissionService.shared.openAppSettings()
  }

  /// "Next": the following screen, and after the last, the wait.
  func advanceSearchDetails() {
    switch searchDetails.step {
    case .topic: searchDetails.step = .struggle
    case .struggle: searchDetails.step = .start
    case .start, .waiting: searchDetails.step = .waiting
    }
  }

  private func missingSearchPermissions(for type: ConversationType) -> [CapturePermissionKind] {
    var missing: [CapturePermissionKind] = []
    if type.requiresMic, PermissionService.shared.captureStatus(for: .microphone) != .granted {
      missing.append(.microphone)
    }
    if type.requiresCamera, PermissionService.shared.captureStatus(for: .camera) != .granted {
      missing.append(.camera)
    }
    return missing
  }

  /// Taken at once on the student's side: a teacher who accepts meanwhile
  /// finds the lesson the student asked for. See `sendSearchDetails` for a
  /// change the backend does not take.
  private func applySearchStart(_ conversationType: String) {
    activeConversationType = conversationType
    logSearchDetailChosen("start", value: conversationType)
    sendSearchDetails(topic: nil, struggle: nil, conversationType: conversationType)
  }

  private func logSearchDetailChosen(_ detail: String, value: String) {
    AnalyticsService.shared.logEvent(AnalyticsEvent.askTeacherDetailChosen, parameters: [
      "detail": detail,
      "value": value
    ])
  }

  // MARK: Search details — copy

  var searchDetailsTitle: String { LocalizationSupport.localized("Tell the teacher") }
  var searchTopicPrompt: String { LocalizationSupport.localized("My question is about:") }
  var searchStrugglePrompt: String { LocalizationSupport.localized("I'm stuck because:") }
  var searchStartPrompt: String { LocalizationSupport.localized("How would you like to start?") }
  var searchNextLabel: String { LocalizationSupport.localized("Next") }
  var checkPermissionLabel: String { LocalizationSupport.localized("Check permission") }
  /// Something to smile at while the wait goes on.
  var searchWaitingJoke: String {
    LocalizationSupport.localized("Math is so spoiled – how can it have so many problems?")
  }

  /// The chips name the subjects as the design does: short, and trigonometry
  /// shortest.
  func searchTopicLabel(_ topic: String) -> String {
    switch topic {
    case "geometry": return LocalizationSupport.localized("Geometry")
    case "algebra": return LocalizationSupport.localized("Algebra")
    case "trigonometry": return LocalizationSupport.localized("Trig")
    case "calculus": return LocalizationSupport.localized("Calculus")
    default: return localizedTopicName(topic)
    }
  }

  func searchStruggleLabel(_ struggle: String) -> String {
    switch struggle {
    case "cant_solve": return LocalizationSupport.localized("I can't solve it")
    case "different_results": return LocalizationSupport.localized("I get a different answer each time")
    case "repeating_mistake": return LocalizationSupport.localized("I keep making the same mistake")
    default: return LocalizationSupport.localized("Other")
    }
  }

  func searchStartLabel(_ conversationType: String) -> String {
    switch conversationType {
    case ConversationType.audio.rawValue: return audioSessionTypeLabel
    case ConversationType.video.rawValue: return videoSessionTypeLabel
    default: return LocalizationSupport.localized("Text only")
    }
  }

  /// The prompt for the current screen.
  var searchDetailsPrompt: String {
    switch searchDetails.step {
    case .topic: return searchTopicPrompt
    case .struggle: return searchStrugglePrompt
    case .start, .waiting: return searchStartPrompt
    }
  }

  /// The character's bubble: what the search is doing, under the animated
  /// dots the scene puts above it — its lines broken by hand, as the bubble
  /// sets them closer than a paragraph.
  var searchBubbleLines: [String] {
    let text: String
    switch searchDetails.step {
    case .topic:
      text = LocalizationSupport.localized("Looking for\na teacher")
    case .struggle:
      text = searchDetails.topic.map { searchFocusText($0) }
        ?? LocalizationSupport.localized("Looking for\na teacher")
    case .start, .waiting:
      text = LocalizationSupport.localized("Updating\ndetails")
    }
    return text.components(separatedBy: "\n")
  }

  /// Each its own sentence: Hebrew joins the subject to its preposition.
  private func searchFocusText(_ topic: String) -> String {
    switch topic {
    case "geometry": return LocalizationSupport.localized("Focusing\non geometry")
    case "algebra": return LocalizationSupport.localized("Focusing\non algebra")
    case "trigonometry": return LocalizationSupport.localized("Focusing\non trig")
    case "calculus": return LocalizationSupport.localized("Focusing\non calculus")
    default: return LocalizationSupport.localized("Looking for\na teacher")
    }
  }

  /// The permission prompt's title, for the start waiting on it.
  var searchPermissionTitle: String {
    searchDetails.pendingStart == ConversationType.video.rawValue
      ? LocalizationSupport.localized("Check video permission")
      : LocalizationSupport.localized("Check audio permission")
  }

  /// The prompt for video, which may be put off with "Not now". Audio's
  /// offers only the check, as designed; a tap beside it still backs out.
  var searchPermissionIsVideo: Bool {
    searchDetails.pendingStart == ConversationType.video.rawValue
  }
}
