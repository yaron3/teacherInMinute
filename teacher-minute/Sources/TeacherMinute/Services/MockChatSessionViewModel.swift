//
//  MockChatSessionViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 13/05/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class MockChatSessionViewModel: ChatSessionViewModeling {
  let questionId: String
  let role: String
  var messages: [ChatMessage]
  var boardStrokes: [BoardStroke]
  var errorMessage: String?
  var isConnecting: Bool
  var onMessagesUpdated: (([ChatMessage]) -> Void)?
  var onBoardStrokesUpdated: (([BoardStroke]) -> Void)?
  var onErrorUpdated: ((String?) -> Void)?
  var onConnectingUpdated: ((Bool) -> Void)?

  private let currentUid = "mock-current-user"

  init(
    questionId: String = "mock-question",
    role: String = "student",
    messages: [ChatMessage] = [],
    boardStrokes: [BoardStroke] = [],
    isConnecting: Bool = true
  ) {
    self.questionId = questionId
    self.role = role
    self.messages = messages.isEmpty ? Self.defaultMessages(currentRole: role) : messages
    self.boardStrokes = boardStrokes
    self.isConnecting = isConnecting
  }

  func start() {
    onConnectingUpdated?(isConnecting)
    Task {
      if isConnecting {
        try? await Task.sleep(nanoseconds: 300_000_000)
        isConnecting = false
        onConnectingUpdated?(false)
      }
      onMessagesUpdated?(messages)
      onBoardStrokesUpdated?(boardStrokes)
      onErrorUpdated?(errorMessage)
    }
  }

  func stop() {
    isConnecting = true
    onConnectingUpdated?(true)
  }

  func localMessage(text: String) -> ChatMessage {
    ChatMessage(
      id: "mock-local-\(Date().timeIntervalSince1970)",
      text: text,
      senderUid: currentUid,
      senderRole: role,
      createdAt: Date().timeIntervalSince1970 * 1000.0,
      isMine: true
    )
  }

  func localStroke(points: [BoardPoint]) -> BoardStroke {
    BoardStroke(
      id: "mock-local-\(Date().timeIntervalSince1970)",
      points: points,
      createdAt: Date().timeIntervalSince1970 * 1000.0,
      isMine: true
    )
  }

  func send(_ messageText: String) {
    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let message = localMessage(text: text)
    messages.append(message)
    onMessagesUpdated?(messages)
  }

  func sendStroke(_ points: [BoardPoint]) {
    guard !points.isEmpty else { return }
    let stroke = localStroke(points: points)
    boardStrokes.append(stroke)
    onBoardStrokesUpdated?(boardStrokes)
  }

  func clearBoard() {
    boardStrokes.removeAll()
    onBoardStrokesUpdated?([])
  }

  private static func defaultMessages(currentRole: String) -> [ChatMessage] {
    [
      ChatMessage(
        id: "mock-1",
        text: "Hi, show me where you got stuck.",
        senderUid: currentRole == "teacher" ? "mock-current-user" : "mock-other-user",
        senderRole: "teacher",
        createdAt: 1,
        isMine: currentRole == "teacher"
      ),
      ChatMessage(
        id: "mock-2",
        text: "I understand the first step, but not how to factor it.",
        senderUid: currentRole == "student" ? "mock-current-user" : "mock-other-user",
        senderRole: "student",
        createdAt: 2,
        isMine: currentRole == "student"
      )
    ]
  }
}
