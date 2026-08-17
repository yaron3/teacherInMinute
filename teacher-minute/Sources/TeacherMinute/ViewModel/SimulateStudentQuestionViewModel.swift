//
//  SimulateStudentQuestionViewModel.swift
//  teacher-minute
//
//  Drives the teacher-facing "simulate an incoming question" demo tool.
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
  var isSending = false
  var statusMessage: String? = nil
  var errorMessage: String? = nil
  /// Question text the local model produced, shown as confirmation.
  var dispatchedQuestionText: String? = nil
  /// True when the service had to use a canned question because the model was down.
  var usedCannedQuestion = false

  private var sendTask: Task<Void, Never>? = nil

  var canSend: Bool { !isSending }

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

  func send(teacherName: String) {
    guard !isSending else { return }

    simulation.hint = hint
    isSending = true
    errorMessage = nil
    dispatchedQuestionText = nil
    usedCannedQuestion = false
    statusMessage = LocalizationSupport.localized("Writing a question with the local AI model...")

    sendTask?.cancel()
    sendTask = Task { [weak self] in
      guard let self else { return }
      do {
        let requestId = try await DemoStudentService.submit(simulation, teacherName: teacherName)
        try Task.checkCancellation()
        statusMessage = LocalizationSupport.localized("Waiting for the demo student to send it...")

        let status = try await DemoStudentService.awaitDispatch(requestId: requestId)
        try Task.checkCancellation()

        isSending = false
        statusMessage = LocalizationSupport.localized("Question sent — it should appear in your queue now.")
        dispatchedQuestionText = status.questionText
        usedCannedQuestion = status.source == "fallback"
        AnalyticsService.shared.logEvent(AnalyticsEvent.teacherDemoQuestionSimulated, parameters: [
          "topic": simulation.topic,
          "difficulty": simulation.difficulty,
          "conversation_type": simulation.conversationType,
          "source": status.source
        ])
        logger.info("[Simulate] dispatched qid=\(status.questionId) source=\(status.source)")
      } catch is CancellationError {
        isSending = false
        statusMessage = nil
      } catch {
        isSending = false
        statusMessage = nil
        errorMessage = error.localizedDescription
        logger.error("[Simulate] failed — \(error.localizedDescription)")
      }
    }
  }

  func cancel() {
    sendTask?.cancel()
    sendTask = nil
    isSending = false
    statusMessage = nil
  }
}
