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
  let onClose: () -> Void

  init(
    questionId: String,
    role: String,
    title: String,
    hasAudio: Bool = false,
    initialDetails: ChatSessionDetails? = nil,
    onClose: @escaping () -> Void
  ) {
    let viewModel = ChatSessionViewModel(questionId: questionId, role: role, initialDetails: initialDetails)
    self._viewModel = State(initialValue: viewModel)
    self._isConnecting = State(initialValue: viewModel.isConnecting)
    self.title = title
    self.hasAudio = hasAudio
    self.onClose = onClose
  }

  init(viewModel: any ChatSessionViewModeling, title: String, hasAudio: Bool = false, onClose: @escaping () -> Void) {
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
          .foregroundStyle(Color.appPink)
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
    .background(Color.white)
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
      Circle()
        .fill(Color.appPinkSoft)
        .frame(width: 40, height: 40)
        .overlay {
          PlatformIcon(systemName: "person.crop.circle.fill", size: 24, weight: .semibold, color: .appPink)
        }
        .overlay(alignment: .bottomTrailing) {
          Circle()
            .fill(Color.appGreen)
            .frame(width: 10, height: 10)
            .overlay {
              Circle().stroke(.white, lineWidth: 2)
            }
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(participantName)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Color.appPrimaryText)
        Text("Connected")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appGreen)
      }

      Spacer()

      Button {} label: {
        PlatformIcon(systemName: "mic.fill", size: 13, weight: .bold, color: .appPrimaryText)
          .frame(width: 34, height: 34)
          .background(Color.appGrayBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button {} label: {
        PlatformIcon(systemName: "speaker.wave.2.fill", size: 13, weight: .bold, color: .appPrimaryText)
          .frame(width: 34, height: 34)
          .background(Color.appGrayBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button(action: onClose) {
        Text("End")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .background(Color.red)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.white)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.appBorder)
        .frame(height: 1)
      }
  }

  var sessionStats: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text(viewModel.primaryAmountTitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
        Text(viewModel.primaryAmountText(at: displayDate))
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(Color.appPink)
        Text(viewModel.primaryAmountSubtitle)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(Color.appBorder)
        .frame(width: 1, height: 54)

      VStack(alignment: .trailing, spacing: 4) {
        Text("Session Time")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
        Text(viewModel.sessionTimeText(at: displayDate))
          .font(.system(size: 28, weight: .heavy))
          .foregroundStyle(Color.appPrimaryText)
        Text("minutes")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(Color.appPinkSoft.opacity(0.45))
  }

  var originalQuestionBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: .appOrange)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 5) {
        Text("ORIGINAL QUESTION")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(Color.appOrange)
        Text(viewModel.originalQuestion)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.appPrimaryText)
          .lineSpacing(3)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.yellow.opacity(0.14))
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.yellow.opacity(0.45)).frame(height: 1)
    }
  }

  var sessionTabs: some View {
    HStack(spacing: 0) {
      tabButton(id: "chat", title: "Chat", icon: "bubble.left.fill")
      tabButton(id: "photos", title: "Photos", icon: "photo.fill")
    }
    .frame(height: 40)
    .background(.white)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.appBorder).frame(height: 1)
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
            color: selectedTab == id ? .appPink : .appSecondaryText
          )
          Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(selectedTab == id ? Color.appPink : Color.appSecondaryText)
        }
        Rectangle()
          .fill(selectedTab == id ? Color.appPink : Color.clear)
          .frame(height: 2)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  var sessionNotice: some View {
    Text(viewModel.sessionNoticeText)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(Color.appOrange)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.yellow.opacity(0.18))
      .clipShape(Capsule())
      .overlay {
        Capsule().stroke(Color.yellow.opacity(0.55), lineWidth: 1)
      }
      .padding(.top, 12)
  }
}

struct ConnectionSetupView: View {
  let participantName: String
  let hasAudio: Bool
  var footerText = "Your teacher will join shortly"
  let onCancel: () -> Void
  @State var capsuleRotation = -18.0

  var connectionTitle: String {
    hasAudio ? "Connecting\naudio" : "Connecting"
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 34)

      avatarSection

      connectionCard
        .padding(.horizontal, 16)
        .padding(.top, 42)

      if hasAudio {
        microphonePermissionCard
          .padding(.horizontal, 16)
          .padding(.top, 16)
      }

      Spacer()

      Text(footerText)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.appSecondaryText)

      Button(action: onCancel) {
        Text("Cancel Session")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.appPink)
          .frame(height: 36)
      }
      .buttonStyle(.plain)
      .padding(.bottom, 36)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [Color.white, Color.appPinkSoft.opacity(0.35), Color.white],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  var avatarSection: some View {
    VStack(spacing: 14) {
      Circle()
        .fill(Color.appGrayBackground)
        .frame(width: 70, height: 70)
        .overlay {
          PlatformIcon(systemName: "person.crop.circle.fill", size: 62, color: .appSecondaryText)
        }
        .overlay {
          Circle().stroke(.white, lineWidth: 4)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)

      Text(participantName)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(Color.appPrimaryText)

      HStack(spacing: 4) {
        ForEach(0..<5, id: \.self) { _ in
          PlatformIcon(systemName: "star.fill", size: 11, weight: .bold, color: .yellow)
        }
        Text("4.9")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(Color.appPrimaryText)
        Text("(127 reviews)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }
    }
  }

  var connectionCard: some View {
    HStack(spacing: 22) {
      Capsule()
        .fill(
          LinearGradient(
            colors: [Color.appPink, Color.appPurple],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 62, height: 104)
        .rotationEffect(.degrees(capsuleRotation))
        .overlay {
          PlatformIcon(systemName: "wifi", size: 20, weight: .bold, color: .white)
        }
        .task {
          withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            capsuleRotation = 342.0
          }
        }
	  Spacer()
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          Text(connectionTitle)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.appPrimaryText)
            .lineLimit(2)

          LoadingDotsView()
            .padding(.top, 7)
        }

        Text("Setting up your session")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)

        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.appGrayBackground)
            Capsule()
              .fill(
                LinearGradient(
                  colors: [Color.appPink, Color.appPurple],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: proxy.size.width * 0.66)
          }
        }
        .frame(height: 5)
        .padding(.top, 14)
      }

      Spacer(minLength: 0)
    }
    .padding(28)
    .frame(maxWidth: .infinity, minHeight: 132)
    .background(.white)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  var microphonePermissionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Circle()
          .fill(Color.appOrange.opacity(0.12))
          .frame(width: 34, height: 34)
          .overlay {
            PlatformIcon(systemName: "mic.fill", size: 14, weight: .semibold, color: .appOrange)
          }

        VStack(alignment: .leading, spacing: 6) {
          Text("Microphone Permission")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.appPrimaryText)
          Text("Make sure your microphone is enabled for the best learning experience.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.appSecondaryText)
            .lineSpacing(3)
        }
      }

      Button {} label: {
        HStack(spacing: 8) {
          PlatformIcon(systemName: "checkmark", size: 11, weight: .bold, color: .white)
          Text("Allow Microphone")
            .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(Color.appOrange)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.leading, 52)
    }
    .padding(16)
    .background(Color.appOrange.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.appOrange.opacity(0.28), lineWidth: 1)
    }
  }
}

struct LoadingDotsView: View {
  @State var phase = 0

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<2, id: \.self) { index in
        Circle()
          .fill(Color.appPrimaryText)
          .frame(width: 3, height: 3)
          .opacity(phase == index ? 1 : 0.28)
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 420_000_000)
        phase = (phase + 1) % 2
      }
    }
  }
}

struct ChatThreadView: View {
  let messages: [ChatMessage]
  let now: Date
  let viewModel: any ChatSessionViewModeling

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 8) {
          if messages.isEmpty {
            Text("Start with a text explanation, then use the board below for the math work.")
              .font(.system(size: 13))
              .foregroundStyle(Color.appSecondaryText)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 28)
              .padding(.top, 24)
          }

          ForEach(messages) { message in
            ChatBubble(message: message, timeText: viewModel.messageTimeText(createdAt: message.createdAt, at: now))
              .id(message.id)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .background(Color.appGrayBackground.opacity(0.45))
      .onChange(of: messages.count) { _, _ in
        if let last = messages.last {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

struct ChatBubble: View {
  let message: ChatMessage
  let timeText: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.isMine { Spacer(minLength: 54) }

      if !message.isMine {
        avatar
      }

      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 5) {
        Text(message.text)
          .font(.system(size: 14))
          .foregroundStyle(message.isMine ? .white : Color.appPrimaryText)
          .lineSpacing(3)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .background(message.isMine ? Color.appPink : Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255))
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        Text(timeText)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }

      if message.isMine {
        avatar
      }

      if !message.isMine { Spacer(minLength: 54) }
    }
  }

  var avatar: some View {
    Circle()
      .fill(message.isMine ? Color.appPurpleSoft : Color.appGreenSoft)
      .frame(width: 24, height: 24)
      .overlay {
        PlatformIcon(
          systemName: "person.crop.circle.fill",
          size: 18,
          weight: .semibold,
          color: message.isMine ? .appPurple : .appGreen
        )
      }
  }
}

struct ChatInputBar: View {
  @Binding var text: String
  let isFocused: FocusState<Bool>.Binding
  let send: () -> Void

  var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 10) {
      PlatformIcon(systemName: "photo.fill", size: 15, weight: .semibold, color: .appPrimaryText)
        .frame(width: 36, height: 36)
        .background(Color.appGrayBackground)
        .clipShape(Circle())

      TextField("Message", text: $text)
        .focused(isFocused)
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.appGrayBackground)
        .clipShape(Capsule())

      Button(action: send) {
        PlatformIcon(systemName: "paperplane.fill", size: 15, weight: .bold, color: .white)
          .frame(width: 42, height: 42)
          .background(
            LinearGradient(
              colors: canSend ? [Color.appPink, Color.appPurple] : [Color.appBorder, Color.appBorder],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 10)
  }
}

struct WhiteboardView: View {
  let strokes: [BoardStroke]
  let revision: String
  let onStrokeFinished: ([CGPoint]) -> Void
  let onClear: () -> Void
  @State var activeStroke: [CGPoint] = []

  var visibleStrokes: [[CGPoint]] {
    let remoteStrokes = strokes.map { stroke in
      stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
    }
    return activeStroke.isEmpty ? remoteStrokes : remoteStrokes + [activeStroke]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Board")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Color.appPrimaryText)

        Spacer()

        Button("Clear") {
          activeStroke.removeAll()
          onClear()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.appPink)
      }
      .padding(.horizontal, 16)

      GeometryReader { proxy in
        ZStack {
          Color.white

          if visibleStrokes.isEmpty {
            VStack(spacing: 8) {
              PlatformIcon(systemName: "pencil", size: 22, weight: .semibold, color: .appSecondaryText)
              Text("Use your finger to write or sketch.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appSecondaryText)
            }
          }

          ForEach(visibleStrokes.indices, id: \.self) { index in
            Path { path in
              let points = visibleStrokes[index]
              guard let first = points.first else { return }
              path.move(to: first)
              for point in points.dropFirst() {
                path.addLine(to: point)
              }
            }
            .stroke(Color.appPrimaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          }
        }
        .id(revision)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.appBorder, lineWidth: 1)
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let point = CGPoint(
                x: min(max(value.location.x, 0), proxy.size.width),
                y: min(max(value.location.y, 0), proxy.size.height)
              )
              if activeStroke.isEmpty {
                activeStroke = [point]
              } else {
                activeStroke = activeStroke + [point]
              }
            }
            .onEnded { _ in
              let completedStroke = activeStroke
              activeStroke.removeAll()
              onStrokeFinished(completedStroke)
            }
        )
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .padding(.top, 10)
    .background(Color.appGrayBackground.opacity(0.35))
  }
}

#if os(iOS)
struct TChatSessionView_Previews: PreviewProvider {
  static var previews: some View {
    ChatSessionView(
      viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher"),
      title: "Student",
      onClose: {}
    )
  }
}

struct TChatSessionProgressView_Previews: PreviewProvider {
  static var previews: some View {
	ChatSessionView(
	  viewModel: MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: false),
	  title: "Student",
	  onClose: {}
	)
  }
}
#endif
