//
//  SimulateStudentQuestionViewModel+LocalizedStrings.swift
//  teacher-minute
//

import Foundation

extension SimulateStudentQuestionViewModel {
  var screenTitle: String { LocalizationSupport.localized("Simulate a Student Question") }
  var introText: String {
    LocalizationSupport.localized("A demo student writes the question with a local AI model and sends it to you, so you can practise the whole flow without a real student.")
  }
  var topicTitle: String { LocalizationSupport.localized("Topic") }
  var difficultyTitle: String { LocalizationSupport.localized("Difficulty") }
  var sessionTypeTitle: String { LocalizationSupport.localized("Session type") }
  /// A topic, difficulty or session type, from its English option key.
  func optionLabel(_ option: String) -> String {
    LocalizationSupport.localized(option.capitalized)
  }
  var hintTitle: String { LocalizationSupport.localized("What should it be about? (optional)") }
  var hintPlaceholder: String { LocalizationSupport.localized("e.g. solving quadratic equations") }
  var sendLabel: String { LocalizationSupport.localized("Send Simulated Question") }
  var footnoteText: String {
    LocalizationSupport.localized("The question takes a few seconds to write. You will get it on your dashboard like any other request.")
  }
}
