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
  let participantName: String
  let originalQuestion: String
  let primaryAmountTitle: String
  let primaryAmountSubtitle: String
  let sessionNoticeText: String
  let sessionStartedAt: Double
  let connectionFeeCents: Int
  let pricePerMinuteCents: Int
  let teacherSharePercent: Double
  var onMessagesUpdated: (([ChatMessage]) -> Void)?
  var onBoardStrokesUpdated: (([BoardStroke]) -> Void)?
  var onErrorUpdated: ((String?) -> Void)?
  var onConnectingUpdated: ((Bool) -> Void)?
  var onSessionDetailsUpdated: (() -> Void)?

  private let currentUid = "mock-current-user"

  init(
    questionId: String = "mock-question",
    role: String = "student",
    messages: [ChatMessage] = [],
    boardStrokes: [BoardStroke] = [],
    isConnecting: Bool = true,
    participantName: String = "Michael",
    originalQuestion: String = "How do I solve quadratic equations using the quadratic formula? I'm confused about the discriminant.",
    sessionNoticeText: String = "Session started - Billing active",
    sessionStartedAt: Double = Date().timeIntervalSince1970 * 1000.0 - 83_000.0,
    connectionFeeCents: Int = 0,
    pricePerMinuteCents: Int = 60,
    teacherSharePercent: Double = 75
  ) {
    self.questionId = questionId
    self.role = role
    self.messages = messages.isEmpty ? Self.defaultMessages(currentRole: role) : messages
    self.boardStrokes = boardStrokes
    self.isConnecting = isConnecting
    self.participantName = participantName
    self.originalQuestion = originalQuestion
    let isTeacherRole = Self.isTeacherRole(role)
    self.primaryAmountTitle = isTeacherRole ? "Live Earnings" : "Session Cost"
    self.primaryAmountSubtitle = isTeacherRole ? "Your share (\(Int(teacherSharePercent))%)" : "Total so far"
    self.sessionNoticeText = sessionNoticeText
    self.sessionStartedAt = sessionStartedAt
    self.connectionFeeCents = connectionFeeCents
    self.pricePerMinuteCents = pricePerMinuteCents
    self.teacherSharePercent = teacherSharePercent
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

  func primaryAmountText(at date: Date) -> String {
    let elapsedMinutes = Double(sessionDurationSeconds(at: date)) / 60.0
    let grossCents = Double(connectionFeeCents) + elapsedMinutes * Double(pricePerMinuteCents)
    let cents = Self.isTeacherRole(role) ? grossCents * (teacherSharePercent / 100.0) : grossCents
    return String(format: "$%.2f", max(0, cents) / 100.0)
  }

  func sessionTimeText(at date: Date) -> String {
    let seconds = sessionDurationSeconds(at: date)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  func messageTimeText(createdAt: Double, at date: Date) -> String {
    let elapsed = max(0, Int(date.timeIntervalSince1970 - createdAt / 1000.0))
    if elapsed < 60 { return "Just now" }
    let minutes = elapsed / 60
    if minutes < 60 { return minutes == 1 ? "1 min ago" : "\(minutes) min ago" }
    let hours = minutes / 60
    return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
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
        text: "Hi! Let me help you with the quadratic formula. First, can you show me the specific problem you're working on?",
        senderUid: currentRole == "teacher" ? "mock-current-user" : "mock-other-user",
        senderRole: "teacher",
        createdAt: Date().timeIntervalSince1970 * 1000.0 - 120_000.0,
        isMine: currentRole == "teacher"
      ),
      ChatMessage(
        id: "mock-2",
        text: "Sure! It's x^2 - 5x + 6 = 0",
        senderUid: currentRole == "student" ? "mock-current-user" : "mock-other-user",
        senderRole: "student",
        createdAt: Date().timeIntervalSince1970 * 1000.0 - 60_000.0,
        isMine: currentRole == "student"
      )
    ]
  }

  private static func isTeacherRole(_ role: String) -> Bool {
    role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "teacher"
  }

  private func sessionDurationSeconds(at date: Date) -> Int {
    max(0, Int(date.timeIntervalSince1970 - sessionStartedAt / 1000.0))
  }
}
