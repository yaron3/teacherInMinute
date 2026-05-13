import Foundation
import Observation

#if !os(Android)
import FirebaseAuth
import FirebaseDatabase
#else
import SkipBridge
import SkipFirebaseAuth
#endif

struct ChatMessage: Identifiable, Equatable {
  let id: String
  let text: String
  let senderUid: String
  let senderRole: String
  let createdAt: Double

  var isMine: Bool {
    senderUid == Auth.auth().currentUser?.uid
  }
}

struct BoardPoint: Equatable {
  let x: Double
  let y: Double
}

struct BoardStroke: Identifiable, Equatable {
  let id: String
  let points: [BoardPoint]
  let createdAt: Double
}

@MainActor
final class ChatSessionService {
  private let questionId: String
#if !os(Android)
  private let messagesRef: FirebaseDatabase.DatabaseReference
  private let boardRef: FirebaseDatabase.DatabaseReference
  private var messagesHandle: DatabaseHandle?
  private var boardHandle: DatabaseHandle?
#endif

  init(questionId: String) {
    self.questionId = questionId
#if !os(Android)
    let questionRef = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    self.messagesRef = questionRef.child("messages")
    self.boardRef = questionRef.child("board/strokes")
#endif
  }

  func startListening(onUpdate: @escaping ([ChatMessage]) -> Void) {
#if !os(Android)
    messagesHandle = messagesRef.observe(.value) { snapshot in
      var messages: [ChatMessage] = []
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot,
              let dict = snap.value as? [String: Any],
              let message = Self.message(from: snap.key, dict: dict) else { continue }
        messages.append(message)
      }
      messages.sort { $0.createdAt < $1.createdAt }
      onUpdate(messages)
    }
#endif
  }

  func startBoardListening(onUpdate: @escaping ([BoardStroke]) -> Void) {
#if !os(Android)
    boardHandle = boardRef.observe(.value) { snapshot in
      var strokes: [BoardStroke] = []
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot,
              let dict = snap.value as? [String: Any],
              let stroke = Self.stroke(from: snap.key, dict: dict) else { continue }
        strokes.append(stroke)
      }
      strokes.sort { $0.createdAt < $1.createdAt }
      onUpdate(strokes)
    }
#endif
  }

  func stopListening() {
#if !os(Android)
    if let messagesHandle {
      messagesRef.removeObserver(withHandle: messagesHandle)
      self.messagesHandle = nil
    }
    if let boardHandle {
      boardRef.removeObserver(withHandle: boardHandle)
      self.boardHandle = nil
    }
#endif
  }

  func sendText(_ text: String, senderRole: String) async throws {
    guard let uid = Auth.auth().currentUser?.uid else { throw FunctionsError.notSignedIn }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.sendText(questionId: self.questionId, text: trimmed, senderRole: senderRole)
    }.value
#else
    let payload: [String: Any] = [
      "text": trimmed,
      "senderUid": uid,
      "senderRole": senderRole,
      "createdAt": Date().timeIntervalSince1970 * 1000.0,
      "kind": "text"
    ]
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      messagesRef.childByAutoId().setValue(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func sendStroke(_ points: [BoardPoint]) async throws {
    guard !points.isEmpty else { return }

#if os(Android)
    let pointsJson = Self.pointsJson(points)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.sendStroke(questionId: self.questionId, pointsJson: pointsJson)
    }.value
#else
    let payload: [String: Any] = [
      "points": points.map { ["x": $0.x, "y": $0.y] },
      "createdAt": Date().timeIntervalSince1970 * 1000.0
    ]
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      boardRef.childByAutoId().setValue(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func clearBoard() async throws {
#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.clearBoard(questionId: self.questionId)
    }.value
#else
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      boardRef.removeValue { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

#if os(Android)
  func fetchMessages() async throws -> [ChatMessage] {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchMessages(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    return rows.compactMap { row in
      guard let id = row["id"] as? String else { return nil }
      return Self.message(from: id, dict: row)
    }.sorted { $0.createdAt < $1.createdAt }
  }

  func fetchBoardStrokes() async throws -> [BoardStroke] {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchBoardStrokes(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    return rows.compactMap { row in
      guard let id = row["id"] as? String else { return nil }
      return Self.stroke(from: id, dict: row)
    }.sorted { $0.createdAt < $1.createdAt }
  }
#endif

  private static func message(from id: String, dict: [String: Any]) -> ChatMessage? {
    guard let text = dict["text"] as? String,
          let senderUid = dict["senderUid"] as? String else { return nil }
    let senderRole = dict["senderRole"] as? String ?? "student"
    let createdAt: Double
    if let value = dict["createdAt"] as? Double {
      createdAt = value
    } else if let value = dict["createdAt"] as? NSNumber {
      createdAt = value.doubleValue
    } else {
      createdAt = 0
    }
    return ChatMessage(id: id, text: text, senderUid: senderUid, senderRole: senderRole, createdAt: createdAt)
  }

  private static func stroke(from id: String, dict: [String: Any]) -> BoardStroke? {
    guard let pointRows = dict["points"] as? [[String: Any]] else { return nil }
    let points = pointRows.compactMap { row -> BoardPoint? in
      guard let x = doubleValue(row["x"]),
            let y = doubleValue(row["y"]) else { return nil }
      return BoardPoint(x: x, y: y)
    }
    guard !points.isEmpty else { return nil }
    return BoardStroke(id: id, points: points, createdAt: doubleValue(dict["createdAt"]) ?? 0)
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static func pointsJson(_ points: [BoardPoint]) -> String {
    let rows = points.map { ["x": $0.x, "y": $0.y] }
    guard let data = try? JSONSerialization.data(withJSONObject: rows),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
  }
}

@Observable
@MainActor
final class ChatSessionViewModel {
  let questionId: String
  let role: String
  var messages: [ChatMessage] = []
  var boardStrokes: [BoardStroke] = []
  var draft = ""
  var errorMessage: String?
  var onMessagesUpdated: (([ChatMessage]) -> Void)?
  var onBoardStrokesUpdated: (([BoardStroke]) -> Void)?
  var onErrorUpdated: ((String?) -> Void)?
  var boardRevision: String {
    boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  private let service: ChatSessionService
  private var pollingTask: Task<Void, Never>?

  init(questionId: String, role: String) {
    self.questionId = questionId
    self.role = role
    self.service = ChatSessionService(questionId: questionId)
  }

  func start() {
#if os(Android)
    pollingTask?.cancel()
    pollingTask = Task {
      while !Task.isCancelled {
        do {
          let rows = try await service.fetchMessages()
          let strokes = try await service.fetchBoardStrokes()
          guard !Task.isCancelled else { return }
          messages = rows
          boardStrokes = strokes
          onMessagesUpdated?(rows)
          onBoardStrokesUpdated?(strokes)
        } catch {
          errorMessage = error.localizedDescription
          onErrorUpdated?(errorMessage)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
      }
    }
#else
    service.startListening { [weak self] rows in
      self?.messages = rows
      self?.onMessagesUpdated?(rows)
    }
    service.startBoardListening { [weak self] strokes in
      self?.boardStrokes = strokes
      self?.onBoardStrokesUpdated?(strokes)
    }
#endif
  }

  func stop() {
    pollingTask?.cancel()
    pollingTask = nil
    service.stopListening()
  }

  func send() {
    send(draft)
  }

  func localMessage(text: String) -> ChatMessage {
    ChatMessage(
      id: "local-\(Date().timeIntervalSince1970)",
      text: text,
      senderUid: Auth.auth().currentUser?.uid ?? "",
      senderRole: role,
      createdAt: Date().timeIntervalSince1970 * 1000.0
    )
  }

  func localStroke(points: [BoardPoint]) -> BoardStroke {
    BoardStroke(
      id: "local-\(Date().timeIntervalSince1970)",
      points: points,
      createdAt: Date().timeIntervalSince1970 * 1000.0
    )
  }

  func send(_ messageText: String) {
    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    errorMessage = nil
#if os(Android)
#endif
    Task {
      do {
        try await service.sendText(text, senderRole: role)
      } catch {
        errorMessage = error.localizedDescription
        onErrorUpdated?(errorMessage)
        print("Chat send failed: \(error.localizedDescription)")
      }
    }
  }

  func sendStroke(_ points: [BoardPoint]) {
    guard !points.isEmpty else { return }
    errorMessage = nil
#if os(Android)
#endif
    Task {
      do {
        try await service.sendStroke(points)
      } catch {
        errorMessage = error.localizedDescription
        onErrorUpdated?(errorMessage)
        print("Board stroke send failed: \(error.localizedDescription)")
      }
    }
  }

  func clearBoard() {
    errorMessage = nil
    onErrorUpdated?(nil)
    Task {
      do {
        try await service.clearBoard()
        boardStrokes = []
        onBoardStrokesUpdated?([])
      } catch {
        errorMessage = error.localizedDescription
        onErrorUpdated?(errorMessage)
        print("Board clear failed: \(error.localizedDescription)")
      }
    }
  }
}

#if os(Android)
private enum AndroidChatBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidChatManager")
  private static let fetchMethod = managerClass.getStaticMethodID(
    name: "fetchMessagesJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let sendMethod = managerClass.getStaticMethodID(
    name: "sendText",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let fetchBoardMethod = managerClass.getStaticMethodID(
    name: "fetchBoardStrokesJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let sendStrokeMethod = managerClass.getStaticMethodID(
    name: "sendStroke",
    sig: "(Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let clearBoardMethod = managerClass.getStaticMethodID(
    name: "clearBoard",
    sig: "(Ljava/lang/String;)V"
  )!

  static func fetchMessages(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func sendText(questionId: String, text: String, senderRole: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: sendMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          text.toJavaParameter(options: [.kotlincompat]),
          senderRole.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func fetchBoardStrokes(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchBoardMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func sendStroke(questionId: String, pointsJson: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: sendStrokeMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          pointsJson.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func clearBoard(questionId: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: clearBoardMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    }
  }
}
#endif
