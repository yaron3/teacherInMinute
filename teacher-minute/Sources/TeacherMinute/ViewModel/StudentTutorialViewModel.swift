//
//  StudentTutorialViewModel.swift
//  teacher-minute
//
//  Instant Teacher's tutorial: what the app is for and the path through it,
//  from asking a question to paying for the minutes it took. The steps on the
//  home screen and in the lesson are shown on screenshots of the app, with
//  numbered callouts on their controls. It opens by
//  itself at launch until the student asks it not to, and from the side
//  menu's Tutorial at any time (see `StudentTutorialStore`).
//

import Foundation
import Observation

@Observable
@MainActor
final class StudentTutorialViewModel {
  /// How the tutorial came to be on screen, for analytics.
  enum Source: String {
    case launch
    case menu
  }

  let source: Source
  private(set) var pageIndex = 0
  /// The last page's "Don't show me again" check box, read when the student
  /// taps Let's start. Off until they tick it.
  var dontShowAgain = false
  /// Called once the tutorial has closed, by any of its ways out.
  private let onClose: () -> Void

  init(source: Source, onClose: @escaping () -> Void) {
    self.source = source
    self.onClose = onClose
  }

  var pages: [StudentTutorialPage] {
    [
      StudentTutorialPage(
        art: .character("home-character"),
        title: welcomeTitle,
        body: welcomeBody
      ),
      StudentTutorialPage(
        art: .screenshot(screenshotName("camera")),
        title: cameraTitle,
        callouts: [
          callout(cameraTabCallout, en: (0.30, 0.08), he: (0.30, 0.08)),
          callout(cameraShutterCallout, en: (0.62, 0.41), he: (0.62, 0.41)),
          callout(cameraBubblesCallout, en: (0.78, 0.68), he: (0.78, 0.68)),
        ]
      ),
      StudentTutorialPage(
        art: .screenshot(screenshotName("attached")),
        title: attachedTitle,
        callouts: [
          callout(attachedPhotoCallout, en: (0.86, 0.43), he: (0.12, 0.43)),
          callout(attachedWordsCallout, en: (0.34, 0.34), he: (0.65, 0.34)),
          callout(attachedFindCallout, en: (0.90, 0.54), he: (0.09, 0.54)),
        ]
      ),
      StudentTutorialPage(
        art: .screenshot(screenshotName("text")),
        title: textTitle,
        callouts: [
          callout(textTabCallout, en: (0.90, 0.08), he: (0.90, 0.08)),
          callout(textAreaCallout, en: (0.31, 0.30), he: (0.65, 0.30)),
          callout(textMathKeyboardCallout, en: (0.69, 0.35), he: (0.31, 0.35)),
        ]
      ),
      StudentTutorialPage(
        art: .character("search-wait-teacher"),
        title: matchTitle,
        body: matchBody
      ),
      StudentTutorialPage(
        art: .screenshot(screenshotName("chat")),
        title: chatTitle,
        callouts: [
          callout(chatMessagesCallout, en: (0.82, 0.30), he: (0.18, 0.28)),
          callout(chatMediaCallout, en: (0.10, 0.86), he: (0.89, 0.86)),
          callout(chatTimerCallout, en: (0.87, 0.86), he: (0.13, 0.86)),
          callout(chatEndCallout, en: (0.82, 0.085), he: (0.18, 0.085)),
        ]
      ),
      StudentTutorialPage(
        art: .screenshot(screenshotName("board")),
        title: boardTitle,
        callouts: [
          callout(boardTabCallout, en: (0.71, 0.08), he: (0.29, 0.08)),
          callout(boardToolsCallout, en: (0.42, 0.19), he: (0.58, 0.19)),
          callout(boardDrawingCallout, en: (0.56, 0.72), he: (0.56, 0.72)),
        ]
      ),
      StudentTutorialPage(
        art: .icon("minutes-timer"),
        title: minutesTitle,
        body: minutesBody
      ),
      StudentTutorialPage(
        art: .icon("brand-menu-activity"),
        title: menuTitle,
        body: menuBody
      ),
    ]
  }

  /// The screenshots are of the app itself, so they come in each language:
  /// Hebrew's run right to left, and its controls sit on the other side.
  private var screenshotsAreHebrew: Bool {
    LocalizationSupport.currentLanguageCode == "he"
  }

  private func screenshotName(_ screen: String) -> String {
    "tutorial-\(screen)-\(screenshotsAreHebrew ? "he" : "en")"
  }

  /// A callout, placed where its control is in the screenshot on screen.
  private func callout(
    _ text: String,
    en: (x: Double, y: Double),
    he: (x: Double, y: Double)
  ) -> StudentTutorialPage.Callout {
    let spot = screenshotsAreHebrew ? he : en
    return StudentTutorialPage.Callout(text: text, x: spot.x, y: spot.y)
  }

  var page: StudentTutorialPage { pages[pageIndex] }
  var isFirstPage: Bool { pageIndex == 0 }
  var isLastPage: Bool { pageIndex == pages.count - 1 }

  func appeared() {
    StudentTutorialStore.markShown()
    AnalyticsService.shared.logEvent(AnalyticsEvent.tutorialShown, parameters: ["source": source.rawValue])
  }

  func next() {
    guard !isLastPage else { return }
    pageIndex += 1
  }

  func back() {
    guard !isFirstPage else { return }
    pageIndex -= 1
  }

  /// Closes the tutorial from any page. It opens again at the next launch.
  func skip() {
    AnalyticsService.shared.logEvent(
      AnalyticsEvent.tutorialSkipped,
      parameters: ["source": source.rawValue, "page": pageIndex + 1]
    )
    onClose()
  }

  /// The last page's Let's start. With "Don't show me again" ticked the
  /// tutorial stops opening at launch (the side menu still opens it);
  /// otherwise it opens again at the next launch.
  func finish() {
    AnalyticsService.shared.logEvent(AnalyticsEvent.tutorialCompleted, parameters: ["source": source.rawValue])
    if dontShowAgain {
      StudentTutorialStore.hide()
      AnalyticsService.shared.logEvent(AnalyticsEvent.tutorialHidden, parameters: ["source": source.rawValue])
    }
    onClose()
  }
}
