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

  @State var viewModel = MockChatSessionViewModel(role: "student", conversationType: "text")
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
      }
      .padding(8)
      .background(AppTheme(colorScheme: colorScheme).cardBackground)
    }
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
