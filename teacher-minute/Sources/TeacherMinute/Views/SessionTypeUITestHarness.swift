//
//  SessionTypeUITestHarness.swift
//  teacher-minute
//
//  A lesson screen with no lesson behind it, for the UI test of switching the
//  session type. A real lesson needs a teacher to accept a real question, and
//  a test must never send one — dispatch reaches real teachers.
//
//  Opened by launching with `-uiTestSessionTypeSwitch`. Debug iOS builds only.
//

#if DEBUG && !os(Android)
import SwiftUI

struct SessionTypeUITestHarness: View {
  static let launchArgument = "-uiTestSessionTypeSwitch"

  static var isRequested: Bool {
    ProcessInfo.processInfo.arguments.contains(launchArgument)
  }

  /// With `-uiTestBoardTeacher` this side is the teacher, who may rub out the
  /// other side's strokes too.
  static let teacherArgument = "-uiTestBoardTeacher"

  @State var viewModel = MockChatSessionViewModel(
    role: ProcessInfo.processInfo.arguments.contains(teacherArgument) ? "teacher" : "student",
    conversationType: "text"
  )
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      ChatSessionView(
        viewModel: viewModel,
        title: "UI test",
        conversationType: "text"
      ) {}

      // Test-only controls standing in for the other participant. The copy is
      // never shown to a user, so it is not localized.
      HStack(spacing: 8) {
        peerButton("text")
        peerButton("audio")
        peerButton("video")
        Button {
          viewModel.simulatePeerMediaState(MediaDeviceState(micMuted: true, cameraOff: true))
        } label: {
          Text(verbatim: "Peer: off")
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("uitest_peer_media_off")
        Button {
          viewModel.hasUnreadBoard = true
        } label: {
          Text(verbatim: "Board")
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("uitest_peer_board")
        Button {
          viewModel.boardStrokes.append(Self.peerStroke(id: "peer-\(viewModel.boardStrokes.count)"))
        } label: {
          Text(verbatim: "Draw")
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("uitest_peer_draw")
      }
      .padding(8)
      .overlay(alignment: .topLeading) {
        // How many strokes the board holds, for the eraser's test to read.
        Text(verbatim: "\(viewModel.boardStrokes.count)")
          .font(.system(size: 1))
          .opacity(0.01)
          .accessibilityIdentifier("uitest_board_stroke_count")
      }
      .background(AppTheme(colorScheme: colorScheme).cardBackground)
    }
  }

  /// A line by the other side straight across the whole board, a sixth of the
  /// way down the phone's opening view of it, so a vertical sweep there
  /// crosses it wherever the board is scrolled sideways.
  static func peerStroke(id: String) -> BoardStroke {
    BoardStroke(
      id: id,
      points: stride(from: 0.0, through: 2000.0, by: 100.0).map { BoardPoint(x: $0, y: 150) },
      createdAt: Date().timeIntervalSince1970 * 1000,
      isMine: false
    )
  }

  func peerButton(_ conversationType: String) -> some View {
    Button {
      viewModel.simulatePeerConversationType(conversationType)
    } label: {
      Text(verbatim: "Peer: \(conversationType)")
        .font(.system(size: 11, weight: .semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("uitest_peer_switch_\(conversationType)")
  }
}
#endif
