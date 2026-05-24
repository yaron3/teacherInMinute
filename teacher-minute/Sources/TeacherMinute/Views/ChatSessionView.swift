import SwiftUI
#if !os(Android)
import LiveKit
#else
import SkipBridge
#endif

enum ChatComposerMode {
  case regular
  case algebra
}

struct ChatSessionView: View {
  @State var viewModel: any ChatSessionViewModeling
  @State var draft = ""
  @State var composerMode: ChatComposerMode = .regular
  @State var messages: [ChatMessage] = []
  @State var boardStrokes: [BoardStroke] = []
  @State var errorMessage: String?
  @State var isConnecting: Bool
  @State var selectedTab = "chat"
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
  @State var conversationType: String
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
    self._selectedTab = State(initialValue: conversationType == "video" ? "video" : "chat")
    self.title = title
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onClose = onClose
  }

  init(viewModel: any ChatSessionViewModeling, title: String, conversationType: String = "text", liveKitRoom: String = "", liveKitToken: String = "", onClose: @escaping @MainActor @Sendable () -> Void) {
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self._conversationType = State(initialValue: conversationType)
    self._selectedTab = State(initialValue: conversationType == "video" ? "video" : "chat")
    self.title = title
    self.liveKitRoom = liveKitRoom
    self.liveKitToken = liveKitToken
    self.onClose = onClose
  }

  var body: some View {
    Group {
      if isConnecting {
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
            conversationType = "text"
          } : nil
        )
      } else {
        sessionBody
      }
    }
    .background(Color(.systemBackground))
    .task {
      viewModel.onMessagesUpdated = { rows in
        let oldCount = messages.count
        if didPrimeMessages,
           selectedTab != "chat",
           rows.count > oldCount,
           rows.suffix(rows.count - oldCount).contains(where: { !$0.isMine }) {
          hasUnreadChat = true
        }
        messages = rows
        didPrimeMessages = true
      }
      viewModel.onBoardStrokesUpdated = { strokes in
        let oldCount = boardStrokes.count
        if didPrimeBoard,
           selectedTab != "photos",
           strokes.count > oldCount,
           strokes.suffix(strokes.count - oldCount).contains(where: { !$0.isMine }) {
          hasUnreadBoard = true
        }
        boardStrokes = strokes
        didPrimeBoard = true
      }
      viewModel.onErrorUpdated = { error in
        errorMessage = error
      }
      viewModel.onSessionDetailsUpdated = {
        sessionDetailsRevision += 1
        displayDate = Date()
      }
      viewModel.onSessionEnded = {
        onClose()
      }
#if !os(Android)
      LiveKitService.shared.onTracksUpdated = { @MainActor @Sendable in
        liveKitRevision &+= 1
      }
#endif
      messages = viewModel.messages
      boardStrokes = viewModel.boardStrokes
      didPrimeMessages = true
      didPrimeBoard = true
      errorMessage = viewModel.errorMessage
      isConnecting = viewModel.isConnecting
      isMessageFieldFocused = true
    }
    .task {
      while !Task.isCancelled {
        displayDate = Date()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    .onDisappear {
      viewModel.stop()
    }
    .trackScreen(AnalyticsScreen.chatSession)
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
        } else if selectedTab == "chat" {
          VStack(spacing: 0) {
            sessionNotice
            ChatThreadView(messages: messages, now: displayDate, viewModel: viewModel)
          }
        } else if selectedTab == "video" {
          videoFeed
        } else {
          whiteboard
        }
      }
      .frame(maxHeight: .infinity)

#if os(Android)
      if !isBoardMaximized {
        inputBar
      }

#endif
    }
    .background(theme.appCardBackground)
#if !os(Android)
    .safeAreaInset(edge: .bottom) {
      if !isBoardMaximized {
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
      isMaximized: $isBoardMaximized
    )
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
    .frame(width: 96, height: 132)
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
        ChatInputBar(text: $draft, isFocused: $isMessageFieldFocused) {
          let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !text.isEmpty else { return }
          draft = ""
          sendComposed(text)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
  }

  var composerModeToggle: some View {
    HStack(spacing: 6) {
      composerModePill(title: "Regular", isSelected: composerMode == .regular) {
        composerMode = .regular
        isMessageFieldFocused = true
      }
      composerModePill(title: "Algebra", isSelected: composerMode == .algebra) {
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
        onClose()
        Task {
          await viewModel.endLesson()
        }
      } label: {
        Text(LocalizationSupport.localized("End"))
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .background(theme.red)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
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
        Text(viewModel.sessionTimeText(at: displayDate))
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

  var sessionTabs: some View {
    HStack(spacing: 0) {
      tabButton(id: "chat", title: "Chat", icon: "bubble.left.fill", showsBadge: hasUnreadChat)
      tabButton(id: "photos", title: "Photos", icon: "photo.fill", showsBadge: hasUnreadBoard)
      if hasVideo {
        tabButton(id: "video", title: "Video", icon: "video.fill", showsBadge: false)
      }
    }
    .frame(height: 40)
    .background(theme.appCardBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.appBorder).frame(height: 1)
    }
  }

  func tabButton(id: String, title: String, icon: String, showsBadge: Bool) -> some View {
    Button {
      if id == "photos" {
        isMessageFieldFocused = false
        hasUnreadBoard = false
      } else {
        isMessageFieldFocused = true
        hasUnreadChat = false
      }
      selectedTab = id
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
                .frame(width: 7, height: 7)
                .offset(x: 4, y: -4)
            }
          }
          Text(LocalizationSupport.localized(title))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(selectedTab == id ? theme.appPink : theme.appSecondaryText)
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
