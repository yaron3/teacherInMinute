import SwiftUI

struct ChatSessionView: View {
  @State var viewModel: any ChatSessionViewModeling
  @State var draft = ""
  @State var messages: [ChatMessage] = []
  @State var boardStrokes: [BoardStroke] = []
  @State var errorMessage: String?
  @State var isConnecting: Bool
  let title: String
  let hasAudio: Bool
  let onClose: () -> Void

  init(questionId: String, role: String, title: String, hasAudio: Bool = false, onClose: @escaping () -> Void) {
    let viewModel = ChatSessionViewModel(questionId: questionId, role: role)
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
        ConnectionSetupView(participantName: title, hasAudio: hasAudio, onCancel: onClose)
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
      messages = viewModel.messages
      boardStrokes = viewModel.boardStrokes
      errorMessage = viewModel.errorMessage
      isConnecting = viewModel.isConnecting
      viewModel.start()
    }
    .onDisappear {
      viewModel.stop()
    }
  }

  var sessionBody: some View {
    VStack(spacing: 0) {
      header

      ChatThreadView(messages: messages)
        .frame(maxHeight: .infinity)

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appPink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.top, 6)
      }

      ChatInputBar(text: $draft) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages = messages + [viewModel.localMessage(text: text)]
        viewModel.send(text)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 10)

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
        .frame(maxHeight: .infinity)
    }
  }

  var boardRevision: String {
    boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  var header: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color.appPinkSoft)
        .frame(width: 36, height: 36)
        .overlay {
          PlatformIcon(systemName: "bubble.left.and.bubble.right.fill", size: 16, weight: .semibold, color: .appPink)
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Color.appPrimaryText)
        Text("Text session")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appGreen)
      }

      Spacer()

      Button(action: onClose) {
        PlatformIcon(systemName: "xmark", size: 13, weight: .bold, color: .appSecondaryText)
          .frame(width: 36, height: 36)
          .background(Color.appGrayBackground)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.white)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.appBorder)
        .frame(height: 1)
    }
  }
}

struct ConnectionSetupView: View {
  let participantName: String
  let hasAudio: Bool
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

      Text("Your teacher will join shortly")
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
            ChatBubble(message: message)
              .id(message.id)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
      }
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

  var body: some View {
    HStack {
      if message.isMine { Spacer(minLength: 44) }

      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
        Text(message.senderRole.capitalized)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Color.appSecondaryText)

        Text(message.text)
          .font(.system(size: 14))
          .foregroundStyle(message.isMine ? .white : Color.appPrimaryText)
          .padding(.horizontal, 13)
          .padding(.vertical, 9)
          .background(message.isMine ? Color.appPink : Color.appGrayBackground)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }

      if !message.isMine { Spacer(minLength: 44) }
    }
  }
}

struct ChatInputBar: View {
  @Binding var text: String
  let send: () -> Void

  var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 10) {
      TextField("Message", text: $text)
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.appGrayBackground)
        .clipShape(Capsule())

      Button(action: send) {
        PlatformIcon(systemName: "arrow.up", size: 14, weight: .bold, color: .white)
          .frame(width: 42, height: 42)
          .background(canSend ? Color.appPink : Color.appBorder)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 8)
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
