//
//  SimulateStudentQuestionViewModel.swift
//  teacher-minute
//
//  Form state for the teacher-facing "simulate an incoming question" demo tool.
//  Sending is driven by TeacherDashboardViewModel so the work outlives this
//  sheet — the sheet closes the moment the teacher taps Send.
//

import SwiftUI
import Observation
import Foundation

@Observable
@MainActor
final class SimulateStudentQuestionViewModel {

  // MARK: - State

  var simulation = DemoStudentSimulation()
  /// Bound directly by the text field; folded into `simulation` when sending.
  var hint = ""

  // MARK: - Actions

  func selectTopic(_ topic: String) {
    simulation.topic = topic
  }

  func selectDifficulty(_ difficulty: String) {
    simulation.difficulty = difficulty
  }

  func selectConversationType(_ type: String) {
    simulation.conversationType = type
  }

  /// The simulation the teacher configured, ready to hand to the dashboard.
  func pendingSimulation() -> DemoStudentSimulation {
    var result = simulation
    result.hint = hint
    return result
  }
}
