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
  @State var messages: [ChatMessage] = []
  @State var boardStrokes: [BoardStroke] = []
  @State var boardViewports: [String: BoardViewport] = [:]
  @State var lastSentBoardViewport: BoardViewport?
  @State var errorMessage: String?
  @State var isConnecting: Bool
  @State var selectedTab:TAB_TYPE = .CHAT
  @State var hasUnreadChat = false
  @State var hasUnreadBoard = false
  @State var didPrimeMessages = false
  @State var didPrimeBoard = false
  @State var displayDate = Date()
  @State var sessionDetailsRevision = 0
  @State var isBoardMaximized = false
  @State var isMicMuted = false
  @State var isCameraOff = false
  /// What the media session is currently able to do, polled from
  /// `LiveKitService` once a second. Both of these are conditions the lesson
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
  @State var isEndingSession = false
  @State var didRequestLessonEnd = false
  @State var saveBoardIsRemoteInitiated = false
  @State var sessionFrozenDate: Date?
  @State var isTransitioningToText = false
  @State var inputBarHeight: CGFloat = 0
  /// Whether the scrolling chat layout still has its tab strip on screen.
  /// The strip scrolls away with the rest of the chrome, and a badge that
  /// scrolls away with it stops telling anyone anything — so once it is gone
  /// `unreadTabIndicator` stands in for it.
  @State var isSessionTabStripVisible = true
  @FocusState var isMessageFieldFocused: Bool
  let title: String
  let liveKitRoom: String
  let liveKitToken: String
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
    onClose: @escaping @MainActor @Sendable () -> Void
  ) {
    let viewModel = ChatSessionViewModel(questionId: questionId, role: role, initialDetails: initialDetails)
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self._conversationType = State(initialValue: conversationType)
	self._selectedTab = State(initialValue: conversationType == "video" ? .VIDEO : .CHAT)
    self.title = title
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onClose = onClose
  }

  init(viewModel: any ChatSessionViewModeling, title: String, conversationType: String = "text", liveKitRoom: String = "", liveKitToken: String = "", onClose: @escaping @MainActor @Sendable () -> Void) {
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self._conversationType = State(initialValue: conversationType)
    self._selectedTab = State(initialValue: conversationType == "video" ? .VIDEO : .CHAT)
    self.title = title
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onClose = onClose
  }

  var body: some View {
	
    ZStack {
      Group {
        if isConnecting {
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
              liveKitRoom: liveKitRoom,
              liveKitToken: liveKitToken,
              onCancel: onClose,
              onSessionStarted: { @MainActor @Sendable in
                logger.info("[ChatSessionView] setup complete qid=\(viewModel.questionId) role=\(viewModel.role) conversationType=\(conversationType)")
                isConnecting = false
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
      .onChange(of: isConnecting) { _, newValue in
        if !newValue {
          isTransitioningToText = false
          refreshMediaCondition()
        }
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
      viewModel.onMessagesUpdated = { rows in
        let oldCount = messages.count
        let previousMessageIDs = Set(messages.map(\.id))
        let newIncomingMessages = didPrimeMessages
          ? rows.filter { !$0.isMine && !previousMessageIDs.contains($0.id) }
          : []
        if didPrimeMessages,
		   selectedTab != .CHAT,
           rows.count > oldCount,
           rows.suffix(rows.count - oldCount).contains(where: { !$0.isMine }) {
          hasUnreadChat = true
        }
        for message in newIncomingMessages {
          LocalNotificationService.shared.scheduleChatMessage(
            questionId: viewModel.questionId,
            message: message,
            currentRole: viewModel.role
          )
        }
        if newIncomingMessages.contains(where: { ChatBubble.containsFormula($0.text) }) {
          dismissChatInput()
        }
        messages = rows
        didPrimeMessages = true
      }
      viewModel.onBoardStrokesUpdated = { strokes in
        let oldCount = boardStrokes.count
        if didPrimeBoard,
		   selectedTab != .BOARD,
           strokes.count > oldCount,
           strokes.suffix(strokes.count - oldCount).contains(where: { !$0.isMine }) {
          hasUnreadBoard = true
        }
        boardStrokes = strokes
        didPrimeBoard = true
      }
      viewModel.onBoardViewportsUpdated = { viewports in
        boardViewports = viewports
      }
      viewModel.onChatPausedUpdated = { _ in
        let newValue = viewModel.peerChatPaused()
        if peerChatPaused != newValue {
          peerChatPaused = newValue
          applyVideoPauseState()
        }
      }
      viewModel.onErrorUpdated = { error in
        errorMessage = error
      }
      viewModel.onSessionDetailsUpdated = {
        sessionDetailsRevision += 1
        displayDate = Date()
      }
      viewModel.onSessionEnded = {
        if sessionFrozenDate == nil { sessionFrozenDate = Date() }
        if !boardStrokes.isEmpty && !didRequestLessonEnd && !isEndingSession {
          saveBoardIsRemoteInitiated = true
          endSessionPrompt = .saveBoard
        } else {
          closeWithOptionalRating()
        }
      }
#if !os(Android)
      LiveKitService.shared.onTracksUpdated = { @MainActor @Sendable in
        liveKitRevision &+= 1
      }
#endif
      messages = viewModel.messages
      boardStrokes = viewModel.boardStrokes
      boardViewports = viewModel.boardViewports
      didPrimeMessages = true
      didPrimeBoard = true
      errorMessage = viewModel.errorMessage
      isConnecting = viewModel.isConnecting
      isMessageFieldFocused = selectedTab == .CHAT && composerMode == .regular
    }
    .task {
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
      while !Task.isCancelled {
        displayDate = Date()
        refreshMediaCondition()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    .onDisappear {
      if !didRequestLessonEnd, !isConnecting {
        didRequestLessonEnd = true
        Task {
          await viewModel.endLesson()
        }
      } else if isConnecting {
        // Left from the setup screen. The connect it began belongs to
        // LiveKitService and would otherwise carry on with no lesson to join.
        Task {
          await LiveKitService.shared.disconnect()
        }
      }
      viewModel.stop()
    }
    .trackScreen(AnalyticsScreen.chatSession)
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
    }
  }

  func endSessionPromptPrimaryTitle(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return viewModel.endSessionActionLabel
    case .saveBoard:
      return viewModel.saveToGalleryLabel
    }
  }

  func handleEndSessionPrimaryAction(_ prompt: EndSessionPrompt) {
    switch prompt {
    case .confirmEnd:
      // The user confirmed "Are you sure?" — end immediately: freeze the timer
      // now so time stops counting right away, even if a save-board prompt follows.
      if sessionFrozenDate == nil { sessionFrozenDate = Date() }
      if boardStrokes.isEmpty {
        finalizeEndSession()
      } else {
        saveBoardIsRemoteInitiated = false
        endSessionPrompt = .saveBoard
      }
    case .saveBoard:
      endSessionAfterSnapshot(saveToChat: !saveBoardIsRemoteInitiated, saveToGallery: true)
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
    let strokesSnapshot = boardStrokes
    guard !strokesSnapshot.isEmpty else { return }

    let questionId = viewModel.questionId
    let senderRole = viewModel.role

#if canImport(UIKit) && !os(Android)
    let renderSize = CGSize(width: 500, height: 500)
    let logical = WhiteboardView.logicalSize
    let strokeColor = theme.primaryText
    let background = theme.cardBackground

    let snapshot = ZStack {
      background
      ForEach(strokesSnapshot.indices, id: \.self) { index in
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
        let url = try await StorageService.shared.uploadBoardSnapshot(data: data, questionId: questionId)
        let service = ChatSessionService(questionId: questionId)
        try await service.sendImage(downloadURL: url, senderRole: senderRole)
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
    let strokesJson = Self.boardStrokesJson(strokesSnapshot)
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

  static func boardStrokesJson(_ strokes: [BoardStroke]) -> String {
    let rows: [[String: Any]] = strokes.map { stroke in
      ["points": stroke.points.map { ["x": $0.x, "y": $0.y] }]
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

            sessionConditionNotice

            sessionStats

            // The lazy stack drops what scrolls out of it, so composition is
            // the signal: the strip is on screen exactly while it is composed.
            sessionTabs
              .onAppear { isSessionTabStripVisible = true }
              .onDisappear { isSessionTabStripVisible = false }

            if let errorMessage {
              Text(errorMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.accentBackground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            if messages.count == 0 {
              sessionNotice

              ChatThreadEmptyNotice(viewModel: viewModel)
            }

            ForEach(messages) { message in
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
        .onChange(of: messages.count) { _, _ in
          if let last = messages.last {
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

        sessionConditionNotice

        sessionStats

       // originalQuestionBanner

        sessionTabs

        if let errorMessage {
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
			if messages.count == 0 {
			  sessionNotice
			}
            ChatThreadView(messages: messages, now: displayDate, viewModel: viewModel)
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
      strokes: boardStrokes,
      revision: boardRevision,
      onStrokeFinished: { points in
        let boardPoints = points.map { BoardPoint(x: Double($0.x), y: Double($0.y)) }
        boardStrokes = boardStrokes + [viewModel.localStroke(points: boardPoints)]
        viewModel.sendStroke(boardPoints)
      },
      onClear: {
        boardStrokes = []
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
        guard shouldSendBoardViewport(viewport) else { return }
        lastSentBoardViewport = viewport
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
    let remoteTrack = LiveKitService.shared.remoteCameraVideoTrack
    let localTrack = LiveKitService.shared.localCameraVideoTrack
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
      isCameraOff: isCameraOff,
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
          if messages.count == 0 {
            sessionNotice
          }
          ChatThreadView(messages: messages, now: displayDate, viewModel: viewModel)
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
    let remoteTrack = LiveKitService.shared.remoteCameraVideoTrack
    let localTrack = LiveKitService.shared.localCameraVideoTrack
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
        isCameraOff: isCameraOff,
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
    let localTrack = LiveKitService.shared.localCameraVideoTrack
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
    AndroidSelfVideoPreview(isCameraOff: isCameraOff, theme: theme)
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
      if let localTrack, !isCameraOff {
        SwiftUIVideoView(localTrack, layoutMode: .fill, mirrorMode: .mirror)
          .id(ObjectIdentifier(localTrack))
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(theme.videoBackground.opacity(0.6))
          .overlay {
            PlatformIcon(
              systemName: isCameraOff ? "video.slash.fill" : "video.fill",
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

  func toggleMicrophone() {
    let newValue = !isMicMuted
    isMicMuted = newValue
    Task {
      await LiveKitService.shared.setMicrophoneEnabled(!newValue)
    }
  }

  func toggleCamera() {
    let newValue = !isCameraOff
    isCameraOff = newValue
    Task {
      await LiveKitService.shared.setCameraEnabled(!newValue)
    }
  }

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
    let target = messages.last?.id ?? Self.chatInitialScrollID
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
    messages = messages + [viewModel.localMessage(text: trimmed)]
    viewModel.send(trimmed)
  }

  func sendFormula(_ latex: String) {
    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let formulaText = "$$\(trimmed)$$"
    messages = messages + [viewModel.localMessage(text: formulaText)]
    viewModel.sendQuestionFormula(formulaText)
  }

  var boardRevision: String {
    boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  var peerBoardViewport: CGRect? {
    let localRole = viewModel.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let viewport = boardViewports
      .filter({ $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != localRole })
      .map(\.value)
      .sorted(by: { $0.updatedAt > $1.updatedAt })
      .first else {
      return nil
    }
    return CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height)
  }

  func shouldSendBoardViewport(_ viewport: BoardViewport) -> Bool {
    guard let previous = lastSentBoardViewport else { return true }
    let positionDelta = abs(previous.x - viewport.x) + abs(previous.y - viewport.y)
    let sizeDelta = abs(previous.width - viewport.width) + abs(previous.height - viewport.height)
    return positionDelta > 2 || sizeDelta > 2
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
        Text(connectionModeText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(hasVideo ? theme.info : theme.positive)
      }

      Spacer()

      if hasVideo {
        if isStudent {
          headerToggle(
            systemName: isMicMuted ? "mic.slash.fill" : "mic.fill",
            isActive: isMicMuted
          ) {
            toggleMicrophone()
          }
          headerToggle(
            systemName: isCameraOff ? "video.slash.fill" : "video.fill",
            isActive: isCameraOff
          ) {
            toggleCamera()
          }
        } else {
          videoBadge
        }
      } else if hasAudio {
        headerToggle(
          systemName: isMicMuted ? "mic.slash.fill" : "mic.fill",
          isActive: isMicMuted
        ) {
          toggleMicrophone()
        }
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
    if hasAudio, mediaPhase == .failed {
      audioFailedNoticeButton
    } else if hasAudio, mediaPhase == .connecting {
      conditionLine(icon: "mic.fill", text: viewModel.audioConnectingNotice, color: theme.warning)
    } else if hasAudio, mediaQuality == .lost {
      conditionLine(icon: "exclamationmark.triangle.fill", text: viewModel.lostConnectionNotice, color: theme.danger)
    } else if hasAudio, mediaQuality == .poor {
      conditionLine(icon: "exclamationmark.triangle.fill", text: viewModel.weakConnectionNotice, color: theme.warning)
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
    didFallBackToAudioOnly = LiveKitService.shared.didFallBackToAudioOnly
    mediaQuality = LiveKitService.shared.currentMediaQuality()
    peerAwaitingAudio = viewModel.peerMediaPending()

    let phase = LiveKitService.shared.connectionPhase
    if phase != mediaPhase {
      if phase == .connected {
        applyMediaTogglesOnConnect()
      }
      mediaPhase = phase
    }
    // Only a running lesson reports it: the setup screen is still waiting on
    // the answer, and a lesson on its way out has nothing left to say.
    if !isConnecting, !didRequestLessonEnd {
      viewModel.setSelfMediaPending(isAudioPending)
    }
  }

  func retryMediaConnection() {
    LiveKitService.shared.startConnecting(roomName: liveKitRoom, token: liveKitToken, enableVideo: hasVideo)
    mediaPhase = .connecting
  }

  /// A mic or camera toggled off while audio was still connecting had no room
  /// to act on, so it is applied once there is one.
  func applyMediaTogglesOnConnect() {
    guard isMicMuted || isCameraOff else { return }
    let muteMic = isMicMuted
    let cameraOff = isCameraOff
    Task {
      if muteMic { await LiveKitService.shared.setMicrophoneEnabled(false) }
      if cameraOff { await LiveKitService.shared.setCameraEnabled(false) }
    }
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

    switch tab {
    case .CHAT:
      hasUnreadChat = false
      isMessageFieldFocused = composerMode == .regular
    case .BOARD:
      hasUnreadBoard = false
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

    let shouldCameraBeOff = selfChatPaused && peerChatPaused

    if shouldCameraBeOff != isCameraOff {
      isCameraOff = shouldCameraBeOff
      Task {
        await LiveKitService.shared.setCameraEnabled(!shouldCameraBeOff)
      }
    }
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
    case .CHAT: return hasUnreadChat
    case .BOARD: return hasUnreadBoard
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
	  tabButton(id: .CHAT, title: viewModel.chatTabTitle, icon: "bubble.left.fill", showsBadge: hasUnreadChat)
		.background(selectedTab == .CHAT ? theme.accentBackground : Color.clear)
	  tabButton(id: .BOARD, title: viewModel.boardTabTitle, icon: "pencil.and.list.clipboard", showsBadge: hasUnreadBoard)
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
