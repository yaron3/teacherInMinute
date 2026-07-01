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
  @FocusState var isMessageFieldFocused: Bool
  let title: String
  let liveKitRoom: String
  let liveKitToken: String
  let onClose: @MainActor @Sendable () -> Void

  var hasAudio: Bool { conversationType == "audio" || conversationType == "video" }
  var hasVideo: Bool { conversationType == "video" }
  var isStudent: Bool { viewModel.role == "student" }
  var connectionModeText: String {
    if hasVideo { return LocalizationSupport.localized("Connected - Video session") }
    if hasAudio { return LocalizationSupport.localized("Connected - Audio session") }
    return LocalizationSupport.localized("Connected")
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
        if !newValue { isTransitioningToText = false }
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
      while !Task.isCancelled {
        displayDate = Date()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    .onDisappear {
      if !didRequestLessonEnd, !isConnecting {
        didRequestLessonEnd = true
        Task {
          await viewModel.endLesson()
        }
      }
      viewModel.stop()
    }
    .trackScreen(AnalyticsScreen.chatSession)
  }

  func endSessionPromptOverlay(_ prompt: EndSessionPrompt) -> some View {
    ZStack {
      Color.black.opacity(0.35)
        .ignoresSafeArea()

      VStack(spacing: 14) {
        Text(endSessionPromptTitle(prompt))
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)
          .multilineTextAlignment(.center)

        Text(endSessionPromptMessage(prompt))
          .font(.system(size: 13))
          .foregroundStyle(theme.appSecondaryText)
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
            .foregroundStyle(theme.white)
            .background(theme.appPink)
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
                Text(LocalizationSupport.localized("Save to chat only"))
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(theme.appPrimaryText)
                  .frame(maxWidth: .infinity)
                  .frame(height: 42)
                  .background(theme.appGrayBackground)
                  .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              }
              .buttonStyle(.plain)
              .disabled(isEndingSession)
            }

            // End without saving the board anywhere.
            Button {
              finalizeEndSession()
            } label: {
              Text(LocalizationSupport.localized("Don't save"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.appSecondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isEndingSession)
          } else {
            Button {
              endSessionPrompt = nil
            } label: {
              Text(LocalizationSupport.localized("Cancel"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.appSecondaryText)
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
      .background(theme.appCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .padding(.horizontal, 24)
    }
    .zIndex(25)
  }

  var textTransitionOverlay: some View {
    VStack(spacing: 16) {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(theme.appPink)
      Text(LocalizationSupport.localized("Switching to text chat…"))
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.appSecondaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.appCardBackground)
  }

  var ratingPromptOverlay: some View {
    RateSessionView(
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
    if isStudent && durationSeconds >= 30 && !viewModel.teacherId.isEmpty {
      isRatingPromptVisible = true
    } else {
      onClose()
    }
  }

  func endSessionPromptTitle(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return LocalizationSupport.localized("End session?")
    case .saveBoard:
      return LocalizationSupport.localized("Save board to gallery?")
    }
  }

  func endSessionPromptMessage(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return LocalizationSupport.localized("Are you sure you want to end this session?")
    case .saveBoard:
      if saveBoardIsRemoteInitiated {
        return LocalizationSupport.localized("The session ended. Do you want to save the board image to your device gallery?")
      }
      return LocalizationSupport.localized("The board will be saved to the chat. Do you also want to save it to your device gallery?")
    }
  }

  func endSessionPromptPrimaryTitle(_ prompt: EndSessionPrompt) -> String {
    switch prompt {
    case .confirmEnd:
      return LocalizationSupport.localized("End session")
    case .saveBoard:
      return LocalizationSupport.localized("Save to gallery")
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
    let strokeColor = theme.appPrimaryText
    let background = theme.appCardBackground

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

  var sessionBody: some View {
    VStack(spacing: 0) {
      if !isBoardMaximized {
        header

        sessionStats

       // originalQuestionBanner

        sessionTabs

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.appPink)
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
        inputBar
      }

#endif
    }
    .background(theme.appCardBackground)
#if !os(Android)
    .safeAreaInset(edge: .bottom) {
      if selectedTab == .CHAT && !isBoardMaximized {
        inputBar
          .background(theme.appCardBackground)
      }
    }
#endif
  }

  var whiteboard: some View {
    WhiteboardView(
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
    .background(theme.appCardBackground)
  }

  func questionImageTile(url: String) -> some View {
    let minSide: CGFloat = hSizeClass == .regular ? 700 : 500
    return RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(theme.appGrayBackground)
      .frame(maxWidth: CGFloat.infinity)
      .frame(minHeight: minSide)
      .overlay {
        CachedRemoteImage(url: url, contentMode: .fit)
          .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(theme.appBorder, lineWidth: 1)
      }
  }

  var videoFeed: some View {
#if !os(Android)
    let remoteTrack = LiveKitService.shared.remoteCameraVideoTrack
    let localTrack = LiveKitService.shared.localCameraVideoTrack
    return RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(Color.black)
      .overlay {
        ZStack {
          if let remoteTrack {
            SwiftUIVideoView(remoteTrack, layoutMode: .fit)
              .id(ObjectIdentifier(remoteTrack))
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          } else {
            videoPlaceholder(
              icon: "video.fill",
              text: LocalizationSupport.localized("Waiting for video…")
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
    return AndroidVideoFeed(isStudent: isStudent, isCameraOff: isCameraOff, theme: theme)
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
        if peerChatPaused {
          peerPausedPanel
        } else if let remoteTrack {
          SwiftUIVideoView(remoteTrack, layoutMode: .fit)
            .id(ObjectIdentifier(remoteTrack))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
          videoPlaceholder(
            icon: "video.fill",
            text: LocalizationSupport.localized("Waiting for video…")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      if isStudent && !peerChatPaused {
        localPreview(localTrack: localTrack)
          .padding(10)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
    .id(liveKitRevision)
#else
    if peerChatPaused {
      peerPausedPanel
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    } else {
      AndroidVideoFeed(isStudent: isStudent, isCameraOff: isCameraOff, theme: theme)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
#endif
  }

  var peerPausedPanel: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(Color.black.opacity(0.85))
      .overlay {
        VStack(spacing: 10) {
          PlatformIcon(
            systemName: "video.slash.fill",
            size: 30,
            weight: .semibold,
            color: theme.white.opacity(0.9)
          )
          Text(peerPausedMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var peerPausedMessage: String {
    if isStudent {
      return LocalizationSupport.localized("Teacher is reading chat — video paused")
    }
    return LocalizationSupport.localized("Student is reading chat — video paused")
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
    AndroidVideoFeed(isStudent: true, isCameraOff: isCameraOff, theme: theme)
      .frame(width: 96, height: 132)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        color: theme.appSecondaryText
      )
      Text(text)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.appSecondaryText)
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
          .fill(Color.black.opacity(0.6))
          .overlay {
            PlatformIcon(
              systemName: isCameraOff ? "video.slash.fill" : "video.fill",
              size: 18,
              weight: .semibold,
              color: theme.white
            )
          }
      }
    }
    .frame(width: isCompact ? 72 : 96, height: isCompact ? 99 : 132)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(.white.opacity(0.4), lineWidth: 1)
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
        color: isActive ? theme.white : theme.appPrimaryText
      )
      .frame(width: 34, height: 34)
      .background(isActive ? theme.appPink : theme.appGrayBackground)
      .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }

  var videoBadge: some View {
    HStack(spacing: 4) {
      PlatformIcon(systemName: "video.fill", size: 10, weight: .bold, color: theme.white)
      Text(LocalizationSupport.localized("Video"))
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.white)
    }
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(theme.appTeal)
    .clipShape(Capsule())
  }

  var inputBar: some View {
    VStack(spacing: 8) {
      composerModeToggle

      if composerMode == .algebra {
        MathEquationEditorView { latex in
          sendComposed(latex)
        }
        .environment(\.layoutDirection, .leftToRight)
      } else {
        MessageComposer(isFocused: $isMessageFieldFocused) { text in
          sendComposed(text)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
  }

  var composerModeToggle: some View {
    HStack(spacing: 6) {
      composerModePill(title: LocalizationSupport.localized("Regular"), isSelected: composerMode == .regular) {
        composerMode = .regular
        isMessageFieldFocused = true
      }
      composerModePill(title: LocalizationSupport.localized("Algebra"), isSelected: composerMode == .algebra) {
        composerMode = .algebra
        isMessageFieldFocused = false
      }
      Spacer()
    }
  }

  func composerModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      action()
    } label: {
      Text(LocalizationSupport.localized(title))
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(isSelected ? theme.white : theme.appPrimaryText)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(isSelected ? theme.appPurple : theme.appGrayBackground)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  func sendComposed(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    messages = messages + [viewModel.localMessage(text: trimmed)]
    viewModel.send(trimmed)
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
        background: theme.appPinkSoft,
        tint: theme.appPink
      )
        .overlay(alignment: .bottomTrailing) {
          Circle()
            .fill(theme.appGreen)
            .frame(width: 10, height: 10)
            .overlay {
              Circle().stroke(.white, lineWidth: 2)
            }
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(participantName)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)
        Text(connectionModeText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(hasVideo ? theme.appTeal : theme.appGreen)
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
        Text(isEndingSession ? LocalizationSupport.localized("Ending...") : LocalizationSupport.localized("End"))
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .background(theme.red)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isEndingSession)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(theme.appCardBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.appBorder)
        .frame(height: 1)
      }
  }

  var sessionStats: some View {
    HStack(spacing: 0) {
	  PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: theme.appOrange)
		.padding(.top, 2)
		.padding(.trailing, 8)
	  VStack(alignment: .leading, spacing: 0) {
		Text(LocalizationSupport.localized("ORIGINAL QUESTION"))
		  .font(.system(size: 10, weight: .bold))
		  .foregroundStyle(theme.appOrange)
		Text(viewModel.originalQuestion)
		  .font(.system(size: 12, weight: .medium))
		  .foregroundStyle(theme.appPrimaryText)
		  .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)
	  }
	  .frame(maxWidth: .infinity, alignment: .leading)
	  Spacer(minLength: 2)
      VStack(alignment: .trailing, spacing: 2) {
        Text(LocalizationSupport.localized("Session Time"))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
        Text(viewModel.sessionTimeText(at: sessionFrozenDate ?? displayDate))
          .font(.system(size: 28, weight: .heavy, design: .monospaced))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(width: 92, alignment: .trailing)
          .foregroundStyle(theme.appPrimaryText)
        Text(LocalizationSupport.localized("minutes"))
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
      }
      .frame(width: 92, alignment: .trailing)
	  
	  
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(theme.appPinkSoft.opacity(0.45))
  }

  var originalQuestionBanner: some View {
    HStack(alignment: .top, spacing: 10) {
	  PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: theme.appOrange)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 5) {
        Text(LocalizationSupport.localized("ORIGINAL QUESTION"))
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(theme.appOrange)
        Text(viewModel.originalQuestion)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(theme.appPrimaryText)
          .lineSpacing(3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(theme.yellow.opacity(0.14))
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.yellow.opacity(0.45)).frame(height: 1)
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

    let shouldCameraBeOff = selfChatPaused || peerChatPaused

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
#if canImport(UIKit) && !os(Android)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
  }

  var sessionTabs: some View {
    HStack(spacing: 0) {
	  tabButton(id: .CHAT, title: LocalizationSupport.localized("Chat"), icon: "bubble.left.fill", showsBadge: hasUnreadChat)
	  tabButton(id: .BOARD, title: LocalizationSupport.localized("Board"), icon: "pencil.and.list.clipboard", showsBadge: hasUnreadBoard)
      if hasVideo {
		tabButton(id: .VIDEO, title: LocalizationSupport.localized("Video"), icon: "video.fill", showsBadge: false)
      }
      if !viewModel.questionPhotoUrls.isEmpty {
        tabButton(id: .IMAGES, title: LocalizationSupport.localized("Images"), icon: "photo.fill", showsBadge: false)
      }
    }
    .frame(height: 40)
    .background(theme.appCardBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.appBorder).frame(height: 1)
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
              color: selectedTab == id ? theme.appPink : theme.appSecondaryText
            )
            if showsBadge {
              Circle()
                .fill(theme.red)
                .overlay {
                  Circle().stroke(theme.appCardBackground, lineWidth: 2)
                }
                .frame(width: 14, height: 14)
                .offset(x: 8, y: -6)
            }
          }
          Text(LocalizationSupport.localized(title))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(showsBadge ? .white : (selectedTab == id ? theme.appPink : theme.appSecondaryText))
            .padding(.horizontal, showsBadge ? 18 : 0)
            .padding(.vertical, showsBadge ? 3 : 0)
            .background {
              if showsBadge {
                Capsule().fill(theme.red)
				  .frame(height: 28)
              }
            }
        }
        Rectangle()
          .fill(selectedTab == id ? theme.appPink : Color.clear)
          .frame(height: 2)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  var sessionNotice: some View {
    Text(viewModel.sessionNoticeText)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(theme.appOrange)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(theme.yellow.opacity(0.18))
      .clipShape(Capsule())
      .overlay {
        Capsule().stroke(theme.yellow.opacity(0.55), lineWidth: 1)
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
#Preview {
  ChatSessionView(
	viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher"),
	title: "Student",
	onClose: {}
  )
}

#Preview {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: false),
      title: "Student",
      onClose: {}
    )
}

#Preview {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: true),
      title: "Student",
      onClose: {}
    )
}
#endif
