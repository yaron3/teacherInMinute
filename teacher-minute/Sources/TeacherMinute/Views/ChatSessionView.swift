import SwiftUI

struct ChatSessionView: View {
  @State var viewModel: any ChatSessionViewModeling
  @State var draft = ""
  @State var messages: [ChatMessage] = []
  @State var boardStrokes: [BoardStroke] = []
  @State var errorMessage: String?
  @State var isConnecting: Bool
  @State var selectedTab = "chat"
  @State var displayDate = Date()
  @State var sessionDetailsRevision = 0
  @FocusState var isMessageFieldFocused: Bool
  let title: String
  let hasAudio: Bool
  let onClose: @MainActor @Sendable () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(
    questionId: String,
    role: String,
    title: String,
    hasAudio: Bool = false,
    initialDetails: ChatSessionDetails? = nil,
    onClose: @escaping @MainActor @Sendable () -> Void
  ) {
    let viewModel = ChatSessionViewModel(questionId: questionId, role: role, initialDetails: initialDetails)
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self.title = title
    self.hasAudio = hasAudio
    self.onClose = onClose
  }

  init(viewModel: any ChatSessionViewModeling, title: String, hasAudio: Bool = false, onClose: @escaping @MainActor @Sendable () -> Void) {
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self.title = title
    self.hasAudio = hasAudio
    self.onClose = onClose
  }

  var body: some View {
    Group {
      if isConnecting {
        ConnectionSetupView(participantName: participantName, hasAudio: hasAudio, onCancel: onClose)
      } else {
        sessionBody
      }
    }
    .background(Color(.systemBackground))
    .task {
      viewModel.onMessagesUpdated = { rows in
        messages = rows
      }
      viewModel.onBoardStrokesUpdated = { strokes in
        boardStrokes = strokes
      }
      viewModel.onErrorUpdated = { error in
        errorMessage = error
      }
      viewModel.onConnectingUpdated = { value in
        isConnecting = value
      }
      viewModel.onSessionDetailsUpdated = {
        sessionDetailsRevision += 1
        displayDate = Date()
      }
      viewModel.onSessionEnded = {
        onClose()
      }
      messages = viewModel.messages
      boardStrokes = viewModel.boardStrokes
      errorMessage = viewModel.errorMessage
      isConnecting = viewModel.isConnecting
      viewModel.start()
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
  }

  var sessionBody: some View {
    VStack(spacing: 0) {
      header

      sessionStats

      originalQuestionBanner

      sessionTabs

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.appPink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.top, 6)
      }

      Group {
        if selectedTab == "chat" {
          VStack(spacing: 0) {
            sessionNotice
            ChatThreadView(messages: messages, now: displayDate, viewModel: viewModel)
          }
        } else {
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
            }
          )
        }
      }
      .frame(maxHeight: .infinity)

#if os(Android)
      inputBar
#endif
    }
    .background(theme.appCardBackground)
#if !os(Android)
    .safeAreaInset(edge: .bottom) {
      inputBar
        .background(theme.appCardBackground)
    }
#endif
  }

  var inputBar: some View {
    ChatInputBar(text: $draft, isFocused: $isMessageFieldFocused) {
      let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return }
      draft = ""
      messages = messages + [viewModel.localMessage(text: text)]
      viewModel.send(text)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
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
        Text("Connected")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.appGreen)
      }

      Spacer()

      Button {} label: {
        PlatformIcon(systemName: "mic.fill", size: 13, weight: .bold, color: theme.appPrimaryText)
          .frame(width: 34, height: 34)
          .background(theme.appGrayBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button {} label: {
		PlatformIcon(systemName: "speaker.wave.2.fill", size: 13, weight: .bold, color: theme.appPrimaryText)
          .frame(width: 34, height: 34)
          .background(theme.appGrayBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button {
        Task {
          await viewModel.endLesson()
          onClose()
        }
      } label: {
        Text("End")
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
      VStack(alignment: .leading, spacing: 6) {
        Text(viewModel.primaryAmountTitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
        Text(viewModel.primaryAmountText(at: displayDate))
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.appPink)
        Text(viewModel.primaryAmountSubtitle)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(theme.appBorder)
        .frame(width: 1, height: 54)

      VStack(alignment: .trailing, spacing: 4) {
        Text("Session Time")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
        Text(viewModel.sessionTimeText(at: displayDate))
          .font(.system(size: 28, weight: .heavy))
          .foregroundStyle(theme.appPrimaryText)
        Text("minutes")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
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
        Text("ORIGINAL QUESTION")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(theme.appOrange)
        Text(viewModel.originalQuestion)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(theme.appPrimaryText)
          .lineSpacing(3)
      }
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
      tabButton(id: "chat", title: "Chat", icon: "bubble.left.fill")
      tabButton(id: "photos", title: "Photos", icon: "photo.fill")
    }
    .frame(height: 40)
    .background(theme.appCardBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.appBorder).frame(height: 1)
    }
  }

  func tabButton(id: String, title: String, icon: String) -> some View {
    Button {
      if id == "photos" {
        isMessageFieldFocused = false
      }
      selectedTab = id
    } label: {
      VStack(spacing: 8) {
        HStack(spacing: 6) {
          PlatformIcon(
            systemName: icon,
            size: 12,
            weight: .semibold,
            color: selectedTab == id ? theme.appPink : theme.appSecondaryText
          )
          Text(title)
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
struct ChatSessionView_Previews: PreviewProvider {
  static var previews: some View {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher"),
      title: "Student",
      onClose: {}
    )
  }
}

struct ChatSessionProgressView_Previews: PreviewProvider {
  static var previews: some View {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: false),
      title: "Student",
      onClose: {}
    )
  }
}

struct ChatSessionConnectingView_Previews: PreviewProvider {
  static var previews: some View {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: true),
      title: "Student",
      onClose: {}
    )
  }
}
#endif
