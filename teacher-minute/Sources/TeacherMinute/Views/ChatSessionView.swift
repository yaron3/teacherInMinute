import SwiftUI
#if canImport(UIKit) && !os(Android)
import UIKit
import Photos
#endif
#if !os(Android)
import LiveKit
#else
import SkipBridge
#endif

enum ChatComposerMode {
  case regular
  case algebra
}

enum EndSessionPrompt {
  case confirmEnd, saveBoard
  /// The student's minutes ran out: the session holds here until they buy more
  /// or end the call.
  case outOfMinutes
  /// Composing the short note that goes to the teacher as the call ends.
  case farewell
  /// The teacher's side of the same hold: wait for the student to buy more, or
  /// end the call.
  case studentOutOfMinutes
  /// The other side closed the lesson and left a note. Shown until it is
  /// acknowledged, so it is not swept away with the session.
  case peerFarewell
}

struct ChatSessionView: View {
  private static let chatInitialScrollID = "chatInitialScroll"
  private static let chatBottomScrollID = "chatBottomScroll"
  private static let chatComposerScrollID = "chatComposerScroll"
  
  enum TAB_TYPE: String {
	case CHAT
	case BOARD
	case VIDEO
	case IMAGES
  }
  @State var viewModel: any ChatSessionViewModeling
  @State var composerMode: ChatComposerMode = .regular
  @State var selectedTab:TAB_TYPE = .CHAT
  @State var displayDate = Date()
  @State var isBoardMaximized = false
  /// What the media session is currently able to do, polled from
  /// the view model once a second. Both of these are conditions the lesson
  /// silently carried on through before — a camera that never published, a
  /// connection that is barely holding — and the header now says so.
  @State var didFallBackToAudioOnly = false
  @State var mediaQuality: SessionMediaQuality = .unknown
  /// Where this side's own connect stands, and whether the other side is in
  /// the lesson without audio. Both matter once a student starts by chat and
  /// audio carries on connecting behind the lesson.
  @State var mediaPhase: MediaConnectionPhase = .idle
  @State var peerAwaitingAudio = false
  @State var liveKitRevision = 0
  @State var peerChatPaused = false
  @State var teacherPreviewOffset: CGSize = .zero
  @State var teacherPreviewAccumOffset: CGSize = .zero
  @State var conversationType: String
  @State var isRatingPromptVisible = false
  @State var endSessionPrompt: EndSessionPrompt?
  @State var farewellText = ""
  /// The teacher chose to wait, so the notice stays down until the hold lifts
  /// and the student runs out again.
  @State var teacherIsWaitingForMinutes = false
  /// The note the other side left as they closed the lesson.
  @State var peerFarewellText = ""
  @State var isEndingSession = false
  @State var didRequestLessonEnd = false
  @State var saveBoardIsRemoteInitiated = false
  @State var sessionFrozenDate: Date?
  @State var isTransitioningToText = false
  /// The strip that lets either side switch the lesson between text, audio
  /// and video while it runs.
  @State var isSessionTypePickerVisible = false
  @State var isChangingSessionType = false
  /// Why the last switch did not happen, shown under the header until tapped.
  @State var sessionTypeNotice: String?
  /// The other side moved the lesson up to audio or video, waiting on this
  /// side's yes — a camera or microphone is never turned on without it.
  @State var pendingPeerConversationType: String?
  /// What the other side's setup asks of this one — wait out their permission
  /// prompt, or read that they left — and the permission they are still being
  /// asked for. Mirrored from the view model.
  @State var peerSetupPrompt: PeerSetupPrompt?
  @State var peerAwaitedPermission: CapturePermissionKind?
  @State var inputBarHeight: CGFloat = 0
  /// Whether the scrolling chat layout still has its tab strip on screen.
  /// The strip scrolls away with the rest of the chrome, and a badge that
  /// scrolls away with it stops telling anyone anything — so once it is gone
  /// `unreadTabIndicator` stands in for it.
  @State var isSessionTabStripVisible = true
  @FocusState var isMessageFieldFocused: Bool
  let title: String
  /// Opens the minutes picker without leaving the session. Absent for the
  /// teacher, and for any caller that cannot present it — the hold panel then
  /// offers only ending the call, rather than a button that does nothing.
  let onBuyMinutes: (@MainActor @Sendable () -> Void)?
  let onClose: @MainActor @Sendable () -> Void

  var hasAudio: Bool { conversationType == "audio" || conversationType == "video" }
  var hasVideo: Bool { conversationType == "video" }
  var isStudent: Bool { viewModel.role == "student" }
  /// Audio was asked for but is not up yet: still connecting in the background,
  /// or given up after its retries.
  var isAudioPending: Bool { hasAudio && (mediaPhase == .connecting || mediaPhase == .failed) }
  var connectionModeText: String {
    if isAudioPending { return viewModel.connectedText }
    if hasVideo { return viewModel.connectedVideoText }
    if hasAudio { return viewModel.connectedAudioText }
    return viewModel.connectedText
  }
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.horizontalSizeClass) var hSizeClass
  var isCompact: Bool { hSizeClass != .regular }
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(
    questionId: String,
    role: String,
    title: String,
    conversationType: String = "text",
    liveKitRoom: String = "",
    liveKitToken: String = "",
    initialDetails: ChatSessionDetails? = nil,
    onBuyMinutes: (@MainActor @Sendable () -> Void)? = nil,
    onClose: @escaping @MainActor @Sendable () -> Void
  ) {
    let viewModel = ChatSessionViewModel(
      questionId: questionId,
      role: role,
      initialDetails: initialDetails,
      liveKitRoom: liveKitRoom,
      liveKitToken: liveKitToken
    )
    self._viewModel = State(initialValue: viewModel)
    self._conversationType = State(initialValue: conversationType)
	self._selectedTab = State(initialValue: conversationType == "video" ? .VIDEO : .CHAT)
    self.title = title
    self.onBuyMinutes = onBuyMinutes
    self.onClose = onClose
  }

  init(viewModel: any ChatSessionViewModeling, title: String, conversationType: String = "text", liveKitRoom: String = "", liveKitToken: String = "", onBuyMinutes: (@MainActor @Sendable () -> Void)? = nil, onClose: @escaping @MainActor @Sendable () -> Void) {
    self._viewModel = State(initialValue: viewModel)
    self._conversationType = State(initialValue: conversationType)
    self._selectedTab = State(initialValue: conversationType == "video" ? .VIDEO : .CHAT)
    if !liveKitRoom.isEmpty, !liveKitToken.isEmpty {
      viewModel.liveKitRoom = liveKitRoom
      viewModel.liveKitToken = liveKitToken
    }
    self.title = title
    self.onBuyMinutes = onBuyMinutes
    self.onClose = onClose
  }

  var body: some View {
	
    ZStack {
      Group {
        if viewModel.isInSetup {
          if isTransitioningToText {
            textTransitionOverlay
          } else {
            ConnectionSetupView(
              participantName: participantName,
              // Only the student is waiting on a teacher; a teacher's own
              // rating is not shown back to them here.
              participantTeacherId: isStudent ? viewModel.teacherId : "",
              conversationType: conversationType,
              viewModel: viewModel,
              liveKitRoom: viewModel.liveKitRoom,
              liveKitToken: viewModel.liveKitToken,
              onCancel: { @MainActor @Sendable in
                cancelSetup()
              },
              onSessionStarted: { @MainActor @Sendable in
                // The other side left while this one connected, and the dialog
                // over this screen is saying so.
                guard viewModel.peerSetupPrompt != .cancelled else { return }
                logger.info("[ChatSessionView] setup complete qid=\(viewModel.questionId) role=\(viewModel.role) conversationType=\(conversationType)")
                viewModel.logSessionStarted(conversationType: conversationType)
                viewModel.finishSetup()
              },
              onContinueAsText: isStudent && hasAudio ? { @MainActor @Sendable in
                isTransitioningToText = true
                conversationType = "text"
              } : nil
            )
          }
        } else {
          sessionBody
        }
      }
      .onChange(of: viewModel.isInSetup) { _, isInSetup in
        if !isInSetup {
          isTransitioningToText = false
          refreshMediaCondition()
          followSharedConversationType()
        }
      }

      if isStudent, viewModel.minutesHoldState(at: displayDate) == .warning {
        holdBanner(viewModel.minutesRunningOutNotice)
      } else if !isStudent, viewModel.minutesHoldState(at: displayDate) == .held {
        // Stays up for a teacher who chose to wait, so the paused session
        // explains itself rather than just going quiet.
        holdBanner(viewModel.studentOutOfMinutesTitle)
      }

      if let endSessionPrompt {
        endSessionPromptOverlay(endSessionPrompt)
      }

      if isRatingPromptVisible {
        ratingPromptOverlay
      }
    }
    .background(Color(.systemBackground))
    .task {
      viewModel.onChatPausedUpdated = { _ in
        let newValue = viewModel.peerChatPaused()
        if peerChatPaused != newValue {
          peerChatPaused = newValue
          applyVideoPauseState()
        }
      }
      viewModel.onSessionDetailsUpdated = {
        displayDate = Date()
        followSharedConversationType()
      }
      viewModel.onPeerSetupUpdated = {
        refreshPeerSetup()
      }
      // Before this side connects anything: the other side can leave, or be
      // held up by a permission prompt, while this one is still on its own.
      viewModel.startWatchingPeerSetup()
      viewModel.onSessionEnded = {
        if viewModel.peerSetupPrompt == .cancelled, !didRequestLessonEnd {
          // They left before the lesson started. The dialog says so, and
          // closes the screen once it has been read.
          refreshPeerSetup()
          return
        }
        if sessionFrozenDate == nil { sessionFrozenDate = Date() }
        if let note = viewModel.peerFarewellNote, !note.isEmpty,
           !didRequestLessonEnd, !isEndingSession {
          // They left a note on their way out. Hold the screen open until it
          // has been read — the chat it also lives in is going away with the
          // session, and closing straight away would take the note with it.
          peerFarewellText = note
          endSessionPrompt = .peerFarewell
        } else if !viewModel.boardStrokes.isEmpty && !didRequestLessonEnd && !isEndingSession {
          saveBoardIsRemoteInitiated = true
          endSessionPrompt = .saveBoard
        } else {
          closeWithOptionalRating()
        }
      }
#if !os(Android)
      viewModel.onMediaTracksUpdated = { @MainActor @Sendable in
        liveKitRevision &+= 1
      }
#endif
      viewModel.sessionTabChanged(showsChat: selectedTab == .CHAT, showsBoard: selectedTab == .BOARD)
      isMessageFieldFocused = selectedTab == .CHAT && composerMode == .regular
    }
    .task {
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
      while !Task.isCancelled {
        displayDate = Date()
        refreshMediaCondition()
        refreshMinutesHold()
        refreshPeerSetup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    .onChange(of: viewModel.incomingFormulaCount) { _, _ in
      // A formula from the other side needs the room the keyboard takes.
      dismissChatInput()
    }
    .onDisappear {
      if !didRequestLessonEnd, !viewModel.isInSetup {
        didRequestLessonEnd = true
        Task {
          await viewModel.endLesson()
        }
      } else if viewModel.isInSetup {
        // Left from the setup screen. The connect it began belongs to
        // LiveKitService and would otherwise carry on with no lesson to join.
        Task {
          await viewModel.disconnectMedia()
        }
      }
      viewModel.stop()
    }
    .trackScreen(AnalyticsScreen.chatSession)
    .appDialog(
      viewModel.peerUpgradeTitle(for: pendingPeerConversationType ?? ""),
      isPresented: Binding(
        get: { pendingPeerConversationType != nil },
        set: { if !$0 { pendingPeerConversationType = nil } }
      ),
      message: viewModel.peerUpgradeMessage(for: pendingPeerConversationType ?? ""),
      actions: peerUpgradeActions
    )
    .appDialog(
      viewModel.peerSetupTitle(for: peerSetupPrompt ?? .cancelled),
      isPresented: Binding(
        get: { peerSetupPrompt != nil },
        set: { if !$0 { peerSetupPrompt = nil } }
      ),
      message: viewModel.peerSetupMessage(for: peerSetupPrompt ?? .cancelled),
      actions: peerSetupActions
    )
  }

  /// Built from the prompt as it stands, like `peerUpgradeActions`: the dialog
  /// clears `peerSetupPrompt` before it runs a handler.
  var peerSetupActions: [AppDialogAction] {
    switch peerSetupPrompt {
    case .awaitingPermission:
      return [
        AppDialogAction(viewModel.waitForPeerLabel) {
          viewModel.waitForPeerPermission()
        },
        AppDialogAction(viewModel.cancelSessionLabel, kind: .cancel) {
          cancelSetup()
        }
      ]
    case .cancelled, nil:
      return [
        AppDialogAction(viewModel.okLabel) {
          acknowledgePeerCancelled()
        }
      ]
    }
  }

  /// Mirrors what the session says about the other side's setup. Nothing moves
  /// once this side is on its way out, so a dialog just answered does not come
  /// back on the way.
  func refreshPeerSetup() {
    guard !didRequestLessonEnd else { return }
    let prompt = viewModel.peerSetupPrompt
    if prompt != peerSetupPrompt {
      if prompt != nil { dismissChatInput() }
      peerSetupPrompt = prompt
    }
    let awaited = viewModel.peerAwaitedPermission
    if awaited != peerAwaitedPermission {
      peerAwaitedPermission = awaited
    }
  }

  /// Leaves a lesson that is still connecting — from the setup screen, or from
  /// the question about the other side's permission prompt. The other side is
  /// told why; no rating is asked for a lesson that never happened.
  func cancelSetup() {
    guard !didRequestLessonEnd else { return }
    didRequestLessonEnd = true
    viewModel.cancelSetup()
    onClose()
  }

  /// The other side left before the lesson started, and the user has read it.
  func acknowledgePeerCancelled() {
    guard !didRequestLessonEnd else { return }
    didRequestLessonEnd = true
    viewModel.acknowledgePeerCancelled()
    onClose()
  }

  /// The dialog clears `pendingPeerConversationType` before it runs a
  /// handler, so the type is captured here, as the buttons are built.
  var peerUpgradeActions: [AppDialogAction] {
    let type = pendingPeerConversationType ?? ""
    return [
      AppDialogAction(viewModel.switchSessionTypeLabel) {
        acceptPeerConversationType(type)
      },
      AppDialogAction(viewModel.notNowLabel, kind: .cancel) {
        declinePeerConversationType()
      }
    ]
  }

  func endSessionPromptOverlay(_ prompt: EndSessionPrompt) -> some View {
    ZStack {
      theme.scrim.opacity(0.35)
        .ignoresSafeArea()

      VStack(spacing: 14) {
        Text(endSessionPromptTitle(prompt))
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.primaryText)
          .multilineTextAlignment(.center)

        Text(endSessionPromptMessage(prompt))
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
          .multilineTextAlignment(.center)

        if prompt == .farewell {
          VStack(alignment: .leading, spacing: 6) {
            TextField(viewModel.farewellPlaceholder, text: $farewellText)
              .font(.system(size: 14))
              .foregroundStyle(theme.primaryText)
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(theme.secondaryText.opacity(0.3), lineWidth: 1)
              )
              .onChange(of: farewellText) { _, newValue in
                // Hard-capped rather than validated on send: the student should
                // not compose a note they are then told to shorten.
                if newValue.count > viewModel.farewellMessageMaxLength {
                  farewellText = String(newValue.prefix(viewModel.farewellMessageMaxLength))
                }
              }

            Text(
              viewModel.farewellCharactersLeftText(
                max(0, viewModel.farewellMessageMaxLength - farewellText.count)
              )
            )
            .font(.system(size: 11))
            .foregroundStyle(theme.secondaryText)
          }
        }

        VStack(spacing: 10) {
          Button {
            handleEndSessionPrimaryAction(prompt)
          } label: {
            HStack {
              Spacer()
              if isEndingSession {
                ProgressView()
              } else {
                Text(endSessionPromptPrimaryTitle(prompt))
                  .font(.system(size: 15, weight: .bold))
              }
              Spacer()
            }
            .frame(height: 46)
            // `onAccentText` is white in both schemes, so this fill has to be
            // the solid accent — `accentBackground` is a pale tint meant for
            // surfaces, and left the label unreadable in light mode.
            .foregroundStyle(theme.onAccentText)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(isEndingSession)

          if prompt == .saveBoard {
            // "Save to chat only" is only meaningful for the local flow; when the
            // peer already ended the session the chat copy is saved separately.
            if !saveBoardIsRemoteInitiated {
              Button {
                endSessionAfterSnapshot(saveToChat: true, saveToGallery: false)
              } label: {
                Text(viewModel.saveToChatOnlyLabel)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(theme.primaryText)
                  .frame(maxWidth: .infinity)
                  .frame(height: 42)
                  .background(theme.cardBackground)
                  .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              }
              .buttonStyle(.plain)
              .disabled(isEndingSession)
            }

            // End without saving the board anywhere.
            Button {
              finalizeEndSession()
            } label: {
              Text(viewModel.dontSaveLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isEndingSession)
          } else if prompt == .studentOutOfMinutes {
            Button {
              endSessionPrompt = nil
              requestEndSession()
            } label: {
              Text(viewModel.endTheCallLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isEndingSession)
          } else if prompt == .outOfMinutes {
            // Deliberately no way to dismiss this one: the session is held
            // until the student either buys more minutes or ends the call.
            // Where buying is the primary action, ending is offered here.
            if onBuyMinutes != nil {
              Button {
                endSessionPrompt = .farewell
              } label: {
                Text(viewModel.endTheCallLabel)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(theme.secondaryText)
                  .frame(maxWidth: .infinity)
                  .frame(height: 38)
              }
              .buttonStyle(.plain)
              .disabled(isEndingSession)
            }
          } else if prompt == .peerFarewell {
            // Nothing but OK: there is no decision here, only a note to read.
            EmptyView()
          } else if prompt == .farewell {
            Button {
              endSessionPrompt = .outOfMinutes
            } label: {
              Text(viewModel.cancelLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isEndingSession)
          } else {
            Button {
              endSessionPrompt = nil
            } label: {
              Text(viewModel.cancelLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isEndingSession)
          }
        }
      }
      .padding(18)
      .frame(maxWidth: 340)
      .background(theme.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .padding(.horizontal, 24)
    }
    .zIndex(25)
  }

  var textTransitionOverlay: some View {
    VStack(spacing: 16) {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(theme.accentBackground)
      Text(viewModel.switchingToTextChatText)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.secondaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.cardBackground)
  }

  var ratingPromptOverlay: some View {
    RateSessionView(
      viewModel: viewModel,
      teacherName: viewModel.participantName,
      teacherImageURL: viewModel.participantImageURL,
      subject: viewModel.originalQuestion,
      teacherId: viewModel.teacherId,
      questionId: viewModel.questionId,
      prepareForRating: {
        didRequestLessonEnd = true
        await viewModel.endLesson()
      },
      onFinish: {
        isRatingPromptVisible = false
        onClose()
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .zIndex(30)
  }

  @MainActor
  private func closeWithOptionalRating() {
    endSessionPrompt = nil
    isEndingSession = false
    let durationSeconds = viewModel.sessionDurationSeconds(at: sessionFrozenDate ?? Date())
    if isStudent && durationSeconds >= 30 {
      // The student has completed a real lesson — make them eligible for the
      // post-first-lesson notification permission explanation.
      NotificationPromptStore.markLessonCompleted()
    }
    if !isStudent && durationSeconds >= TeacherDocumentsPromptStore.minimumLessonSeconds {
      // The teacher has completed a lesson longer than a minute — make them
      // eligible for the one-time "finish your verification documents"
      // suggestion (bug #24).
      TeacherDocumentsPromptStore.markLessonCompleted()
    }
    if isStudent && durationSeconds >= 30 && !viewModel.teacherId.isEmpty {
      isRatingPromptVisible = true
    } else {
      onClose()
    }
  }

  func endSessionPromptTitle(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return viewModel.endSessionTitleLabel
    case .saveBoard:
      return viewModel.saveBoardTitleLabel
    case .outOfMinutes:
      return viewModel.outOfMinutesTitle
    case .farewell:
      return viewModel.endTheCallLabel
    case .studentOutOfMinutes:
      return viewModel.studentOutOfMinutesTitle
    case .peerFarewell:
      return viewModel.peerEndedLessonTitle
    }
  }

  func endSessionPromptMessage(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return viewModel.endSessionConfirmMessage
    case .saveBoard:
      if saveBoardIsRemoteInitiated {
        return viewModel.saveBoardRemoteMessage
      }
      return viewModel.saveBoardLocalMessage
    case .outOfMinutes:
      return viewModel.outOfMinutesMessage
    case .farewell:
      return viewModel.farewellPromptMessage
    case .studentOutOfMinutes:
      return viewModel.studentOutOfMinutesMessage
    case .peerFarewell:
      // Their own words, not copy of ours.
      return peerFarewellText
    }
  }

  func endSessionPromptPrimaryTitle(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return viewModel.endSessionActionLabel
    case .saveBoard:
      return viewModel.saveToGalleryLabel
    case .outOfMinutes:
      // Buying is the offer worth leading with; where this caller cannot
      // present the picker, ending the call is the only thing left to do.
      return onBuyMinutes != nil
        ? viewModel.buyMoreMinutesLabel
        : viewModel.endTheCallLabel
    case .farewell:
      return viewModel.sendAndEndLabel
    case .studentOutOfMinutes:
      return viewModel.waitForStudentLabel
    case .peerFarewell:
      return viewModel.okLabel
    }
  }

  func handleEndSessionPrimaryAction(_ prompt: EndSessionPrompt) {
    switch prompt {
    case .confirmEnd:
      // The user confirmed "Are you sure?" — end immediately: freeze the timer
      // now so time stops counting right away, even if a save-board prompt follows.
      if sessionFrozenDate == nil { sessionFrozenDate = Date() }
      if viewModel.boardStrokes.isEmpty {
        finalizeEndSession()
      } else {
        saveBoardIsRemoteInitiated = false
        endSessionPrompt = .saveBoard
      }
    case .saveBoard:
      endSessionAfterSnapshot(saveToChat: !saveBoardIsRemoteInitiated, saveToGallery: true)
    case .outOfMinutes:
      if let onBuyMinutes {
        onBuyMinutes()
      } else {
        endSessionPrompt = .farewell
      }
    case .farewell:
      sendFarewellAndEnd()
    case .studentOutOfMinutes:
      // Waiting: the notice comes down and stays down until the student runs
      // out again. The session is paused for both sides until minutes arrive.
      teacherIsWaitingForMinutes = true
      endSessionPrompt = nil
    case .peerFarewell:
      // Read. Carry on with the ordinary close, board prompt included.
      endSessionPrompt = nil
      if !viewModel.boardStrokes.isEmpty && !isEndingSession {
        saveBoardIsRemoteInitiated = true
        endSessionPrompt = .saveBoard
      } else {
        closeWithOptionalRating()
      }
    }
  }

  /// Raises the hold the moment the student's credit runs out. Driven by the
  /// same once-a-second tick that moves the session timer, so it costs nothing
  /// extra, and it never replaces a prompt the student is already dealing with.
  func refreshMinutesHold() {
    guard !isEndingSession else { return }

    guard viewModel.minutesHoldState(at: displayDate) == .held else {
      // Minutes arrived. Take the hold panels down — but never a farewell the
      // student is in the middle of writing — and let the notice appear again
      // if they run out a second time.
      if endSessionPrompt == .outOfMinutes || endSessionPrompt == .studentOutOfMinutes {
        endSessionPrompt = nil
      }
      teacherIsWaitingForMinutes = false
      return
    }

    guard endSessionPrompt == nil else { return }

    if isStudent {
      dismissChatInput()
      endSessionPrompt = .outOfMinutes
    } else if !teacherIsWaitingForMinutes {
      dismissChatInput()
      endSessionPrompt = .studentOutOfMinutes
    }
  }

  func holdBanner(_ text: String) -> some View {
    VStack {
      Text(text)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(theme.onAccentText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.accent)
        .clipShape(Capsule())
        .padding(.top, 8)
      Spacer()
    }
    .allowsHitTesting(false)
    .zIndex(20)
  }

  /// Sends the parting note and closes the call. Mirrors finalizeEndSession,
  /// which the ordinary End button uses.
  func sendFarewellAndEnd() {
    guard !isEndingSession else { return }
    let note = farewellText
    endSessionPrompt = nil
    isEndingSession = true
    didRequestLessonEnd = true
    if sessionFrozenDate == nil { sessionFrozenDate = Date() }
    Task {
      await viewModel.endLessonWithFarewell(note)
      closeWithOptionalRating()
    }
  }

  func requestEndSession() {
    guard !isEndingSession else { return }
    dismissChatInput()
    endSessionPrompt = .confirmEnd
  }

  func finalizeEndSession() {
    guard !isEndingSession else { return }
    endSessionPrompt = nil
    isEndingSession = true
    didRequestLessonEnd = true
    if sessionFrozenDate == nil { sessionFrozenDate = Date() }
    Task {
      await viewModel.endLesson()
      closeWithOptionalRating()
    }
  }

  @MainActor
  func endSessionAfterSnapshot(saveToChat: Bool, saveToGallery: Bool) {
    guard !isEndingSession else { return }
    isEndingSession = true
    endSessionPrompt = nil
    didRequestLessonEnd = true
    if sessionFrozenDate == nil { sessionFrozenDate = Date() }
    Task {
      await saveBoardSnapshotAndShare(saveToChat: saveToChat, saveToGallery: saveToGallery)
      await viewModel.endLesson()
      closeWithOptionalRating()
    }
  }

  @MainActor
  func saveBoardSnapshotAndShare(saveToChat: Bool, saveToGallery: Bool) async {
    let strokesSnapshot = viewModel.boardStrokes
    guard !strokesSnapshot.isEmpty else { return }

    let questionId = viewModel.questionId
    let senderRole = viewModel.role

#if canImport(UIKit) && !os(Android)
    let renderSize = CGSize(width: 500, height: 500)
    let logical = WhiteboardView.logicalSize
    let background = theme.cardBackground
    let snapshotTheme = theme
    let mine = boardAuthor(isMine: true)
    let theirs = boardAuthor(isMine: false)

    let snapshot = ZStack {
      background
      ForEach(strokesSnapshot.indices, id: \.self) { index in
        let strokeColor = (strokesSnapshot[index].isMine ? mine : theirs).color(theme: snapshotTheme)
        Path { path in
          let points = strokesSnapshot[index].points.map { point in
            CGPoint(
              x: point.x * renderSize.width / logical.width,
              y: point.y * renderSize.height / logical.height
            )
          }
          guard let first = points.first else { return }
          path.move(to: first)
          for point in points.dropFirst() {
            path.addLine(to: point)
          }
        }
        .stroke(strokeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      }
    }
    .frame(width: renderSize.width, height: renderSize.height)

    let renderer = ImageRenderer(content: snapshot)
    renderer.scale = 1
    guard let image = renderer.uiImage,
          let data = image.jpegData(compressionQuality: 0.88) else { return }
    logger.info("[BoardSnapshot] jpeg ready bytes=\(data.count) pixelSize=\(Int(image.size.width))x\(Int(image.size.height))")

    if saveToChat {
      do {
        logger.info("[BoardSnapshot] uploading to chat bytes=\(data.count) qid=\(questionId)")
        try await viewModel.sendBoardSnapshot(data, senderRole: senderRole)
      } catch {
        logger.error("Board snapshot save failed: \(error.localizedDescription)")
      }
    }

    if saveToGallery {
      logger.info("[BoardSnapshot] saving to gallery bytes=\(data.count)")
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
      } completionHandler: { _, error in
        if let error {
          logger.error("Failed to save board snapshot to photo library: \(error.localizedDescription)")
        }
      }
    }
#elseif os(Android)
    let strokesJson = Self.boardStrokesJson(
      strokesSnapshot,
      myAuthor: boardAuthor(isMine: true),
      peerAuthor: boardAuthor(isMine: false)
    )
    let logical = WhiteboardView.logicalSize
    let logicalWidth = Double(logical.width)
    let logicalHeight = Double(logical.height)
    let strokeColorArgb = Int32(bitPattern: 0xFF111827 as UInt32)
    let backgroundColorArgb = Int32(bitPattern: 0xFFFFFFFF as UInt32)

    do {
      _ = try await Task.detached(priority: .userInitiated) {
        try AndroidBoardImageBridge.saveBoardSnapshotToChat(
          questionId: questionId,
          senderRole: senderRole,
          strokesJson: strokesJson,
          width: 500,
          height: 500,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          strokeColorArgb: strokeColorArgb,
          backgroundColorArgb: backgroundColorArgb,
          saveToChat: saveToChat,
          saveToGallery: saveToGallery
        )
      }.value
    } catch {
      logger.error("Board snapshot save failed: \(error.localizedDescription)")
    }
#endif
  }

  /// The author of a stroke, seen from this device: the board only ever holds
  /// two people, so "mine or not" plus this side's own role names both.
  func boardAuthor(isMine: Bool) -> BoardAuthor {
    let mine = BoardAuthor.own(role: viewModel.role)
    return isMine ? mine : mine.peer
  }

  /// The Android renderer draws on a fixed white sheet, so the saved image uses
  /// the light-appearance inks whatever the phone is set to.
  static func snapshotArgb(for author: BoardAuthor) -> Int {
    switch author {
    case .teacher: return Int(Int32(bitPattern: 0xFF2563EB as UInt32))
    case .student: return Int(Int32(bitPattern: 0xFF111827 as UInt32))
    }
  }

  static func boardStrokesJson(
    _ strokes: [BoardStroke],
    myAuthor: BoardAuthor,
    peerAuthor: BoardAuthor
  ) -> String {
    let rows: [[String: Any]] = strokes.map { stroke in
      [
        "points": stroke.points.map { ["x": $0.x, "y": $0.y] },
        "color": snapshotArgb(for: stroke.isMine ? myAuthor : peerAuthor)
      ]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: rows),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
  }

  @ViewBuilder var sessionBody: some View {
    if selectedTab == .CHAT && !isBoardMaximized && !hasVideo {
      scrollingChatLayout
    } else {
      standardSessionBody
    }
  }

  /// The chat tab as one scrolling column.
  ///
  /// The header, the pinned question and the tabs used to be fixed chrome above
  /// a thread that was the only thing able to scroll, so on a short viewport —
  /// a small phone with the keyboard up — the composer was pushed off the
  /// bottom with no way to reach it. Everything above the composer now scrolls
  /// together, and the composer stays pinned where it can always be tapped.
  var scrollingChatLayout: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
          // One lazy stack for the whole tab, messages included. It has to be
          // the scroll view's direct content and the bubbles have to be its
          // direct items: on Android the lazy stack is the scrolling
          // LazyColumn, and only it registers the ids that `scrollTo` resolves
          // against — inside a plain stack the scroll-to-newest call is a
          // silent no-op, which is why chat did not follow new messages there.
          LazyVStack(spacing: 0) {
            Color.clear
              .frame(height: 0)
              .id(Self.chatInitialScrollID)

            header

            sessionTypePicker

            sessionConditionNotice

            sessionStats

            // The lazy stack drops what scrolls out of it, so composition is
            // the signal: the strip is on screen exactly while it is composed.
            sessionTabs
              .onAppear { isSessionTabStripVisible = true }
              .onDisappear { isSessionTabStripVisible = false }

            if let errorMessage = viewModel.errorMessage {
              Text(errorMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.accentBackground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            if viewModel.messages.count == 0 {
              sessionNotice

              ChatThreadEmptyNotice(viewModel: viewModel)
            }

            ForEach(viewModel.messages) { message in
              ChatThreadRow(message: message, now: displayDate, viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .id(message.id)
            }

#if os(Android)
            inputBar(scrollProxy: proxy)
              .padding(.top, 8)
              .id(Self.chatComposerScrollID)
#else
            if composerMode == .algebra {
              inputBar(scrollProxy: proxy)
                .padding(.top, 8)
                .id(Self.chatComposerScrollID)

            }
#endif

            Color.clear
              .frame(height: 0)
              .id(Self.chatBottomScrollID)
          }
#if os(Android)
          .padding(.bottom, 10)
#else
          .padding(.bottom, 10)
#endif
        }
        // Claims the space the composer does not take, so the composer is
        // never the thing that overflows.
        .frame(maxHeight: .infinity)
        .onChange(of: viewModel.messages.count) { _, _ in
          if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
        .onChange(of: composerMode) { _, mode in
          scrollChatForKeyboardMode(mode, proxy: proxy)
        }
        .onChange(of: isMessageFieldFocused) { _, focused in
          if focused {
            scrollChatForKeyboardMode(.regular, proxy: proxy)
          }
        }
      }

    }
    .overlay(alignment: .top) {
      unreadTabIndicator
    }
#if !os(Android)
    .safeAreaInset(edge: .bottom) {
      if composerMode == .regular {
        inputBar()
          .background(Color.black.opacity(0.15))
      }
    }
#endif
  }


  var standardSessionBody: some View {
    VStack(spacing: 0) {
      if !isBoardMaximized {
        header

        sessionTypePicker

        sessionConditionNotice

        sessionStats

       // originalQuestionBanner

        sessionTabs

        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.accentBackground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
      }

      Group {
        if isBoardMaximized {
          whiteboard
        } else if hasVideo && isCompact {
          compactVideoSessionLayout
		} else if selectedTab == .CHAT {
          VStack(spacing: 0) {
			if viewModel.messages.count == 0 {
			  sessionNotice
			}
            ChatThreadView(messages: viewModel.messages, now: displayDate, viewModel: viewModel)
          }
		} else if selectedTab == .VIDEO {
          videoFeed
        } else if selectedTab == .IMAGES {
          questionImagesGallery
        } else {
          whiteboard
        }
      }
      .frame(maxHeight: .infinity)

#if os(Android)
      if selectedTab == .CHAT && !isBoardMaximized {
        inputBar()
      }

#endif
    }
    .background(theme.cardBackground)
#if !os(Android)
    .safeAreaInset(edge: .bottom) {
      if selectedTab == .CHAT && !isBoardMaximized {
        inputBar()
          .background(.ultraThinMaterial)
      }
    }
#endif
  }

  var whiteboard: some View {
    WhiteboardView(
      viewModel: viewModel,
      strokes: viewModel.boardStrokes,
      revision: boardRevision,
      onStrokeFinished: { points in
        let boardPoints = points.map { BoardPoint(x: Double($0.x), y: Double($0.y)) }
        viewModel.sendStroke(boardPoints)
      },
      onClear: {
        viewModel.clearBoard()
      },
      onViewportChanged: { rect in
        // Don't emit viewport updates once the session is ending — the RTDB
        // question node is being finalized and a late write would be rejected.
        guard !isEndingSession, sessionFrozenDate == nil else { return }
        let viewport = BoardViewport(
          x: Double(rect.origin.x),
          y: Double(rect.origin.y),
          width: Double(rect.width),
          height: Double(rect.height),
          updatedAt: Date().timeIntervalSince1970 * 1000.0
        )
        viewModel.updateBoardViewport(viewport)
      },
      peerViewport: peerBoardViewport,
      isMaximized: $isBoardMaximized,
      role: viewModel.role
    )
  }

  var questionImagesGallery: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(spacing: 14) {
        ForEach(viewModel.questionPhotoUrls, id: \.self) { url in
          questionImageTile(url: url)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .frame(maxWidth: CGFloat.infinity)
    }
    .background(theme.cardBackground)
  }

  func questionImageTile(url: String) -> some View {
    let minSide: CGFloat = hSizeClass == .regular ? 700 : 500
    return RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(theme.cardBackground)
      .frame(maxWidth: CGFloat.infinity)
      .frame(minHeight: minSide)
      .overlay {
        CachedRemoteImage(url: url, contentMode: .fit)
          .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(theme.controlBorder, lineWidth: 1)
      }
  }

  var videoFeed: some View {
#if !os(Android)
    let remoteTrack = viewModel.remoteCameraVideoTrack
    let localTrack = viewModel.localCameraVideoTrack
    return RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(theme.videoBackground)
      .overlay {
        ZStack {
          if let remoteTrack {
            SwiftUIVideoView(remoteTrack, layoutMode: .fit)
              .id(ObjectIdentifier(remoteTrack))
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          } else {
            videoPlaceholder(
              icon: "video.fill",
              text: viewModel.waitingForVideoText
            )
          }
          if isStudent {
            VStack {
              Spacer()
              HStack {
                Spacer()
                localPreview(localTrack: localTrack)
              }
            }
            .padding(12)
          }
        }
      }
      .padding(16)
      .id(liveKitRevision)
#else
    return AndroidVideoFeed(
      isStudent: isStudent,
      isCameraOff: viewModel.isCameraOff,
      theme: theme,
      waitingForVideoText: viewModel.waitingForVideoText
    )
    .padding(16)
#endif
  }

  @ViewBuilder
  var compactVideoSessionLayout: some View {
    if selectedTab == .CHAT {
      ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
          if viewModel.messages.count == 0 {
            sessionNotice
          }
          ChatThreadView(messages: viewModel.messages, now: displayDate, viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !peerChatPaused {
          draggableSelfPreview
            .padding(12)
        }
      }
    } else if selectedTab == .VIDEO {
      compactBottomVideoStrip
        .frame(maxHeight: .infinity)
    } else {
      VStack(spacing: 0) {
        whiteboard
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        compactBottomVideoStrip
          .frame(height: 220)
      }
    }
  }

  @ViewBuilder
  var compactBottomVideoStrip: some View {
#if !os(Android)
    let remoteTrack = viewModel.remoteCameraVideoTrack
    let localTrack = viewModel.localCameraVideoTrack
    ZStack(alignment: .bottomTrailing) {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        if selfChatPaused && peerChatPaused {
          peerPausedPanel
        } else if let remoteTrack {
          SwiftUIVideoView(remoteTrack, layoutMode: .fit)
            .id(ObjectIdentifier(remoteTrack))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
          videoPlaceholder(
            icon: "video.fill",
            text: viewModel.waitingForVideoText
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      if isStudent && !(selfChatPaused && peerChatPaused) {
        localPreview(localTrack: localTrack)
          .padding(10)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
    .id(liveKitRevision)
#else
    if selfChatPaused && peerChatPaused {
      peerPausedPanel
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    } else {
      AndroidVideoFeed(
        isStudent: isStudent,
        isCameraOff: viewModel.isCameraOff,
        theme: theme,
        waitingForVideoText: viewModel.waitingForVideoText
      )
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
    }
#endif
  }

  var peerPausedPanel: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(theme.videoBackground.opacity(0.85))
      .overlay {
        VStack(spacing: 10) {
          PlatformIcon(
            systemName: "video.slash.fill",
            size: 30,
            weight: .semibold,
            color: theme.onDarkFill.opacity(0.9)
          )
          Text(peerPausedMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.onDarkFill)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var peerPausedMessage: String {
    viewModel.peerPausedMessage
  }

  @ViewBuilder
  var draggableSelfPreview: some View {
#if !os(Android)
    let localTrack = viewModel.localCameraVideoTrack
    localPreview(localTrack: localTrack)
      .offset(teacherPreviewOffset)
      .gesture(
        DragGesture()
          .onChanged { value in
            teacherPreviewOffset = CGSize(
              width: teacherPreviewAccumOffset.width + value.translation.width,
              height: teacherPreviewAccumOffset.height + value.translation.height
            )
          }
          .onEnded { _ in
            teacherPreviewAccumOffset = teacherPreviewOffset
          }
      )
      .id(liveKitRevision)
#else
    // Your own camera, not the whole feed: the feed carries the remote
    // participant, and shrinking it to preview size put them in the window.
    AndroidSelfVideoPreview(isCameraOff: viewModel.isCameraOff, theme: theme)
      .offset(teacherPreviewOffset)
      .gesture(
        DragGesture()
          .onChanged { value in
            teacherPreviewOffset = CGSize(
              width: teacherPreviewAccumOffset.width + value.translation.width,
              height: teacherPreviewAccumOffset.height + value.translation.height
            )
          }
          .onEnded { _ in
            teacherPreviewAccumOffset = teacherPreviewOffset
          }
      )
#endif
  }

  func videoPlaceholder(icon: String, text: String) -> some View {
    VStack(spacing: 10) {
      PlatformIcon(
        systemName: icon,
        size: 32,
        weight: .semibold,
        color: theme.secondaryText
      )
      Text(text)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.secondaryText)
    }
  }

#if !os(Android)
  @ViewBuilder
  func localPreview(localTrack: VideoTrack?) -> some View {
    Group {
      if let localTrack, !viewModel.isCameraOff {
        SwiftUIVideoView(localTrack, layoutMode: .fill, mirrorMode: .mirror)
          .id(ObjectIdentifier(localTrack))
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(theme.videoBackground.opacity(0.6))
          .overlay {
            PlatformIcon(
              systemName: viewModel.isCameraOff ? "video.slash.fill" : "video.fill",
              size: 18,
              weight: .semibold,
              color: theme.onDarkFill
            )
          }
      }
    }
    .frame(width: isCompact ? 72 : 96, height: isCompact ? 99 : 132)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(theme.onDarkFill.opacity(0.4), lineWidth: 1)
    }
  }
#endif

  func headerToggle(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      PlatformIcon(
        systemName: systemName,
        size: 13,
        weight: .bold,
        color: isActive ? theme.primaryText : theme.primaryText
      )
      .frame(width: 34, height: 34)
      .background(isActive ? theme.accentBackground : theme.cardBackground)
      .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }

  var videoBadge: some View {
    HStack(spacing: 4) {
      PlatformIcon(systemName: "video.fill", size: 10, weight: .bold, color: theme.onBrightFill)
      Text(viewModel.videoLabel)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.onBrightFill)
    }
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(theme.info)
    .clipShape(Capsule())
  }

  func inputBar(scrollProxy: ScrollViewProxy? = nil) -> some View {
    VStack(spacing: 8) {
      composerModeToggle(scrollProxy: scrollProxy)

      if composerMode == .algebra {
        MathEquationEditorView { latex in
          sendFormula(latex)
        }
        .environment(\.layoutDirection, .leftToRight)
      } else {
        MessageComposer(placeholder: viewModel.messagePlaceholder,
                        isFocused: $isMessageFieldFocused) { text in
          sendComposed(text)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
  }

  func composerModeToggle(scrollProxy: ScrollViewProxy? = nil) -> some View {
    HStack(spacing: 6) {
      composerModePill(title: viewModel.regularModeLabel, isSelected: composerMode == .regular) {
        composerMode = .regular
        isMessageFieldFocused = true
        if let scrollProxy {
          scrollChatForKeyboardMode(.regular, proxy: scrollProxy)
        }
      }
      composerModePill(title: viewModel.algebraModeLabel, isSelected: composerMode == .algebra) {
        composerMode = .algebra
        // The math keys are the keyboard in this mode. Dropping the focus state
        // is not enough to send the system one away on Android — SkipUI's
        // `.focused(_:)` only ever requests focus — so the pad would sit on top
        // of a keyboard that never left. Same fix as the ask-a-teacher sheet.
        isMessageFieldFocused = false
        SoftKeyboard.dismiss()
        if let scrollProxy {
          scrollChatForKeyboardMode(.algebra, proxy: scrollProxy)
        }
      }
      Spacer()
    }
  }

  func composerModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      action()
    } label: {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(isSelected ? theme.onDarkFill : theme.primaryText)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(isSelected ? theme.accentStrong : theme.cardBackground)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  func scrollChatForKeyboardMode(_ mode: ChatComposerMode, proxy: ScrollViewProxy) {
#if os(Android)
    let target = viewModel.messages.last?.id ?? Self.chatInitialScrollID
    let anchor: UnitPoint = .top
#else
    let target = mode == .algebra ? Self.chatComposerScrollID : Self.chatBottomScrollID
    let anchor: UnitPoint = .bottom
#endif
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 80_000_000)
      withAnimation(.easeInOut(duration: 0.25)) {
        proxy.scrollTo(target, anchor: anchor)
      }
    }
  }

  func sendComposed(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    viewModel.send(trimmed)
  }

  func sendFormula(_ latex: String) {
    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let formulaText = "$$\(trimmed)$$"
    viewModel.sendQuestionFormula(formulaText)
  }

  var boardRevision: String {
    viewModel.boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  var peerBoardViewport: CGRect? {
    let localRole = viewModel.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let viewport = viewModel.boardViewports
      .filter({ $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != localRole })
      .map(\.value)
      .sorted(by: { $0.updatedAt > $1.updatedAt })
      .first else {
      return nil
    }
    return CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height)
  }

  var participantName: String {
    let name = viewModel.participantName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? title : name
  }

  var header: some View {
    HStack(spacing: 12) {
      ProfileAvatarView(
        imageURL: viewModel.participantImageURL,
        size: 40,
        fallbackSystemImage: "person.crop.circle.fill",
        background: theme.accentBackground,
        tint: theme.accent
      )
        .overlay(alignment: .bottomTrailing) {
          Circle()
            .fill(theme.positive)
            .frame(width: 10, height: 10)
            .overlay {
              Circle().stroke(theme.screenBackground, lineWidth: 2)
            }
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(participantName)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.primaryText)
        Button {
          isSessionTypePickerVisible.toggle()
        } label: {
          HStack(spacing: 6) {
            Text(connectionModeText)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(hasVideo ? theme.info : theme.positive)
            Text(viewModel.changeSessionTypeLabel)
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(theme.accent)
          }
        }
        .buttonStyle(.plain)
        .disabled(isEndingSession)
        .accessibilityIdentifier("session_type_change")
      }

      Spacer()

      if hasVideo {
        if isStudent {
          headerToggle(
            systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill",
            isActive: viewModel.isMicMuted
          ) {
            viewModel.toggleMicrophone()
          }
          .accessibilityIdentifier("session_mic_toggle")
          headerToggle(
            systemName: viewModel.isCameraOff ? "video.slash.fill" : "video.fill",
            isActive: viewModel.isCameraOff
          ) {
            viewModel.toggleCamera()
          }
          .accessibilityIdentifier("session_camera_toggle")
        } else {
          videoBadge
        }
      } else if hasAudio {
        headerToggle(
          systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill",
          isActive: viewModel.isMicMuted
        ) {
          viewModel.toggleMicrophone()
        }
        .accessibilityIdentifier("session_mic_toggle")
      }

      Button {
        requestEndSession()
      } label: {
        Text(isEndingSession ? viewModel.endingLabel : viewModel.endLabel)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(theme.onAccentText)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .background(theme.danger)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isEndingSession)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(theme.cardBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.controlBorder)
        .frame(height: 1)
      }
  }

  /// A line under the header for a session that is running, but not in the way
  /// it was asked for. This side's own audio comes first — not connected at all
  /// outranks connected badly — then the other side's, and a camera that never
  /// started, a settled fact of the lesson, comes last.
  @ViewBuilder var sessionConditionNotice: some View {
    if let sessionTypeNotice {
      Button {
        self.sessionTypeNotice = nil
      } label: {
        conditionLine(icon: "exclamationmark.triangle.fill", text: sessionTypeNotice, color: theme.danger)
      }
      .buttonStyle(.plain)
    } else if hasAudio, mediaPhase == .failed {
      audioFailedNoticeButton
    } else if hasAudio, mediaPhase == .connecting {
      conditionLine(icon: "mic.fill", text: viewModel.audioConnectingNotice, color: theme.warning)
    } else if hasAudio, mediaQuality == .lost {
      conditionLine(icon: "exclamationmark.triangle.fill", text: viewModel.lostConnectionNotice, color: theme.danger)
    } else if hasAudio, mediaQuality == .poor {
      conditionLine(icon: "exclamationmark.triangle.fill", text: viewModel.weakConnectionNotice, color: theme.warning)
    } else if let peerAwaitedPermission {
      // The other side is still answering a permission prompt, and this one
      // chose to wait: nothing reaches them until they are through it.
      conditionLine(
        icon: peerAwaitedPermission == .camera ? "video.fill" : "mic.fill",
        text: viewModel.waitingForPeerText,
        color: theme.warning
      )
    } else if hasAudio, peerAwaitingAudio {
      conditionLine(icon: "bubble.left.and.bubble.right.fill", text: viewModel.peerAudioPendingNotice, color: theme.warning)
    } else if hasVideo, didFallBackToAudioOnly {
      conditionLine(icon: "video.slash.fill", text: viewModel.cameraUnavailableNotice, color: theme.warning)
    }
  }

  func conditionLine(icon: String, text: String, color: Color) -> some View {
    HStack(spacing: 8) {
      PlatformIcon(systemName: icon, size: 12, weight: .bold, color: color)

      Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .multilineTextAlignment(.leading)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.warningBackground)
  }

  /// Background audio gave up after its retries; tapping the line starts it again.
  var audioFailedNoticeButton: some View {
    Button {
      retryMediaConnection()
    } label: {
      conditionLine(icon: "arrow.clockwise", text: viewModel.audioFailedNotice, color: theme.danger)
    }
    .buttonStyle(.plain)
  }

  func refreshMediaCondition() {
    guard hasAudio else { return }
    didFallBackToAudioOnly = viewModel.mediaDidFallBackToAudioOnly
    mediaQuality = viewModel.mediaQuality()
    peerAwaitingAudio = viewModel.peerMediaPending()

    let phase = viewModel.mediaConnectionPhase
    if phase != mediaPhase {
      if phase == .connected {
        viewModel.applyMediaTogglesOnConnect()
      }
      mediaPhase = phase
    }
    // Only a running lesson reports it: the setup screen is still waiting on
    // the answer, and a lesson on its way out has nothing left to say.
    if !viewModel.isInSetup, !didRequestLessonEnd {
      viewModel.setSelfMediaPending(isAudioPending)
    }
  }

  // MARK: Session type

  /// Text, audio and video, for either side to move the running lesson between.
  @ViewBuilder var sessionTypePicker: some View {
    if isSessionTypePickerVisible {
      VStack(alignment: .leading, spacing: 8) {
        Text(viewModel.sessionTypeTitle)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.primaryText)

        HStack(spacing: 10) {
          ConversationTypeChip(
            title: viewModel.textSessionTypeLabel,
            isSelected: conversationType == ConversationType.text.rawValue,
            systemIcons: ["bubble.left.fill"],
            accent: .teal
          ) {
            requestConversationType(ConversationType.text.rawValue)
          }
          .accessibilitySelected(conversationType == ConversationType.text.rawValue)
          .accessibilityIdentifier("session_type_text")
          ConversationTypeChip(
            title: viewModel.audioSessionTypeLabel,
            isSelected: conversationType == ConversationType.audio.rawValue,
            systemIcons: ["mic.fill"],
            accent: .teal
          ) {
            requestConversationType(ConversationType.audio.rawValue)
          }
          .accessibilitySelected(conversationType == ConversationType.audio.rawValue)
          .accessibilityIdentifier("session_type_audio")
          ConversationTypeChip(
            title: viewModel.videoSessionTypeLabel,
            isSelected: conversationType == ConversationType.video.rawValue,
            systemIcons: ["video.fill"],
            accent: .teal
          ) {
            requestConversationType(ConversationType.video.rawValue)
          }
          .accessibilitySelected(conversationType == ConversationType.video.rawValue)
          .accessibilityIdentifier("session_type_video")
        }
        .disabled(isChangingSessionType)
        .opacity(isChangingSessionType ? 0.5 : 1)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.cardBackground)
      .overlay(alignment: .bottom) {
        Rectangle().fill(theme.controlBorder).frame(height: 1)
      }
    }
  }

  /// This side picked a new medium: make sure the device allows it, tell the
  /// other side, then switch.
  func requestConversationType(_ type: String) {
    guard type != conversationType, !isChangingSessionType else {
      isSessionTypePickerVisible = false
      return
    }
    isChangingSessionType = true
    sessionTypeNotice = nil
    Task {
      defer { isChangingSessionType = false }
      if let error = await viewModel.requestConversationType(type) {
        sessionTypeNotice = error
        return
      }
      isSessionTypePickerVisible = false
      await applyConversationType(type)
    }
  }

  /// Follows a switch the other side made. Dropping media happens straight
  /// away; picking it up waits for this side to agree.
  func followSharedConversationType() {
    let change = viewModel.sharedConversationTypeChange(
      current: conversationType,
      canFollow: !viewModel.isInSetup && !didRequestLessonEnd
    )
    switch change {
    case .none:
      break
    case .apply(let type):
      pendingPeerConversationType = nil
      Task { await applyConversationType(type) }
    case .askToFollow(let type):
      pendingPeerConversationType = type
    }
  }

  func acceptPeerConversationType(_ type: String) {
    pendingPeerConversationType = nil
    Task {
      if let error = await viewModel.prepareMedia(for: type) {
        sessionTypeNotice = error
        declinePeerConversationType()
        return
      }
      await applyConversationType(type)
    }
  }

  /// Stays on the current medium. Without audio of its own, this side says so,
  /// and the other side is told to use the chat.
  func declinePeerConversationType() {
    pendingPeerConversationType = nil
    if !hasAudio {
      viewModel.setSelfMediaPending(true)
    }
  }

  /// Moves this side's media to `type`: joins the room, turns the camera on or
  /// off, or leaves the room for a text-only lesson.
  func applyConversationType(_ type: String) async {
    guard let target = ConversationType(rawValue: type), type != conversationType else { return }

    if target.requiresMic, !(await viewModel.ensureMediaCredentials()) {
      sessionTypeNotice = viewModel.mediaCredentialsFailedNotice
      viewModel.setSelfMediaPending(true)
      return
    }
    guard !didRequestLessonEnd else { return }

    logger.info("[ChatSessionView] applying conversation type qid=\(viewModel.questionId) role=\(viewModel.role) from=\(conversationType) to=\(type)")
    conversationType = type
    viewModel.resetMediaToggles()

    guard target.requiresMic else {
      mediaPhase = .idle
      mediaQuality = .unknown
      didFallBackToAudioOnly = false
      peerAwaitingAudio = false
      viewModel.setSelfMediaPending(false)
      if selectedTab == .VIDEO {
        selectSessionTab(.CHAT)
      } else {
        applyVideoPauseState()
      }
      await viewModel.switchMedia(to: target)
      return
    }

    let wasJoining = viewModel.mediaConnectionPhase == .connecting || viewModel.mediaConnectionPhase == .connected
    Task { await viewModel.switchMedia(to: target) }
    if !wasJoining {
      mediaPhase = .connecting
    }

    if target.requiresCamera {
      selectSessionTab(.VIDEO)
    } else if selectedTab == .VIDEO {
      selectSessionTab(.CHAT)
    } else {
      applyVideoPauseState()
    }
  }

  func retryMediaConnection() {
    viewModel.connectMedia(enableVideo: hasVideo)
    mediaPhase = .connecting
  }

  var sessionStats: some View {
    HStack(spacing: 0) {
	  PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: theme.warning)
		.padding(.top, 2)
		.padding(.trailing, 8)
	  VStack(alignment: .leading, spacing: 0) {
		Text(viewModel.originalQuestionLabel)
		  .font(.system(size: 10, weight: .bold))
		  .foregroundStyle(theme.warning)
            FormulaAwareText(
              text: viewModel.originalQuestion,
              textColor: theme.primaryText,
              font: .system(size: 12, weight: .medium),
              lineSpacing: 3,
              formulaMinWidth: 160,
              formulaMaxWidth: 260
            )
              .frame(maxWidth: .infinity, alignment: .leading)
	  }
	  .frame(maxWidth: .infinity, alignment: .leading)
	  Spacer(minLength: 2)
      VStack(alignment: .trailing, spacing: 2) {
        Text(viewModel.sessionTimeLabel)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.secondaryText)
        Text(viewModel.sessionTimeText(at: sessionFrozenDate ?? displayDate))
          .font(.system(size: 28, weight: .heavy, design: .monospaced))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(width: 92, alignment: .trailing)
          .foregroundStyle(theme.primaryText)
        Text(viewModel.minutesLabel)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(theme.secondaryText)
      }
      .frame(width: 92, alignment: .trailing)
	  
	  
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
  }

  var originalQuestionBanner: some View {
    HStack(alignment: .top, spacing: 10) {
	  PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: theme.warning)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 5) {
        Text(viewModel.originalQuestionLabel)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(theme.warning)
        FormulaAwareText(
          text: viewModel.originalQuestion,
          textColor: theme.primaryText,
          font: .system(size: 12, weight: .medium),
          lineSpacing: 3,
          formulaMinWidth: 160,
          formulaMaxWidth: 260
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(theme.warningBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.warningBorder).frame(height: 1)
    }
  }

  func selectSessionTab(_ tab: TAB_TYPE) {
    selectedTab = tab
    viewModel.sessionTabChanged(showsChat: tab == .CHAT, showsBoard: tab == .BOARD)

    switch tab {
    case .CHAT:
      isMessageFieldFocused = composerMode == .regular
    case .BOARD:
      dismissChatInput()
    case .VIDEO:
      dismissChatInput()
    case .IMAGES:
      dismissChatInput()
    }

    applyVideoPauseState()
  }

  var selfChatPaused: Bool {
    hasVideo && selectedTab == .CHAT
  }

  func applyVideoPauseState() {
    guard hasVideo else {
      viewModel.setSelfChatPaused(false)
      return
    }
    viewModel.setSelfChatPaused(selfChatPaused)

    viewModel.setCameraPaused(selfChatPaused && peerChatPaused)
  }

  func dismissChatInput() {
    isMessageFieldFocused = false
    composerMode = .regular
    // Was iOS-only, which left the keyboard up on Android whenever the session
    // wanted the composer out of the way.
    SoftKeyboard.dismiss()
  }

  /// The tabs in the order the strip lays them out. `unreadTabIndicator` walks
  /// this list so its mark lands in the same slot as the badge it stands for,
  /// so the two must keep agreeing about which tabs are present.
  var sessionTabIds: [TAB_TYPE] {
    var ids: [TAB_TYPE] = [.CHAT, .BOARD]
    if hasVideo { ids.append(.VIDEO) }
    if !viewModel.questionPhotoUrls.isEmpty { ids.append(.IMAGES) }
    return ids
  }

  func sessionTabHasUnread(_ id: TAB_TYPE) -> Bool {
    switch id {
    case .CHAT: return viewModel.hasUnreadChat
    case .BOARD: return viewModel.hasUnreadBoard
    case .VIDEO, .IMAGES: return false
    }
  }

  /// Stands in for a badge whose tab has scrolled out of reach: a red rule at
  /// the top of the screen, in the slot the tab itself occupies. Laying it out
  /// as the same row of equal shares as the strip keeps the mark over its own
  /// tab under either reading direction — with the board second it sits right
  /// of centre in English and left of centre in Hebrew, matching the strip.
  @ViewBuilder var unreadTabIndicator: some View {
    if !isSessionTabStripVisible, sessionTabIds.contains(where: { sessionTabHasUnread($0) }) {
      HStack(spacing: 0) {
        ForEach(sessionTabIds, id: \.self) { id in
          Rectangle()
            .fill(sessionTabHasUnread(id) ? theme.danger : Color.clear)
            .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 3)
    }
  }

  var sessionTabs: some View {
    HStack(spacing: 0) {
	  tabButton(id: .CHAT, title: viewModel.chatTabTitle, icon: "bubble.left.fill", showsBadge: viewModel.hasUnreadChat)
		.background(selectedTab == .CHAT ? theme.accentBackground : Color.clear)
	  tabButton(id: .BOARD, title: viewModel.boardTabTitle, icon: "pencil.and.list.clipboard", showsBadge: viewModel.hasUnreadBoard)
		.background(selectedTab == .BOARD ? theme.accentBackground : Color.clear)
      if hasVideo {
		tabButton(id: .VIDEO, title: viewModel.videoTabTitle, icon: "video.fill", showsBadge: false)
		  .background(selectedTab == .VIDEO ? theme.accentBackground : Color.clear)
      }
      if !viewModel.questionPhotoUrls.isEmpty {
        tabButton(id: .IMAGES, title: viewModel.imagesTabTitle, icon: "photo.fill", showsBadge: false)
		  .background(selectedTab == .IMAGES ? theme.accentBackground : Color.clear)
      }
    }
    .frame(height: 40)
    .background(theme.cardBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.controlBorder).frame(height: 1)
    }
  }

  func tabButton(id: TAB_TYPE, title: String, icon: String, showsBadge: Bool) -> some View {
    Button {
      selectSessionTab(id)
    } label: {
      VStack(spacing: 8) {
        HStack(spacing: 6) {
          ZStack(alignment: .topTrailing) {
            PlatformIcon(
              systemName: icon,
              size: 12,
              weight: .semibold,
              color: selectedTab == id ? theme.primaryText : theme.secondaryText
            )
            if showsBadge {
              Circle()
                .fill(theme.danger)
                .overlay {
                  Circle().stroke(theme.cardBackground, lineWidth: 2)
                }
                .frame(width: 14, height: 14)
                .offset(x: 8, y: -6)
            }
          }
          Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(showsBadge ? .white : (selectedTab == id ? theme.primaryText : theme.secondaryText))
            .padding(.horizontal, showsBadge ? 18 : 0)
            .padding(.vertical, showsBadge ? 3 : 0)
            .background {
              if showsBadge {
                Capsule().fill(theme.danger)
				  .frame(height: 28)
              }
            }
        }
        Rectangle()
          .fill(selectedTab == id ? theme.accentBackground : Color.clear)
          .frame(height: 2)
      }
    }
	
    .buttonStyle(.plain)
    .accessibilityIdentifier("session_tab_\(id.rawValue.lowercased())")
    .frame(maxWidth: .infinity)
	
  }

  var sessionNotice: some View {
    Text(viewModel.sessionNoticeText)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(theme.warning)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(theme.warningBackground)
      .clipShape(Capsule())
      .overlay {
        Capsule().stroke(theme.warningBorder, lineWidth: 1)
      }
      .padding(.top, 12)
  }
}

#if os(Android)
private enum AndroidBoardImageBridge {
  private static let saverClass = try! JClass(name: "teacher/minute/AndroidBoardImageSaver")
  private static let saveMethod = saverClass.getStaticMethodID(
    name: "saveBoardSnapshotToChat",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;IIDDIIZZ)Ljava/lang/String;"
  )!

  static func saveBoardSnapshotToChat(
    questionId: String,
    senderRole: String,
    strokesJson: String,
    width: Int32,
    height: Int32,
    logicalWidth: Double,
    logicalHeight: Double,
    strokeColorArgb: Int32,
    backgroundColorArgb: Int32,
    saveToChat: Bool,
    saveToGallery: Bool
  ) throws -> String {
    try jniContext {
      try saverClass.callStatic(
        method: saveMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          senderRole.toJavaParameter(options: [.kotlincompat]),
          strokesJson.toJavaParameter(options: [.kotlincompat]),
          width.toJavaParameter(options: [.kotlincompat]),
          height.toJavaParameter(options: [.kotlincompat]),
          logicalWidth.toJavaParameter(options: [.kotlincompat]),
          logicalHeight.toJavaParameter(options: [.kotlincompat]),
          strokeColorArgb.toJavaParameter(options: [.kotlincompat]),
          backgroundColorArgb.toJavaParameter(options: [.kotlincompat]),
          saveToChat.toJavaParameter(options: [.kotlincompat]),
          saveToGallery.toJavaParameter(options: [.kotlincompat])
        ]
      )
    } as String
  }
}
#endif

#if os(iOS)
#Preview("teacher") {
  ChatSessionView(
	viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher"),
	title: "Student",
	onClose: {}
  )
}

#Preview ("student"){
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "student", isConnecting: false),
      title: "Teacher",
      onClose: {}
    )
}

#Preview ("teacher - connecting"){
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: true),
      title: "Student",
      onClose: {}
    )
}
#endif
