//
//  StudentTutorialViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for Instant Teacher's tutorial.
//

import Foundation

extension StudentTutorialViewModel {
  var skipLabel: String { LocalizationSupport.localized("Skip") }
  var nextLabel: String { LocalizationSupport.localized("Next") }
  var backLabel: String { LocalizationSupport.localized("Back") }
  var startLabel: String { LocalizationSupport.localized("Let's start") }
  var dontShowAgainLabel: String { LocalizationSupport.localized("Don't show me again") }
  var pageCounterText: String {
    String(format: LocalizationSupport.localized("%d of %d"), pageIndex + 1, pages.count)
  }

  var welcomeTitle: String { LocalizationSupport.localized("Welcome to Instant Teacher") }
  var welcomeBody: String {
    LocalizationSupport.localized("Stuck on a question? A real human teacher joins you in about 90 seconds and explains exactly the step you missed.")
  }

  // MARK: Asking, on the home screen
  var cameraTitle: String { LocalizationSupport.localized("Point the camera at the exercise") }
  var cameraTabCallout: String { LocalizationSupport.localized("Photo: the camera opens on the home screen") }
  var cameraShutterCallout: String { LocalizationSupport.localized("Tap here to take the picture") }
  var cameraBubblesCallout: String { LocalizationSupport.localized("Teachers online now, and the price per minute") }

  var attachedTitle: String { LocalizationSupport.localized("Your photo is attached") }
  var attachedPhotoCallout: String { LocalizationSupport.localized("Your picture. Tap it to remove it and retake") }
  var attachedWordsCallout: String { LocalizationSupport.localized("Add a few words about where you got stuck") }
  var attachedFindCallout: String { LocalizationSupport.localized("Find a Teacher sends your question") }

  var textTitle: String { LocalizationSupport.localized("Or write your question") }
  var textTabCallout: String { LocalizationSupport.localized("Text: type the question instead") }
  var textAreaCallout: String { LocalizationSupport.localized("Write the exercise and what you don't understand") }
  var textMathKeyboardCallout: String { LocalizationSupport.localized("A math keyboard for equations and symbols") }

  var matchTitle: String { LocalizationSupport.localized("We find you a teacher") }
  var matchBody: String {
    LocalizationSupport.localized("Tap Find a Teacher. Your question goes to available teachers for that subject, and the first to accept joins you.")
  }

  // MARK: The lesson
  var chatTitle: String { LocalizationSupport.localized("A live one-on-one lesson") }
  var chatMessagesCallout: String { LocalizationSupport.localized("Chat with your teacher in real time") }
  var chatMediaCallout: String { LocalizationSupport.localized("Media: switch to voice or video") }
  var chatTimerCallout: String { LocalizationSupport.localized("Lesson time: you pay only for these minutes") }
  var chatEndCallout: String { LocalizationSupport.localized("End the lesson when you understand") }

  var boardTitle: String { LocalizationSupport.localized("Draw together on the board") }
  var boardTabCallout: String { LocalizationSupport.localized("Switch between Chat and Board") }
  var boardToolsCallout: String { LocalizationSupport.localized("Pen, line and shapes") }
  var boardDrawingCallout: String { LocalizationSupport.localized("You and the teacher draw on the same board") }

  var sessionTitle: String { LocalizationSupport.localized("Your live session") }
  var sessionBody: String {
    LocalizationSupport.localized("This is the lesson: you and your teacher see each other, talk, and work on the same board.")
  }

  var minutesTitle: String { LocalizationSupport.localized("Pay only for the minutes you use") }
  var minutesBody: String {
    LocalizationSupport.localized("Create a free account and load minutes. Only the time the lesson runs is charged, with no subscription and no fixed lessons.")
  }
  var menuTitle: String { LocalizationSupport.localized("Everything is in the menu") }
  var menuBody: String {
    LocalizationSupport.localized("Rate your teacher after each lesson. Your past lessons, minutes, settings and support are in the menu, and so is this tutorial.")
  }
}
