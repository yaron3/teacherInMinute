//
//  StudentTutorialStore.swift
//  teacher-minute
//
//  When Instant Teacher opens its tutorial by itself. It does so once per
//  launch until the student taps "Don't show me again" on its last page;
//  Skip, or finishing without that, only closes it until the next launch.
//
//  The choice is the device's, not the account's: a student starts without an
//  account, and the anonymous uid they start with is replaced when they make
//  one, so a per-uid key would bring the tutorial back right after sign-up.
//

import Foundation

@MainActor
enum StudentTutorialStore {
  private static let hiddenKey = "tutorial.student.hidden"

  /// Set once the tutorial has been on screen in this run of the app, so a
  /// rebuilt main screen — after a sign-in, or a language switch — does not
  /// open it a second time.
  private static var wasShownThisLaunch = false

  static var isHidden: Bool {
    UserDefaults.standard.bool(forKey: hiddenKey)
  }

  /// Whether the main screen should open on the tutorial.
  ///
  /// Asking does not use up the launch's one showing: SwiftUI builds the main
  /// screen's view model more than once and keeps only the first, so the
  /// showing is spent by `markShown()` when the tutorial actually appears.
  static var shouldPresentAutomatically: Bool {
    !isHidden && !wasShownThisLaunch
  }

  static func markShown() {
    wasShownThisLaunch = true
  }

  static func hide() {
    UserDefaults.standard.set(true, forKey: hiddenKey)
  }
}
