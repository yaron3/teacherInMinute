//
//  StudentTutorialUITestHarness.swift
//  teacher-minute
//
//  The tutorial, opened directly over the mock root rather than through the
//  side menu or a first launch. The tutorial has no backend of its own to
//  avoid — it only reads and writes `StudentTutorialStore` and fires
//  analytics — so unlike `SessionTypeUITestHarness` this wraps the real
//  `StudentTutorialViewModel`, not a mock.
//
//  Opened by launching with `-uiTestStudentTutorial`. Debug iOS builds only.
//

#if DEBUG && !os(Android)
import SwiftUI

struct StudentTutorialUITestHarness: View {
  static let launchArgument = "-uiTestStudentTutorial"

  static var isRequested: Bool {
    ProcessInfo.processInfo.arguments.contains(launchArgument)
  }

  /// Flips once the tutorial calls its `onClose`, by Skip or by Let's
  /// start — the same way `MainTabView` drops its own tutorial view model.
  @State private var isClosed = false

  var body: some View {
    if isClosed {
      // Test-only marker: never shown to a user, so not localized.
      Text(verbatim: "closed")
        .accessibilityIdentifier("uitest_tutorial_closed")
    } else {
      StudentTutorialView(viewModel: StudentTutorialViewModel(source: .menu) {
        isClosed = true
      })
    }
  }
}
#endif
