import Foundation
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
import FirebaseDatabase
import LiveKit
#else
import SkipBridge
import SkipFirebaseAuth
#endif

struct ChatMessage: Identifiable, Equatable {
  /// The note a student leaves as they close a session their minutes ran out
  /// on. An ordinary message otherwise.
  static let farewellKind = "farewell"

  let id: String
  let text: String
  let senderUid: String
  let senderRole: String
  let createdAt: Double
  let isMine: Bool
  /// `farewellKind` for a parting note, "text" for everything else. Defaulted
  /// so the places that build a message locally keep compiling.
  var kind: String = "text"
}

struct BoardPoint: Equatable {
  let x: Double
  let y: Double
}

struct BoardStroke: Identifiable, Equatable {
  let id: String
  let points: [BoardPoint]
  let createdAt: Double
  let isMine: Bool
}

struct BoardViewport: Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
  let updatedAt: Double
}

struct ChatSessionDetails: Equatable {
  let questionId: String
  let studentId: String
  let teacherId: String
  let studentName: String
  let teacherName: String
  let studentImageURL: String
  let teacherImageURL: String
  let questionText: String
  let questionPhotoUrls: [String]
  let createdAt: Double
  let acceptedAt: Double
  let pricePerMinuteCents: Int
  let teacherSharePercent: Double
  let currencyCode: String
  /// When the student's purchased minutes run out, in epoch milliseconds, as
  /// published by `startLesson` and kept current when they buy more. Zero when
  /// the backend has not said — a lesson from before allowances were recorded
  /// runs exactly as it used to, with no countdown and no hold.
  ///
  /// Defaulted so the several places that rebuild these details keep compiling;
  /// each of them passes the current value through deliberately.
  var minutesDeadlineAt: Double = 0
  /// The lesson's current medium, as last written to the question node —
  /// `ConversationType` raw values. Empty when the node has not said. Either
  /// side may change it while the lesson runs, and the other follows.
  var conversationType: String = ""
}

/// The room and token one participant joins the lesson's media with.
struct MediaCredentials: Equatable {
  let room: String
  let token: String
}

/// One reading of the lesson's `connectionSetup` entries — see
/// `ConnectionSetupSignal` — and whether the question is still live.
struct ConnectionSetupReading: Equatable {
  let isLive: Bool
  /// Each side's signal, keyed by role.
  let signals: [String: String]
}

/// What this side should do about the lesson's shared medium.
enum ConversationTypeChange: Equatable {
  /// Nothing new, or nothing this side has to act on.
  case none
  /// Follow straight away: the other side dropped media.
  case apply(String)
  /// The other side added media. Ask before turning any of it on here.
  case askToFollow(String)
}

/// What the student's remaining credit means for the session right now.
enum MinutesHoldState: Equatable {
  /// Time left, or no deadline published at all.
  case none
  /// Under a minute to go, so the student can top up before being interrupted.
  case warning
  /// Nothing left. The session holds here until the student buys more minutes
  /// or ends the call; nothing past this point is billed.
  case held
}

@MainActor
final class ChatSessionService {
  private let questionId: String
  private let currentUserUid: String
#if !os(Android)
  private let questionRef: FirebaseDatabase.DatabaseReference
  private let messagesRef: FirebaseDatabase.DatabaseReference
  private let boardRef: FirebaseDatabase.DatabaseReference
  private let boardViewportsRef: FirebaseDatabase.DatabaseReference
  private let chatPausedRef: FirebaseDatabase.DatabaseReference
  private let mediaPendingRef: FirebaseDatabase.DatabaseReference
  private let connectionSetupRef: FirebaseDatabase.DatabaseReference
  private let statusRef: FirebaseDatabase.DatabaseReference
  private var sessionHandle: DatabaseHandle?
  private var messagesHandle: DatabaseHandle?
  private var boardHandle: DatabaseHandle?
  private var boardViewportsHandle: DatabaseHandle?
  private var chatPausedHandle: DatabaseHandle?
  private var mediaPendingHandle: DatabaseHandle?
  private var connectionSetupHandle: DatabaseHandle?
  private var statusHandle: DatabaseHandle?
#endif

  init(questionId: String, currentUserUid: String? = nil) {
    self.questionId = questionId
    self.currentUserUid = currentUserUid ?? Auth.auth().currentUser?.uid ?? ""
#if !os(Android)
    let questionRef = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    self.questionRef = questionRef
    self.messagesRef = questionRef.child("messages")
    self.boardRef = questionRef.child("board/strokes")
    self.boardViewportsRef = questionRef.child("board/viewports")
    self.chatPausedRef = questionRef.child("chatPaused")
    self.mediaPendingRef = questionRef.child("mediaPending")
    self.connectionSetupRef = questionRef.child("connectionSetup")
    self.statusRef = questionRef.child("status")
#endif
  }

  func fetchSessionDetails() async throws -> ChatSessionDetails? {
#if os(Android)
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchSessionDetails(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          !dict.isEmpty else {
      return nil
    }
    return Self.details(from: dict)
#else
    let questionRef = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ChatSessionDetails?, Error>) in
      questionRef.observeSingleEvent(of: .value) { snapshot in
        guard let dict = snapshot.value as? [String: Any] else {
          cont.resume(returning: nil)
          return
        }
        cont.resume(returning: Self.details(from: dict))
      } withCancel: { error in
        cont.resume(throwing: error)
      }
    }
#endif
  }

  static func markQuestionAccepted(questionId: String, teacherId: String?) async throws {
#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.markQuestionAccepted(questionId: questionId, teacherId: teacherId ?? "")
    }.value
#else
    var payload: [String: Any] = [
      "status": "accepted",
      "acceptedAt": Date().timeIntervalSince1970 * 1000.0
    ]
    if let teacherId, !teacherId.isEmpty {
      payload["teacherId"] = teacherId
    }

    let questionRef = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      questionRef.updateChildValues(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func startSessionListening(onEnded: @escaping () -> Void, onUpdate: @escaping (ChatSessionDetails) -> Void = { _ in }) {
#if !os(Android)
    sessionHandle = questionRef.observe(.value) { snapshot in
      if !snapshot.exists() {
        onEnded()
        return
      }
      if let dict = snapshot.value as? [String: Any],
         Self.isTerminalStatus(dict["status"]) {
        onEnded()
        return
      }
      if let dict = snapshot.value as? [String: Any] {
        onUpdate(Self.details(from: dict))
      }
    }
#endif
  }

  private static func isTerminalStatus(_ value: Any?) -> Bool {
    guard let raw = value as? String else { return false }
    switch raw.lowercased() {
    case "cancelled", "canceled", "declined", "rejected", "ended", "expired", "completed":
      return true
    default:
      return false
    }
  }

  func startListening(onUpdate: @escaping ([ChatMessage]) -> Void) {
#if !os(Android)
    messagesHandle = messagesRef.observe(.value) { snapshot in
      var messages: [ChatMessage] = []
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot,
              let dict = snap.value as? [String: Any],
              let message = Self.message(from: snap.key, dict: dict, currentUserUid: self.currentUserUid) else { continue }
		logger.info("[ChatSession] message: \(message.senderRole):\(message.text)")

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
              let stroke = Self.stroke(from: snap.key, dict: dict, currentUserUid: self.currentUserUid) else { continue }
        strokes.append(stroke)
      }
      strokes.sort { $0.createdAt < $1.createdAt }
      onUpdate(strokes)
    }
#endif
  }

  func startBoardViewportListening(onUpdate: @escaping ([String: BoardViewport]) -> Void) {
#if !os(Android)
    boardViewportsHandle = boardViewportsRef.observe(.value) { snapshot in
      var viewports: [String: BoardViewport] = [:]
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot,
              let dict = snap.value as? [String: Any],
              let viewport = Self.viewport(from: dict) else { continue }
        viewports[snap.key] = viewport
      }
      onUpdate(viewports)
    }
#endif
  }

  func startChatPausedListening(onUpdate: @escaping ([String: Bool]) -> Void) {
#if !os(Android)
    chatPausedHandle = chatPausedRef.observe(.value) { snapshot in
      var states: [String: Bool] = [:]
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot else { continue }
        if let flag = snap.value as? Bool {
          states[snap.key] = flag
        } else if let num = snap.value as? NSNumber {
          states[snap.key] = num.boolValue
        }
      }
      onUpdate(states)
    }
#endif
  }

  func startMediaPendingListening(onUpdate: @escaping ([String: Bool]) -> Void) {
#if !os(Android)
    mediaPendingHandle = mediaPendingRef.observe(.value) { snapshot in
      var states: [String: Bool] = [:]
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot else { continue }
        if let flag = snap.value as? Bool {
          states[snap.key] = flag
        } else if let num = snap.value as? NSNumber {
          states[snap.key] = num.boolValue
        }
      }
      onUpdate(states)
    }
#endif
  }

  /// Follows both sides' `connectionSetup` entries, and the question's status:
  /// `onEnded` fires once the question is gone or has reached an end state.
  /// Separate from the lesson's own listeners, which only start once this side
  /// has connected, and left running when those restart.
  func startConnectionSetupListening(
    onUpdate: @escaping ([String: String]) -> Void,
    onEnded: @escaping () -> Void
  ) {
#if !os(Android)
    stopConnectionSetupListening()
    connectionSetupHandle = connectionSetupRef.observe(.value) { snapshot in
      var signals: [String: String] = [:]
      for child in snapshot.children {
        guard let snap = child as? DataSnapshot,
              let signal = snap.value as? String else { continue }
        signals[snap.key] = signal
      }
      onUpdate(signals)
    }
    // Only the status, not the whole question: that would hand over every
    // message and stroke of the lesson on each change.
    statusHandle = statusRef.observe(.value) { snapshot in
      if !snapshot.exists() || Self.isTerminalStatus(snapshot.value) {
        onEnded()
      }
    }
#endif
  }

  func stopConnectionSetupListening() {
#if !os(Android)
    if let connectionSetupHandle {
      connectionSetupRef.removeObserver(withHandle: connectionSetupHandle)
      self.connectionSetupHandle = nil
    }
    if let statusHandle {
      statusRef.removeObserver(withHandle: statusHandle)
      self.statusHandle = nil
    }
#endif
  }

  func stopListening() {
#if !os(Android)
    if let sessionHandle {
      questionRef.removeObserver(withHandle: sessionHandle)
      self.sessionHandle = nil
    }
    if let messagesHandle {
      messagesRef.removeObserver(withHandle: messagesHandle)
      self.messagesHandle = nil
    }
    if let boardHandle {
      boardRef.removeObserver(withHandle: boardHandle)
      self.boardHandle = nil
    }
    if let boardViewportsHandle {
      boardViewportsRef.removeObserver(withHandle: boardViewportsHandle)
      self.boardViewportsHandle = nil
    }
    if let chatPausedHandle {
      chatPausedRef.removeObserver(withHandle: chatPausedHandle)
      self.chatPausedHandle = nil
    }
    if let mediaPendingHandle {
      mediaPendingRef.removeObserver(withHandle: mediaPendingHandle)
      self.mediaPendingHandle = nil
    }
#endif
  }

  func sendText(_ text: String, senderRole: String, kind: String = "text") async throws {
    guard let uid = Auth.auth().currentUser?.uid else { throw FunctionsError.notSignedIn }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.sendText(
        questionId: self.questionId,
        text: trimmed,
        senderRole: senderRole,
        kind: kind
      )
    }.value
#else
    let payload: [String: Any] = [
      "text": trimmed,
      "senderUid": uid,
      "senderRole": senderRole,
      "createdAt": Date().timeIntervalSince1970 * 1000.0,
      "kind": kind
    ]
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      messagesRef.childByAutoId().setValue(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func appendQuestionText(_ addition: String) async throws -> String {
    let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

#if os(Android)
    return try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.appendQuestionText(questionId: self.questionId, addition: trimmed)
    }.value
#else
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
      questionRef.observeSingleEvent(of: .value) { snapshot in
        let current = Self.questionText(from: snapshot.value as? [String: Any])
        let next = Self.appendingQuestionText(addition: trimmed, to: current)
        self.questionRef.updateChildValues([
          "text": next,
          "questionText": next
        ]) { error, _ in
          if let error {
            cont.resume(throwing: error)
            return
          }
          cont.resume(returning: next)
        }
      } withCancel: { error in
        cont.resume(throwing: error)
      }
    }
#endif
  }

#if !os(Android)
  func sendImage(downloadURL: String, senderRole: String) async throws {
    guard let uid = Auth.auth().currentUser?.uid else { throw FunctionsError.notSignedIn }
    let trimmed = downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let payload: [String: Any] = [
      "text": trimmed,
      "senderUid": uid,
      "senderRole": senderRole,
      "createdAt": Date().timeIntervalSince1970 * 1000.0,
      "kind": "image"
    ]
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      messagesRef.childByAutoId().setValue(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
  }
#endif

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
      "createdAt": Date().timeIntervalSince1970 * 1000.0,
      "senderUid": Auth.auth().currentUser?.uid ?? ""
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

  func updateBoardViewport(_ viewport: BoardViewport, role: String) async throws {
    let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = trimmedRole.isEmpty ? "participant" : trimmedRole

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.updateBoardViewport(
        questionId: self.questionId,
        role: key,
        x: viewport.x,
        y: viewport.y,
        width: viewport.width,
        height: viewport.height
      )
    }.value
#else
    let payload: [String: Any] = [
      "x": viewport.x,
      "y": viewport.y,
      "width": viewport.width,
      "height": viewport.height,
      "updatedAt": Date().timeIntervalSince1970 * 1000.0
    ]
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      boardViewportsRef.child(key).setValue(payload) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func setChatPaused(_ paused: Bool, role: String) async throws {
    let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = trimmedRole.isEmpty ? "participant" : trimmedRole

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.setChatPaused(
        questionId: self.questionId,
        role: key,
        paused: paused
      )
    }.value
#else
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      chatPausedRef.child(key).setValue(paused) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  func setMediaPending(_ pending: Bool, role: String) async throws {
    let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = trimmedRole.isEmpty ? "participant" : trimmedRole

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.setMediaPending(
        questionId: self.questionId,
        role: key,
        pending: pending
      )
    }.value
#else
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      mediaPendingRef.child(key).setValue(pending) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

  /// This side's `connectionSetup` entry, which the other side reads while the
  /// lesson connects. Nil removes it.
  func setConnectionSetupSignal(_ signal: ConnectionSetupSignal?, role: String) async throws {
    let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = trimmedRole.isEmpty ? "participant" : trimmedRole

#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.setConnectionSetupSignal(
        questionId: self.questionId,
        role: key,
        signal: signal?.rawValue ?? ""
      )
    }.value
#else
    let ref = connectionSetupRef.child(key)
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      let completion: (Error?, FirebaseDatabase.DatabaseReference) -> Void = { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
      if let signal {
        ref.setValue(signal.rawValue, withCompletionBlock: completion)
      } else {
        ref.removeValue(completionBlock: completion)
      }
    }
#endif
  }

  /// Switches the lesson's medium for both participants.
  func setConversationType(_ conversationType: String) async throws {
#if os(Android)
    try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.setConversationType(
        questionId: self.questionId,
        conversationType: conversationType
      )
    }.value
#else
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      questionRef.child("conversationType").setValue(conversationType) { error, _ in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: ())
      }
    }
#endif
  }

#if os(Android)
  func fetchChatPaused() async throws -> [String: Bool] {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchChatPaused(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }
    var states: [String: Bool] = [:]
    for (key, value) in rows {
      if let flag = value as? Bool {
        states[key] = flag
      } else if let num = value as? NSNumber {
        states[key] = num.boolValue
      }
    }
    return states
  }

  func fetchMediaPending() async throws -> [String: Bool] {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchMediaPending(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }
    var states: [String: Bool] = [:]
    for (key, value) in rows {
      if let flag = value as? Bool {
        states[key] = flag
      } else if let num = value as? NSNumber {
        states[key] = num.boolValue
      }
    }
    return states
  }

  /// One reading of what the iOS setup listeners follow as it changes.
  func fetchConnectionSetup() async throws -> ConnectionSetupReading {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchConnectionSetup(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      // Unreadable is not the same as gone: nothing is inferred from it.
      return ConnectionSetupReading(isLive: true, signals: [:])
    }
    var signals: [String: String] = [:]
    for (key, value) in row["signals"] as? [String: Any] ?? [:] {
      if let signal = value as? String {
        signals[key] = signal
      }
    }
    let status = row["status"] as? String ?? ""
    return ConnectionSetupReading(
      isLive: !status.isEmpty && !Self.isTerminalStatus(status),
      signals: signals
    )
  }

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
      return Self.message(from: id, dict: row, currentUserUid: currentUserUid)
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
      return Self.stroke(from: id, dict: row, currentUserUid: currentUserUid)
    }.sorted { $0.createdAt < $1.createdAt }
  }

  func fetchBoardViewports() async throws -> [String: BoardViewport] {
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidChatBridge.fetchBoardViewports(questionId: self.questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }
    var viewports: [String: BoardViewport] = [:]
    for (key, value) in rows {
      guard let dict = value as? [String: Any],
            let viewport = Self.viewport(from: dict) else { continue }
      viewports[key] = viewport
    }
    return viewports
  }
#endif

  private static func message(from id: String, dict: [String: Any], currentUserUid: String) -> ChatMessage? {
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
    return ChatMessage(
      id: id,
      text: text,
      senderUid: senderUid,
      senderRole: senderRole,
      createdAt: createdAt,
      isMine: senderUid == currentUserUid,
      kind: dict["kind"] as? String ?? "text"
    )
  }

  private static func stroke(from id: String, dict: [String: Any], currentUserUid: String) -> BoardStroke? {
    guard let pointRows = dict["points"] as? [[String: Any]] else { return nil }
    let points = pointRows.compactMap { row -> BoardPoint? in
      guard let x = doubleValue(row["x"]),
            let y = doubleValue(row["y"]) else { return nil }
      return BoardPoint(x: x, y: y)
    }
    guard !points.isEmpty else { return nil }
    let senderUid = dict["senderUid"] as? String ?? ""
    return BoardStroke(
      id: id,
      points: points,
      createdAt: doubleValue(dict["createdAt"]) ?? 0,
      isMine: !senderUid.isEmpty && senderUid == currentUserUid
    )
  }

  private static func viewport(from dict: [String: Any]) -> BoardViewport? {
    guard let x = doubleValue(dict["x"]),
          let y = doubleValue(dict["y"]),
          let width = doubleValue(dict["width"]),
          let height = doubleValue(dict["height"]),
          width > 0,
          height > 0 else { return nil }
    return BoardViewport(
      x: x,
      y: y,
      width: width,
      height: height,
      updatedAt: doubleValue(dict["updatedAt"]) ?? 0
    )
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static func questionText(from dict: [String: Any]?) -> String {
    guard let dict else { return "" }
    return firstString(in: dict, keys: ["text", "questionText", "originalQuestion", "message", "topic"])
  }

  static func appendingQuestionText(addition: String, to current: String) -> String {
    let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAddition.isEmpty else { return trimmedCurrent }
    guard !trimmedCurrent.isEmpty else { return trimmedAddition }
    if trimmedCurrent.contains(trimmedAddition) { return trimmedCurrent }
    return trimmedCurrent + "\n" + trimmedAddition
  }

  private static func pointsJson(_ points: [BoardPoint]) -> String {
    let rows = points.map { ["x": $0.x, "y": $0.y] }
    guard let data = try? JSONSerialization.data(withJSONObject: rows),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
  }

  static func normalizedMilliseconds(_ value: Double) -> Double {
    value > 0 && value < 10_000_000_000 ? value * 1000.0 : value
  }

  private static func details(from dict: [String: Any]) -> ChatSessionDetails {
    ChatSessionDetails(
      questionId: firstString(in: dict, keys: ["questionId", "questionID", "id"]),
      studentId: firstString(in: dict, keys: ["studentId", "studentUID", "studentId"]),
      teacherId: firstString(in: dict, keys: ["teacherId", "teacherUID", "teacherId"]),
      studentName: firstString(in: dict, keys: ["studentName", "studentFullName", "studentDisplayName", "name"]),
      teacherName: firstString(in: dict, keys: ["teacherName", "teacherFullName", "teacherDisplayName"]),
      studentImageURL: firstString(in: dict, keys: ["studentImageURL", "studentProfileImageURL", "studentPhotoURL"]),
      teacherImageURL: firstString(in: dict, keys: ["teacherImageURL", "teacherProfileImageURL", "teacherPhotoURL"]),
      questionText: firstString(in: dict, keys: ["text", "questionText", "originalQuestion", "message", "topic"]),
      questionPhotoUrls: stringArray(dict["photoUrls"]),
      createdAt: normalizedMilliseconds(doubleValue(dict["createdAt"]) ?? 0),
      acceptedAt: normalizedMilliseconds(
        doubleValue(dict["acceptedAt"])
          ?? doubleValue(dict["connectedAt"])
          ?? doubleValue(dict["startedAt"])
          ?? 0
      ),
      pricePerMinuteCents: intValue(dict["pricePerMinuteCents"])
        ?? intValue(dict["ratePerMinuteCents"])
        ?? intValue(dict["costPerMinuteCents"])
        ?? 0,
      teacherSharePercent: doubleValue(dict["teacherSharePercent"]) ?? doubleValue(dict["teacherShare"]) ?? 75,
      currencyCode: currencyCode(from: dict),
      minutesDeadlineAt: normalizedMilliseconds(doubleValue(dict["minutesDeadlineAt"]) ?? 0),
      conversationType: firstString(in: dict, keys: ["conversationType"])
    )
  }

  private static func stringArray(_ value: Any?) -> [String] {
    if let arr = value as? [String] { return arr.filter { !$0.isEmpty } }
    if let arr = value as? [Any] {
      return arr.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
    if let dict = value as? [String: Any] {
      return dict.values.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
    return []
  }

  private static func currencyCode(from dict: [String: Any]) -> String {
    let currency = firstString(in: dict, keys: [
      "currencyCode",
      "currency",
      "packageCurrency",
      "pricingCurrency",
      "purchaseCurrency"
    ])
    return currency.isEmpty ? LessonFormatting.defaultCurrencyCode : currency
  }

  private static func firstString(in dict: [String: Any], keys: [String]) -> String {
    for key in keys {
      if let value = dict[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return ""
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    if let value = value as? Double { return Int(value) }
    return nil
  }
}

@MainActor
protocol ChatSessionViewModeling: AnyObject {
  var questionId: String { get }
  var role: String { get }
  var teacherId: String { get }
  var messages: [ChatMessage] { get set }
  var boardStrokes: [BoardStroke] { get set }
  var boardViewports: [String: BoardViewport] { get set }
  var chatPausedStates: [String: Bool] { get set }
  var mediaPendingStates: [String: Bool] { get set }
  var errorMessage: String? { get set }
  var isConnecting: Bool { get set }
  var participantName: String { get }
  var participantImageURL: String { get }
  var currentUserImageURL: String { get }
  var originalQuestion: String { get }
  var questionPhotoUrls: [String] { get }
  var primaryAmountTitle: String { get }
  var primaryAmountSubtitle: String { get }
  var sessionNoticeText: String { get }
  var onChatPausedUpdated: (([String: Bool]) -> Void)? { get set }
  var onMediaPendingUpdated: (([String: Bool]) -> Void)? { get set }
  var onConnectingUpdated: ((Bool) -> Void)? { get set }

  /// True until the setup screen has both chat and, where asked for, media
  /// ready. Unlike `isConnecting`, which clears once chat alone is up.
  var isInSetup: Bool { get }
  func finishSetup()

  /// New activity from the other side on a tab this side is not looking at.
  var hasUnreadChat: Bool { get }
  var hasUnreadBoard: Bool { get }
  /// Tells the session which tab is on screen, which also marks it read.
  func sessionTabChanged(showsChat: Bool, showsBoard: Bool)
  /// Bumped whenever the other side sends a formula, so the screen can put its
  /// keyboard away and let it be read.
  var incomingFormulaCount: Int { get }
  var onSessionDetailsUpdated: (() -> Void)? { get set }
  var onSessionEnded: (() -> Void)? { get set }

  func start()
  func stop()
  func primaryAmountText(at date: Date) -> String
  func sessionTimeText(at date: Date) -> String
  func sessionDurationSeconds(at date: Date) -> Int
  func messageTimeText(createdAt: Double, at date: Date) -> String
  func localMessage(text: String) -> ChatMessage
  func localStroke(points: [BoardPoint]) -> BoardStroke
  func send(_ messageText: String)
  func sendQuestionFormula(_ formulaText: String)
  func sendStroke(_ points: [BoardPoint])
  func clearBoard()
  func updateBoardViewport(_ viewport: BoardViewport)
  func setSelfChatPaused(_ paused: Bool)
  func peerChatPaused() -> Bool
  func setSelfMediaPending(_ pending: Bool)
  func peerMediaPending() -> Bool
  func endLesson() async

  // MARK: Connecting
  //
  // What each side tells the other while the lesson connects — a permission
  // prompt it is waiting on, or that it left. See `ConnectionSetupSignal`.

  /// What to put to this side about the other one. Nil when there is nothing.
  var peerSetupPrompt: PeerSetupPrompt? { get }
  /// The permission the other side is being asked for, while they still are.
  var peerAwaitedPermission: CapturePermissionKind? { get }
  var onPeerSetupUpdated: (() -> Void)? { get set }
  /// Starts following the other side. Called as the lesson screen appears,
  /// before this side has connected anything.
  func startWatchingPeerSetup()
  /// Tells the other side what this one is waiting on, or that it no longer is.
  func setSelfAwaitingPermission(_ kind: CapturePermissionKind?)
  /// This side keeps waiting while the other side answers a permission prompt.
  func waitForPeerPermission()
  /// Leaves a lesson that has not started: tells the other side, then ends it.
  func cancelSetup()
  /// The user has read that the other side left before the lesson started.
  func acknowledgePeerCancelled()

  /// What the student's remaining credit means at `date`. Read from the
  /// deadline the backend publishes, so both apps reach the same answer at the
  /// same moment without either of them polling.
  func minutesHoldState(at date: Date) -> MinutesHoldState
  /// Sends a parting note, then ends the lesson. An empty note just ends it.
  func endLessonWithFarewell(_ message: String) async
  /// The other side's parting note, when they left one.
  var peerFarewellNote: String? { get }
  func logSessionStarted(conversationType: String)
  func sendBoardSnapshot(_ snapshotData: Data, senderRole: String) async throws

  /// The lesson's medium as both participants currently see it — a
  /// `ConversationType` raw value, or empty until the session node has said.
  var sharedConversationType: String { get }
  /// Asks for whatever `conversationType` needs from this device. Nil once it
  /// is all granted, otherwise the sentence to show.
  func prepareMedia(for conversationType: String) async -> String?
  /// Switches the lesson to `conversationType` for both sides. Nil on success,
  /// otherwise the sentence to show.
  func publishConversationType(_ conversationType: String) async -> String?
  /// Fresh credentials for the lesson's room, for a lesson that started
  /// without them and has just switched to audio or video.
  func fetchMediaCredentials() async -> MediaCredentials?

  /// The lesson's LiveKit room and this participant's token. Empty until
  /// known — a text lesson may start without them.
  var liveKitRoom: String { get set }
  var liveKitToken: String { get set }
  /// The shared medium this side has already acted on. Only a change to it is
  /// followed: a student who went on by chat while the lesson was asked as
  /// audio has not been switched by anyone, and must not be pulled back.
  var lastSeenSharedConversationType: String { get set }

  // MARK: Media

  /// This side's own microphone and camera, as the user left them.
  var isMicMuted: Bool { get set }
  var isCameraOff: Bool { get set }
  //
  // The lesson's audio and video. The connection itself belongs to
  // `LiveKitService`, so it outlives the screen that asked for it.

  var mediaConnectionPhase: MediaConnectionPhase { get }
  /// True when a video lesson connected without its camera.
  var mediaDidFallBackToAudioOnly: Bool { get }
  func mediaQuality() -> SessionMediaQuality
  /// Starts joining the lesson's room with the stored credentials.
  func connectMedia(enableVideo: Bool)
  /// Waits for a connect in flight to settle; true once the room is joined.
  func waitUntilMediaConnected() async -> Bool
  func disconnectMedia() async
  func setMicrophoneEnabled(_ enabled: Bool) async
  func setCameraEnabled(_ enabled: Bool) async
  /// Called on the main actor whenever local or remote tracks change.
  var onMediaTracksUpdated: (@MainActor @Sendable () -> Void)? { get set }
#if !os(Android)
  var localCameraVideoTrack: VideoTrack? { get }
  var remoteCameraVideoTrack: VideoTrack? { get }
#endif
}

// MARK: - ChatSessionViewModeling defaults

extension ChatSessionViewModeling {

  var sharedConversationType: String { "" }

  func prepareMedia(for conversationType: String) async -> String? { nil }

  func publishConversationType(_ conversationType: String) async -> String? { nil }

  func fetchMediaCredentials() async -> MediaCredentials? { nil }

  var hasMediaCredentials: Bool { !liveKitRoom.isEmpty && !liveKitToken.isEmpty }

  func toggleMicrophone() {
    isMicMuted.toggle()
    let enabled = !isMicMuted
    Task { await setMicrophoneEnabled(enabled) }
  }

  func toggleCamera() {
    isCameraOff.toggle()
    let enabled = !isCameraOff
    Task { await setCameraEnabled(enabled) }
  }

  /// Turns the camera off while both sides are reading the chat of a video
  /// lesson, and back on when either returns to the video.
  func setCameraPaused(_ paused: Bool) {
    guard paused != isCameraOff else { return }
    isCameraOff = paused
    Task { await setCameraEnabled(!paused) }
  }

  /// A new medium starts with the microphone and camera on.
  func resetMediaToggles() {
    isMicMuted = false
    isCameraOff = false
  }

  /// A mic or camera turned off while the room was still connecting had
  /// nothing to act on, so it is applied once the room is there.
  func applyMediaTogglesOnConnect() {
    guard isMicMuted || isCameraOff else { return }
    let muteMic = isMicMuted
    let cameraOff = isCameraOff
    Task {
      if muteMic { await setMicrophoneEnabled(false) }
      if cameraOff { await setCameraEnabled(false) }
    }
  }

  /// Moves this side's media to `target`: leaves the room for a text lesson,
  /// changes only the camera in a room already joined or being joined, and
  /// otherwise starts joining.
  func switchMedia(to target: ConversationType) async {
    guard target.requiresMic else {
      await disconnectMedia()
      return
    }
    let phase = mediaConnectionPhase
    guard phase == .connecting || phase == .connected else {
      connectMedia(enableVideo: target.requiresCamera)
      return
    }
    guard await waitUntilMediaConnected() else { return }
    await setMicrophoneEnabled(true)
    await setCameraEnabled(target.requiresCamera)
  }

  /// Makes sure there is a room to join, fetching credentials if the lesson
  /// started without them.
  func ensureMediaCredentials() async -> Bool {
    if hasMediaCredentials { return true }
    guard let credentials = await fetchMediaCredentials() else { return false }
    liveKitRoom = credentials.room
    liveKitToken = credentials.token
    return true
  }

  /// This side picked a new medium: checks the device allows it, then tells
  /// the other side. Nil once the switch is published, otherwise the sentence
  /// to show.
  func requestConversationType(_ conversationType: String) async -> String? {
    if let error = await prepareMedia(for: conversationType) {
      return error
    }
    // Marked as seen before the write: the node echoes it straight back, and
    // that echo is this side's own switch, not one to follow.
    let previouslySeen = lastSeenSharedConversationType
    lastSeenSharedConversationType = conversationType
    if let error = await publishConversationType(conversationType) {
      lastSeenSharedConversationType = previouslySeen
      return error
    }
    return nil
  }

  /// Reads the shared medium and says what, if anything, this side should do
  /// about it, given the medium it is on now. `canFollow` is false while the
  /// lesson is still connecting or already ending; a change seen then is left
  /// for a later reading.
  func sharedConversationTypeChange(current: String, canFollow: Bool) -> ConversationTypeChange {
    let shared = sharedConversationType
    guard let sharedType = ConversationType(rawValue: shared) else { return .none }
    // The first reading is the medium the lesson was asked as, which this
    // side has already set itself up for.
    guard !lastSeenSharedConversationType.isEmpty else {
      lastSeenSharedConversationType = shared
      return .none
    }
    guard canFollow, shared != lastSeenSharedConversationType else { return .none }
    lastSeenSharedConversationType = shared
    logger.info("[ChatSession] other side switched qid=\(self.questionId) role=\(self.role) from=\(current) to=\(shared)")

    // Back to the medium this side is already on still counts as a change: it
    // answers any question still open about the one before.
    let currentRank = ConversationType(rawValue: current)?.mediaRank ?? 0
    return sharedType.mediaRank > currentRank ? .askToFollow(shared) : .apply(shared)
  }

  /// Longest parting note a student can send as they close a held session.
  var farewellMessageMaxLength: Int { 128 }

  func minutesHoldState(at date: Date) -> MinutesHoldState { .none }

  func endLessonWithFarewell(_ message: String) async { await endLesson() }

  var peerFarewellNote: String? { nil }

  func logSessionStarted(conversationType: String) {
  }

  func sendBoardSnapshot(_ snapshotData: Data, senderRole: String) async throws {
  }
}

// MARK: - ChatSessionViewModeling UI Strings
extension ChatSessionViewModeling {

  // MARK: Out of minutes

  var outOfMinutesTitle: String { LocalizationSupport.localized("No more minutes left.") }
  var outOfMinutesMessage: String {
    LocalizationSupport.localized("Buy more minutes to carry on, or end the call with a short note for your teacher.")
  }
  var buyMoreMinutesLabel: String { LocalizationSupport.localized("Buy more minutes") }
  var endTheCallLabel: String { LocalizationSupport.localized("End the call") }
  var minutesRunningOutNotice: String {
    LocalizationSupport.localized("Less than a minute of credit left.")
  }
  var farewellPromptMessage: String {
    LocalizationSupport.localized("Your teacher will see this before the call ends.")
  }
  var farewellPlaceholder: String { LocalizationSupport.localized("Message to your teacher") }
  var sendAndEndLabel: String { LocalizationSupport.localized("Send and end the call") }

  // MARK: Out of minutes — the teacher's side

  var studentOutOfMinutesTitle: String {
    LocalizationSupport.localized("The student is out of minutes.")
  }
  var studentOutOfMinutesMessage: String {
    LocalizationSupport.localized("They can buy more to carry on. You can wait, or end the call.")
  }
  var waitForStudentLabel: String { LocalizationSupport.localized("Wait") }
  var peerEndedLessonTitle: String {
    LocalizationSupport.localized("The student ended the lesson.")
  }
  var okLabel: String { LocalizationSupport.localized("OK") }
  func farewellCharactersLeftText(_ remaining: Int) -> String {
    String(format: LocalizationSupport.localized("%d characters left"), remaining)
  }

  // MARK: Header / connection

  var connectedVideoText: String { LocalizationSupport.localized("Connected - Video session") }
  var connectedAudioText: String { LocalizationSupport.localized("Connected - Audio session") }
  var connectedText: String { LocalizationSupport.localized("Connected") }

  // MARK: Composer

  var messagePlaceholder: String { LocalizationSupport.localized("Message") }

  // MARK: Whiteboard

  var clearBoardTitle: String { LocalizationSupport.localized("Clear board?") }
  var peerClearedBoardTitle: String { LocalizationSupport.localized("The other side cleared the board") }
  var saveAsPhotoAndClearLabel: String { LocalizationSupport.localized("Save as photo and clear") }
  var saveAsPhotoLabel: String { LocalizationSupport.localized("Save as photo") }
  var clearLabel: String { LocalizationSupport.localized("Clear") }
  var dismissLabel: String { LocalizationSupport.localized("Dismiss") }
  var boardHintText: String { LocalizationSupport.localized("Use your finger to write or sketch.") }
  var seeOtherSideLabel: String { LocalizationSupport.localized("See the other side") }

  // MARK: Rate the session

  var sessionCompleteTitle: String { LocalizationSupport.localized("Session Complete!") }
  var rateSessionTitle: String { LocalizationSupport.localized("Rate this session") }
  var rateCommentPlaceholderTitle: String { LocalizationSupport.localized("Add a comment (optional)") }
  var rateCommentPrivacyNote: String {
    LocalizationSupport.localized("Your teacher sees this without your name.")
  }
  var sendLabel: String { LocalizationSupport.localized("Send") }
  var ratingFailedMessage: String {
    LocalizationSupport.localized("Could not send rating. Please try again next time.")
  }

  func greatJobText(teacherName: String) -> String {
    String(format: LocalizationSupport.localized("Great job learning with %@"), teacherName)
  }

  func rateExperienceText(teacherName: String) -> String {
    String(format: LocalizationSupport.localized("How was your experience with %@?"), teacherName)
  }

  // MARK: End-session prompt

  var endSessionTitleLabel: String { LocalizationSupport.localized("End session?") }
  var saveBoardTitleLabel: String { LocalizationSupport.localized("Save board to gallery?") }
  var endSessionConfirmMessage: String { LocalizationSupport.localized("Are you sure you want to end this session?") }
  var saveBoardRemoteMessage: String { LocalizationSupport.localized("The session ended. Do you want to save the board image to your device gallery?") }
  var saveBoardLocalMessage: String { LocalizationSupport.localized("The board will be saved to the chat. Do you also want to save it to your device gallery?") }
  var endSessionActionLabel: String { LocalizationSupport.localized("End session") }
  var saveToGalleryLabel: String { LocalizationSupport.localized("Save to gallery") }
  var saveToChatOnlyLabel: String { LocalizationSupport.localized("Save to chat only") }
  var dontSaveLabel: String { LocalizationSupport.localized("Don't save") }
  var cancelLabel: String { LocalizationSupport.localized("Cancel") }

  // MARK: End-session button (header)

  var endLabel: String { LocalizationSupport.localized("End") }
  var endingLabel: String { LocalizationSupport.localized("Ending...") }

  // MARK: Text-transition overlay

  var switchingToTextChatText: String { LocalizationSupport.localized("Switching to text chat…") }

  // MARK: Video placeholders

  var waitingForVideoText: String { LocalizationSupport.localized("Waiting for video…") }

  // MARK: Session condition notice (header)

  /// Said when a video lesson had to start without a camera. The session is
  /// otherwise fine, so this explains the missing picture rather than warning.
  var cameraUnavailableNotice: String {
    LocalizationSupport.localized("Camera unavailable — this lesson is audio only.")
  }

  var weakConnectionNotice: String {
    LocalizationSupport.localized("Weak connection — audio and video may stutter.")
  }

  var lostConnectionNotice: String {
    LocalizationSupport.localized("Reconnecting…")
  }

  /// A lesson that went ahead by chat while its audio carries on connecting.
  var audioConnectingNotice: String {
    LocalizationSupport.localized("Audio is still connecting — you can chat meanwhile.")
  }

  var audioFailedNotice: String {
    LocalizationSupport.localized("Audio couldn't connect. Tap to try again.")
  }

  /// The other side is in the lesson without audio, so talking will not reach them.
  var peerAudioPendingNotice: String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    if isStudentRole {
      return LocalizationSupport.localized("Your teacher's audio isn't connected yet — use the chat.")
    }
    return LocalizationSupport.localized("The student's audio isn't connected yet — use the chat.")
  }

  // MARK: Peer-paused panel (role-dependent)

  var peerPausedMessage: String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    if isStudentRole {
      return LocalizationSupport.localized("Teacher is reading chat — video paused")
    }
    return LocalizationSupport.localized("Student is reading chat — video paused")
  }

  // MARK: Video badge

  var videoLabel: String { LocalizationSupport.localized("Video") }

  // MARK: Composer mode pills

  var regularModeLabel: String { LocalizationSupport.localized("Regular") }
  var algebraModeLabel: String { LocalizationSupport.localized("Algebra") }

  // MARK: Session stats

  var originalQuestionLabel: String { LocalizationSupport.localized("ORIGINAL QUESTION") }
  var sessionTimeLabel: String { LocalizationSupport.localized("Session Time") }
  var minutesLabel: String { LocalizationSupport.localized("minutes") }

  // MARK: Empty thread

  var emptyThreadHintText: String {
    LocalizationSupport.localized("Start with a text explanation, then use the board below for the math work.")
  }

  // MARK: Tab bar

  var chatTabTitle: String { LocalizationSupport.localized("Chat") }
  var boardTabTitle: String { LocalizationSupport.localized("Board") }
  var videoTabTitle: String { LocalizationSupport.localized("Video") }
  var imagesTabTitle: String { LocalizationSupport.localized("Images") }

  // MARK: Session type

  var sessionTypeTitle: String { LocalizationSupport.localized("Session type") }
  var changeSessionTypeLabel: String { LocalizationSupport.localized("Change") }
  var textSessionTypeLabel: String { LocalizationSupport.localized("Text") }
  var audioSessionTypeLabel: String { LocalizationSupport.localized("Audio") }
  var videoSessionTypeLabel: String { LocalizationSupport.localized("Video") }
  var switchSessionTypeLabel: String { LocalizationSupport.localized("Switch") }
  var notNowLabel: String { LocalizationSupport.localized("Not now") }
  var sessionTypeChangeFailedNotice: String {
    LocalizationSupport.localized("The session type could not be changed. Tap to dismiss.")
  }
  var mediaCredentialsFailedNotice: String {
    LocalizationSupport.localized("Could not start the audio/video connection. Please try again.")
  }

  /// Asks this side to follow the other one up to `conversationType`.
  func peerUpgradeTitle(for conversationType: String) -> String {
    conversationType == ConversationType.video.rawValue
      ? LocalizationSupport.localized("Switch to a video session?")
      : LocalizationSupport.localized("Switch to an audio session?")
  }

  func peerUpgradeMessage(for conversationType: String) -> String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    let isVideo = conversationType == ConversationType.video.rawValue
    switch (isStudentRole, isVideo) {
    case (true, true):
      return LocalizationSupport.localized("Your teacher switched the session to video.")
    case (true, false):
      return LocalizationSupport.localized("Your teacher switched the session to audio.")
    case (false, true):
      return LocalizationSupport.localized("The student switched the session to video.")
    case (false, false):
      return LocalizationSupport.localized("The student switched the session to audio.")
    }
  }

  // MARK: Connecting — the other side

  func peerSetupTitle(for prompt: PeerSetupPrompt) -> String {
    switch prompt {
    case .awaitingPermission: return waitingForPeerText
    case .cancelled: return peerCancelledTitle
    }
  }

  func peerSetupMessage(for prompt: PeerSetupPrompt) -> String {
    switch prompt {
    case .awaitingPermission(let kind): return peerPermissionMessage(for: kind)
    case .cancelled: return peerCancelledMessage
    }
  }

  /// Heads the permission question, and stays on screen as a reminder once
  /// this side chose to wait.
  var waitingForPeerText: String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    return isStudentRole
      ? LocalizationSupport.localized("Waiting for your teacher")
      : LocalizationSupport.localized("Waiting for the student")
  }

  func peerPermissionMessage(for kind: CapturePermissionKind) -> String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    switch (isStudentRole, kind) {
    case (true, .microphone):
      return LocalizationSupport.localized("Your teacher was asked to allow access to their microphone. Do you want to wait until they approve?")
    case (true, .camera):
      return LocalizationSupport.localized("Your teacher was asked to allow access to their camera. Do you want to wait until they approve?")
    case (false, .microphone):
      return LocalizationSupport.localized("The student was asked to allow access to their microphone. Do you want to wait until they approve?")
    case (false, .camera):
      return LocalizationSupport.localized("The student was asked to allow access to their camera. Do you want to wait until they approve?")
    }
  }

  var peerCancelledTitle: String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    return isStudentRole
      ? LocalizationSupport.localized("Your teacher cancelled the session.")
      : LocalizationSupport.localized("The student cancelled the session.")
  }

  var peerCancelledMessage: String {
    let isStudentRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student"
    return isStudentRole
      ? LocalizationSupport.localized("You can ask your question again.")
      : LocalizationSupport.localized("You can take the next question.")
  }

  var waitForPeerLabel: String { LocalizationSupport.localized("Wait") }
  var cancelSessionLabel: String { LocalizationSupport.localized("Cancel Session") }
}

@Observable
@MainActor
final class ChatSessionViewModel: ChatSessionViewModeling {
  let questionId: String
  let role: String
  var messages: [ChatMessage] = []
  var boardStrokes: [BoardStroke] = []
  var boardViewports: [String: BoardViewport] = [:]
  var chatPausedStates: [String: Bool] = [:]
  var mediaPendingStates: [String: Bool] = [:]
  var draft = ""
  var errorMessage: String?
  var isConnecting = true
  var details: ChatSessionDetails?
  var liveKitRoom: String
  var liveKitToken: String
  var lastSeenSharedConversationType = ""
  private(set) var isInSetup = true
  private(set) var hasUnreadChat = false
  private(set) var hasUnreadBoard = false
  private(set) var incomingFormulaCount = 0
  var isMicMuted = false
  var isCameraOff = false
  var participantName: String {
    if isTeacherRole {
	  return nonEmpty(details?.studentName) ?? LocalizationSupport.localized("Student")
    }
	return nonEmpty(details?.teacherName) ?? LocalizationSupport.localized("Teacher")
   
  }
  var participantImageURL: String {
    if isTeacherRole {
      return nonEmpty(details?.studentImageURL) ?? ""
    }
    return nonEmpty(details?.teacherImageURL) ?? ""
  }
  var currentUserImageURL: String {
    if isTeacherRole {
      return nonEmpty(details?.teacherImageURL) ?? ""
    }
    return nonEmpty(details?.studentImageURL) ?? ""
  }
  var originalQuestion: String {
    nonEmpty(details?.questionText) ?? LocalizationSupport.localized("Question details are loading.")
  }
  var questionPhotoUrls: [String] {
    details?.questionPhotoUrls ?? []
  }
  var primaryAmountTitle: String {
    LocalizationSupport.localized(isTeacherRole ? "Live Earnings" : "Session Cost")
  }
  var primaryAmountSubtitle: String {
    if isTeacherRole {
      return String(
        format: LocalizationSupport.localized("Your share (%d%%)"),
        teacherSharePercent
      )
    }
    return LocalizationSupport.localized("Total so far")
  }
  let sessionNoticeText = LocalizationSupport.localized("Session started - Billing active")
  var onChatPausedUpdated: (([String: Bool]) -> Void)?
  var onMediaPendingUpdated: (([String: Bool]) -> Void)?
  var onConnectingUpdated: ((Bool) -> Void)?
  var onSessionDetailsUpdated: (() -> Void)?
  var onSessionEnded: (() -> Void)?
  var boardRevision: String {
    boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  /// What the other side has said about its setup — see `PeerSetupTracker`.
  private(set) var peerSetup = PeerSetupTracker()
  var onPeerSetupUpdated: (() -> Void)?
  var peerSetupPrompt: PeerSetupPrompt? { peerSetup.prompt }
  var peerAwaitedPermission: CapturePermissionKind? { peerSetup.peerAwaitedPermission }

  private let service: ChatSessionService
  private var pollingTask: Task<Void, Never>?
  private var isWatchingPeerSetup = false
  private var peerSetupTask: Task<Void, Never>?
  /// This side's own `connectionSetup` entry as last written, and the write
  /// in flight. Writes are chained so they land in the order they were made.
  private var sentSetupSignal: ConnectionSetupSignal?
  private var setupSignalWrite: Task<Void, Never>?
  /// Set once this side ends or leaves the lesson itself, so the question going
  /// away afterwards is not taken for the other side leaving.
  private var isLeaving = false
  private var hasReportedLessonEnd = false
  private var hasReportedLessonStart = false
  private var didObserveActiveSession = false
  private var lastSentChatPaused: Bool?
  private var lastSentMediaPending: Bool?
  private var lastSentBoardViewport: BoardViewport?
  private var isChatVisible = true
  private var isBoardVisible = false

  init(
    questionId: String,
    role: String,
    initialDetails: ChatSessionDetails? = nil,
    liveKitRoom: String = "",
    liveKitToken: String = ""
  ) {
    self.questionId = questionId
    self.role = role
    self.liveKitRoom = liveKitRoom.trimmingCharacters(in: .whitespacesAndNewlines)
    self.liveKitToken = liveKitToken.trimmingCharacters(in: .whitespacesAndNewlines)
    self.details = initialDetails
    self.service = ChatSessionService(questionId: questionId)
  }

  func start() {
    logger.info("[ChatSession] start requested questionId=\(self.questionId) role=\(self.role)")
    isConnecting = true
    onConnectingUpdated?(true)
    Task {
      let didLoadSession = await loadSessionDetails()
      guard didLoadSession else {
        logger.info("[ChatSession] start blocked: session details unavailable questionId=\(self.questionId) role=\(self.role)")
        return
      }
      guard !Task.isCancelled else {
        logger.info("[ChatSession] start cancelled before connected questionId=\(self.questionId) role=\(self.role)")
        return
      }
      isConnecting = false
      onConnectingUpdated?(false)
      logger.info("[ChatSession] connected questionId=\(self.questionId) role=\(self.role)")
      beginListening()
      await reportLessonStarted()
    }
  }

  /// Tells the backend this participant is in the session.
  ///
  /// Nothing used to call `startLesson`, which left the lesson document
  /// uncreated, the 30-minute hard cap unarmed — it is scheduled by that call —
  /// and the billing clock running from the moment the teacher accepted rather
  /// than from when the two of them were actually together. It is also how the
  /// backend learns the student turned up at all: a lesson they never joined is
  /// written off after a grace period and charged to nobody.
  ///
  /// Both sides call it as they connect, and the backend treats the second
  /// arrival as ordinary. Best-effort: failing here must not throw anyone out
  /// of a session they are already connected to.
  private func reportLessonStarted() async {
    guard !hasReportedLessonStart else { return }
    guard let questionId = nonEmpty(self.questionId) else { return }
    hasReportedLessonStart = true

    do {
      let lessonId = try await FunctionsService.shared.startLesson(questionId: questionId)
      logger.info("[ChatSession] startLesson reported questionId=\(questionId) lessonId=\(lessonId)")
    } catch {
      logger.error(
        "[ChatSession] startLesson failed questionId=\(questionId): \(error.localizedDescription)"
      )
    }
  }

  private func loadSessionDetails() async -> Bool {
    do {
      if let updated = try await service.fetchSessionDetails() {
        didObserveActiveSession = true
        details = mergedDetails(current: details, updated: updated)
        await loadParticipantProfiles()
        onSessionDetailsUpdated?()
        logger.info("[ChatSession] details loaded questionId=\(self.questionId) role=\(self.role)")
        return true
      }
      if details != nil {
        logger.info("[ChatSession] using initial details questionId=\(self.questionId) role=\(self.role)")
        return true
      }
      errorMessage = LocalizationSupport.localized("Session is no longer available.")
      logger.info("[ChatSession] details missing questionId=\(self.questionId) role=\(self.role)")
      return false
    } catch {
      errorMessage = error.localizedDescription
      logger.error("[ChatSession] details failed questionId=\(self.questionId) role=\(self.role): \(error.localizedDescription)")
      return false
    }
  }

  private func beginListening() {
#if os(Android)
    pollingTask?.cancel()
    pollingTask = Task {
      while !Task.isCancelled {
        do {
          guard let updatedDetails = try await service.fetchSessionDetails() else {
            guard !Task.isCancelled else { return }
            await handleRemoteSessionEnded()
            return
          }
          didObserveActiveSession = true
          details = mergedDetails(current: details, updated: updatedDetails)
          onSessionDetailsUpdated?()
          let rows = try await service.fetchMessages()
          let strokes = try await service.fetchBoardStrokes()
          let viewports = try await service.fetchBoardViewports()
          let paused = try await service.fetchChatPaused()
          let mediaPending = try await service.fetchMediaPending()
          guard !Task.isCancelled else { return }
          receiveMessages(rows)
          receiveBoardStrokes(strokes)
          receiveBoardViewports(viewports)
          chatPausedStates = paused
          mediaPendingStates = mediaPending
          onChatPausedUpdated?(paused)
          onMediaPendingUpdated?(mediaPending)
        } catch {
          errorMessage = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
      }
    }
#else
    // A retried start must not stack a second set of observers on the first.
    service.stopListening()
    service.startSessionListening(
      onEnded: { [weak self] in
        Task { @MainActor in
          await self?.handleRemoteSessionEnded()
        }
      },
      onUpdate: { [weak self] updatedDetails in
        guard let self else { return }
        self.details = self.mergedDetails(current: self.details, updated: updatedDetails)
        self.onSessionDetailsUpdated?()
      }
    )
    service.startListening { [weak self] rows in
      self?.receiveMessages(rows)
    }
    service.startBoardListening { [weak self] strokes in
      self?.receiveBoardStrokes(strokes)
    }
    service.startBoardViewportListening { [weak self] viewports in
      self?.receiveBoardViewports(viewports)
    }
    service.startChatPausedListening { [weak self] states in
      self?.chatPausedStates = states
      self?.onChatPausedUpdated?(states)
    }
    service.startMediaPendingListening { [weak self] states in
      self?.mediaPendingStates = states
      self?.onMediaPendingUpdated?(states)
    }
#endif
  }

  // MARK: Incoming

  /// Takes the latest thread. Messages from the other side that were not in
  /// the last one are announced, and mark the chat unread when it is not on
  /// screen.
  private func receiveMessages(_ rows: [ChatMessage]) {
    guard rows != messages else { return }
    let previousIDs = Set(messages.map(\.id))
    let incoming = rows.filter { !$0.isMine && !previousIDs.contains($0.id) }
    if !incoming.isEmpty, !isChatVisible {
      hasUnreadChat = true
    }
    for message in incoming {
      LocalNotificationService.shared.scheduleChatMessage(
        questionId: questionId,
        message: message,
        currentRole: role
      )
    }
    if incoming.contains(where: { ChatBubble.containsFormula($0.text) }) {
      incomingFormulaCount += 1
    }
    messages = rows
    noteFarewell(in: rows)
  }

  private func receiveBoardStrokes(_ strokes: [BoardStroke]) {
    guard strokes != boardStrokes else { return }
    let previousIDs = Set(boardStrokes.map(\.id))
    if !isBoardVisible, strokes.contains(where: { !$0.isMine && !previousIDs.contains($0.id) }) {
      hasUnreadBoard = true
    }
    boardStrokes = strokes
  }

  private func receiveBoardViewports(_ viewports: [String: BoardViewport]) {
    guard viewports != boardViewports else { return }
    boardViewports = viewports
  }

  func sessionTabChanged(showsChat: Bool, showsBoard: Bool) {
    isChatVisible = showsChat
    isBoardVisible = showsBoard
    if showsChat { hasUnreadChat = false }
    if showsBoard { hasUnreadBoard = false }
  }

  func finishSetup() {
    isInSetup = false
  }

  func stop() {
    pollingTask?.cancel()
    pollingTask = nil
    stopWatchingPeerSetup()
    isConnecting = true
    onConnectingUpdated?(true)
    service.stopListening()
  }

  func send() {
    send(draft)
  }

  func primaryAmountText(at date: Date) -> String {
    let elapsedMinutes = Double(sessionDurationSeconds(at: date)) / 60.0
    let grossCents = elapsedMinutes * Double(pricePerMinuteCents)
    let cents = isTeacherRole ? grossCents * (teacherSharePercent / 100.0) : grossCents
    return currencyText(cents: max(0, cents))
  }

  func sessionTimeText(at date: Date) -> String {
    let seconds = sessionDurationSeconds(at: date)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  func messageTimeText(createdAt: Double, at date: Date) -> String {
    let createdAtMilliseconds = ChatSessionService.normalizedMilliseconds(createdAt)
    guard createdAtMilliseconds > 0 else { return LocalizationSupport.localized("Just now") }
    let elapsed = max(0, Int(date.timeIntervalSince1970 - createdAtMilliseconds / 1000.0))
    if elapsed < 60 {
      return elapsed == 1
        ? LocalizationSupport.localized("1 second ago")
        : String(format: LocalizationSupport.localized("%d seconds ago"), elapsed)
    }
    let minutes = elapsed / 60
    if minutes < 60 {
      return minutes == 1
        ? LocalizationSupport.localized("1 min ago")
        : String(format: LocalizationSupport.localized("%d min ago"), minutes)
    }
    let hours = minutes / 60
    if hours < 24 {
      return hours == 1
        ? LocalizationSupport.localized("1 hr ago")
        : String(format: LocalizationSupport.localized("%d hrs ago"), hours)
    }
    let days = hours / 24
    return days == 1
      ? LocalizationSupport.localized("1 day ago")
      : String(format: LocalizationSupport.localized("%d days ago"), days)
  }

  func localMessage(text: String) -> ChatMessage {
    ChatMessage(
      id: "local-\(Date().timeIntervalSince1970)",
      text: text,
      senderUid: Auth.auth().currentUser?.uid ?? "",
      senderRole: role,
      createdAt: Date().timeIntervalSince1970 * 1000.0,
      isMine: true
    )
  }

  func localStroke(points: [BoardPoint]) -> BoardStroke {
    BoardStroke(
      id: "local-\(Date().timeIntervalSince1970)",
      points: points,
      createdAt: Date().timeIntervalSince1970 * 1000.0,
      isMine: true
    )
  }

  func send(_ messageText: String) {
    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    // A held session is paused for both sides: nothing past the deadline is
    // billed, so nothing past it is taught either. The parting note goes out
    // through endLessonWithFarewell, which does not come through here.
    guard minutesHoldState(at: Date()) != .held else { return }
    errorMessage = nil
    // Shown at once; the next snapshot of the thread replaces it.
    messages.append(localMessage(text: text))
    Task {
      do {
        try await service.sendText(text, senderRole: role)
      } catch {
        errorMessage = error.localizedDescription
		logger.error("[ChatSession] Chat send failed: \(error.localizedDescription)")
      }
    }
  }

  func sendQuestionFormula(_ formulaText: String) {
    let text = formulaText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    send(text)

    guard role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "student" else { return }
    let currentText = details?.questionText ?? ""
    let localQuestionText = ChatSessionService.appendingQuestionText(addition: text, to: currentText)
    updateLocalQuestionText(localQuestionText)

    Task {
      do {
        let remoteQuestionText = try await service.appendQuestionText(text)
        updateLocalQuestionText(remoteQuestionText)
      } catch {
        errorMessage = error.localizedDescription
        logger.error("[ChatSession] Question formula append failed: \(error.localizedDescription)")
      }
    }
  }

  func sendStroke(_ points: [BoardPoint]) {
    guard !points.isEmpty else { return }
    guard !hasReportedLessonEnd else { return }
    errorMessage = nil
    boardStrokes.append(localStroke(points: points))
    Task {
      do {
        try await service.sendStroke(points)
      } catch {
        errorMessage = error.localizedDescription
		logger.error("[ChatSession] Board stroke send failed: \(error.localizedDescription)")
      }
    }
  }

  func clearBoard() {
    errorMessage = nil
    boardStrokes = []
    Task {
      do {
        try await service.clearBoard()
      } catch {
        errorMessage = error.localizedDescription
		logger.error("[ChatSession] Board clear failed: \(error.localizedDescription)")
      }
    }
  }

  func updateBoardViewport(_ viewport: BoardViewport) {
    // Once the lesson has ended the RTDB question node is removed/finalized by the
    // backend, so a late viewport write races into a permission_denied. Suppress
    // any board writes after the session has been reported ended.
    guard !hasReportedLessonEnd else { return }
    // A board being dragged reports every frame; only a real move goes out.
    if let previous = lastSentBoardViewport {
      let positionDelta = abs(previous.x - viewport.x) + abs(previous.y - viewport.y)
      let sizeDelta = abs(previous.width - viewport.width) + abs(previous.height - viewport.height)
      guard positionDelta > 2 || sizeDelta > 2 else { return }
    }
    lastSentBoardViewport = viewport
    Task {
      do {
        try await service.updateBoardViewport(viewport, role: role)
      } catch {
		logger.error("[ChatSession] Board viewport update failed: \(error.localizedDescription)")
      }
    }
  }

  func setSelfChatPaused(_ paused: Bool) {
    if lastSentChatPaused == paused { return }
    lastSentChatPaused = paused
    let selfKey = roleKey(role)
    chatPausedStates[selfKey] = paused
    Task {
      do {
        try await service.setChatPaused(paused, role: role)
      } catch {
        logger.error("[ChatSession] setChatPaused failed paused=\(paused): \(error.localizedDescription)")
      }
    }
  }

  func peerChatPaused() -> Bool {
    let selfKey = roleKey(role)
    for (key, value) in chatPausedStates where key != selfKey && value {
      return true
    }
    return false
  }

  /// Tells the other side this participant is in the lesson without audio —
  /// still connecting, or started by chat instead — so they type rather than
  /// talk. Nothing is written until there is something to say.
  func setSelfMediaPending(_ pending: Bool) {
    if (lastSentMediaPending ?? false) == pending { return }
    lastSentMediaPending = pending
    mediaPendingStates[roleKey(role)] = pending
    Task {
      do {
        try await service.setMediaPending(pending, role: role)
      } catch {
        logger.error("[ChatSession] setMediaPending failed pending=\(pending): \(error.localizedDescription)")
      }
    }
  }

  func peerMediaPending() -> Bool {
    let selfKey = roleKey(role)
    for (key, value) in mediaPendingStates where key != selfKey && value {
      return true
    }
    return false
  }

  private func roleKey(_ role: String) -> String {
    let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? "participant" : trimmed
  }

  // MARK: Connecting

  /// How often Android reads the other side's setup. iOS is told as it changes.
  private static let peerSetupPollNanos: UInt64 = 1_000_000_000
  /// How long this side leaves the other one to end a lesson it cancelled
  /// before ending it itself — see `acknowledgePeerCancelled`.
  private static let peerCancelSettleNanos: UInt64 = 10_000_000_000

  func startWatchingPeerSetup() {
    guard !isWatchingPeerSetup, !isLeaving else { return }
    isWatchingPeerSetup = true
    logger.info("[ChatSession] watching the other side's setup questionId=\(self.questionId) role=\(self.role)")
#if os(Android)
    peerSetupTask?.cancel()
    peerSetupTask = Task {
      while !Task.isCancelled {
        if let reading = try? await service.fetchConnectionSetup() {
          guard !Task.isCancelled else { return }
          receivePeerSetupSignals(reading.signals)
          if !reading.isLive {
            receiveQuestionEnded()
            return
          }
        }
        try? await Task.sleep(nanoseconds: Self.peerSetupPollNanos)
      }
    }
#else
    service.startConnectionSetupListening(
      onUpdate: { [weak self] signals in
        self?.receivePeerSetupSignals(signals)
      },
      onEnded: { [weak self] in
        self?.receiveQuestionEnded()
      }
    )
#endif
  }

  private func stopWatchingPeerSetup() {
    isWatchingPeerSetup = false
    peerSetupTask?.cancel()
    peerSetupTask = nil
    service.stopConnectionSetupListening()
  }

  private func receivePeerSetupSignals(_ signals: [String: String]) {
    guard isWatchingPeerSetup else { return }
    let peerKey = roleKey(role) == "teacher" ? "student" : "teacher"
    var updated = peerSetup
    updated.receive(signals[peerKey].flatMap(ConnectionSetupSignal.init(rawValue:)))
    applyPeerSetup(updated)
  }

  /// The question is gone, or over. Whether that means the other side left
  /// before the lesson started is `PeerSetupTracker`'s call.
  private func receiveQuestionEnded() {
    guard isWatchingPeerSetup, !isLeaving else { return }
    var updated = peerSetup
    updated.questionEnded(whileConnecting: isInSetup)
    applyPeerSetup(updated)
  }

  private func applyPeerSetup(_ updated: PeerSetupTracker) {
    guard updated != peerSetup else { return }
    if updated.peerCancelled, !peerSetup.peerCancelled {
      logger.info("[ChatSession] the other side left before the lesson started questionId=\(self.questionId) role=\(self.role)")
    }
    peerSetup = updated
    onPeerSetupUpdated?()
  }

  func setSelfAwaitingPermission(_ kind: CapturePermissionKind?) {
    guard !isLeaving else { return }
    sendSetupSignal(kind.map(ConnectionSetupSignal.awaiting))
  }

  func waitForPeerPermission() {
    var updated = peerSetup
    updated.waitForPeerPermission()
    applyPeerSetup(updated)
  }

  func cancelSetup() {
    guard !isLeaving else { return }
    isLeaving = true
    stopWatchingPeerSetup()
    logger.info("[ChatSession] leaving before the lesson started questionId=\(self.questionId) role=\(self.role)")
    let announcement = sendSetupSignal(.cancelled)
    Task {
      await LiveKitService.shared.disconnect()
      // Landed, and read, before the lesson is ended: that removes the
      // question, and the other side reads the signal there to know this was
      // a cancel rather than an ordinary end.
      await announcement?.value
      try? await Task.sleep(nanoseconds: ConnectionSetupSignal.cancelledAnnouncementNanos)
      await endLesson()
    }
  }

  func acknowledgePeerCancelled() {
    guard !isLeaving else { return }
    isLeaving = true
    stopWatchingPeerSetup()
    Task {
      await LiveKitService.shared.disconnect()
      // The other side ends the lesson as it leaves, and settling it from both
      // sides at once could bill it twice. So this side only steps in when that
      // end never arrived — the question is still there after a while.
      try? await Task.sleep(nanoseconds: Self.peerCancelSettleNanos)
      guard !hasReportedLessonEnd,
            (try? await service.fetchSessionDetails()) != nil else { return }
      logger.info("[ChatSession] the other side's end never arrived; ending the lesson questionId=\(self.questionId) role=\(self.role)")
      await reportLessonEnded()
    }
  }

  /// Writes this side's `connectionSetup` entry, after any write still in
  /// flight: a prompt that opens and closes quickly must not end with the
  /// "waiting" write landing last. Nil when there is nothing new to write.
  @discardableResult
  private func sendSetupSignal(_ signal: ConnectionSetupSignal?) -> Task<Void, Never>? {
    guard signal != sentSetupSignal else { return nil }
    sentSetupSignal = signal
    let previous = setupSignalWrite
    let write = Task {
      await previous?.value
      do {
        try await service.setConnectionSetupSignal(signal, role: role)
      } catch {
        logger.error("[ChatSession] setConnectionSetupSignal failed signal=\(signal?.rawValue ?? "none"): \(error.localizedDescription)")
      }
    }
    setupSignalWrite = write
    return write
  }

  func endLesson() async {
    isLeaving = true
    setSelfChatPaused(false)
    setSelfMediaPending(false)
    await reportLessonEnded()
    await LiveKitService.shared.disconnect()
    stop()
  }

  /// Warn a minute before the student's credit runs out, so they can top up
  /// before the session is interrupted at all.
  private static let minutesWarningSeconds: Double = 60

  func minutesHoldState(at date: Date) -> MinutesHoldState {
    // Zero means the backend published no allowance — a lesson that started
    // before this existed runs as it always did.
    guard let deadlineMs = details?.minutesDeadlineAt, deadlineMs > 0 else { return .none }

    let secondsLeft = deadlineMs / 1000.0 - date.timeIntervalSince1970
    if secondsLeft <= 0 { return .held }
    return secondsLeft <= Self.minutesWarningSeconds ? .warning : .none
  }

  /// The other side's parting note, once it has arrived. Read when the session
  /// ends: the note is shown to them before the screen closes, rather than
  /// flashing past in a chat that is about to disappear.
  private(set) var peerFarewellNote: String?

  /// Remembers a parting note the moment it lands, because it arrives just
  /// ahead of the session ending and the chat is torn down with it.
  private func noteFarewell(in rows: [ChatMessage]) {
    guard let note = rows.last(where: { $0.kind == ChatMessage.farewellKind && !$0.isMine }) else {
      return
    }
    peerFarewellNote = note.text
  }

  func endLessonWithFarewell(_ message: String) async {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      do {
        try await service.sendText(
          String(trimmed.prefix(farewellMessageMaxLength)),
          senderRole: role,
          // Flagged so the other side can show it rather than let it scroll
          // past: it lands in both chats either way.
          kind: ChatMessage.farewellKind
        )
      } catch {
        // The call is ending either way; a note that failed to send must not
        // strand the student in a session they have already left.
        logger.error(
          "[ChatSession] farewell failed questionId=\(self.questionId): \(error.localizedDescription)"
        )
      }
    }
    await endLesson()
  }

  private func handleRemoteSessionEnded() async {
	logger.info("[ChatSession] handleRemoteSessionEnded")
    guard didObserveActiveSession || details != nil else { return }
    // Settled before anything is torn down: the screen reads it to tell the
    // other side leaving before the lesson started from an ordinary end.
    receiveQuestionEnded()
    await reportLessonEnded()
    await LiveKitService.shared.disconnect()
    stop()
    onSessionEnded?()
  }

  private func reportLessonEnded() async {
    guard !hasReportedLessonEnd else { return }
    hasReportedLessonEnd = true

    do {
      guard let questionId = nonEmpty(self.questionId) else {
        logger.error("[ChatSession] cannot report endLesson without questionId questionId=\(self.questionId)")
        return
      }
      try await FunctionsService.shared.endLesson(questionId: self.questionId)
      logger.info("[ChatSession] endLesson reported questionId=\(questionId)")
    } catch {
      errorMessage = error.localizedDescription
      logger.error("[ChatSession] endLesson failed questionId=\(self.questionId): \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "ChatSession.endLesson")
    }
  }

  private var isTeacherRole: Bool {
    if let currentUid = nonEmpty(Auth.auth().currentUser?.uid) {
      if let teacherId = nonEmpty(details?.teacherId), currentUid == teacherId {
        return true
      }
      if let studentId = nonEmpty(details?.studentId), currentUid == studentId {
        return false
      }
    }
    return role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "teacher"
  }

  private var pricePerMinuteCents: Int {
    details?.pricePerMinuteCents ?? 0
  }

  private var teacherSharePercent: Double {
    details?.teacherSharePercent ?? 75
  }

  func sessionDurationSeconds(at date: Date) -> Int {
    let startMilliseconds = details?.acceptedAt ?? 0
    guard startMilliseconds > 0 else { return 0 }
    return max(0, Int(date.timeIntervalSince1970 - startMilliseconds / 1000.0))
  }

  var teacherId: String {
    nonEmpty(details?.teacherId) ?? ""
  }

  private func currencyText(cents: Double) -> String {
    LessonFormatting.currencyText(cents: Int(cents.rounded()), currencyCode: details?.currencyCode ?? LessonFormatting.defaultCurrencyCode)
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private func mergedDetails(current: ChatSessionDetails?, updated: ChatSessionDetails) -> ChatSessionDetails {
    if let published = publishedConversationType,
       updated.conversationType == published
        || Date().timeIntervalSince(publishedConversationTypeAt) > Self.publishedConversationTypeGraceSeconds {
      publishedConversationType = nil
    }
    guard let current else { return updated }
    return ChatSessionDetails(
      questionId: nonEmpty(updated.questionId) ?? current.questionId,
      studentId: nonEmpty(updated.studentId) ?? current.studentId,
      teacherId: nonEmpty(updated.teacherId) ?? current.teacherId,
      studentName: nonEmpty(updated.studentName) ?? current.studentName,
      teacherName: nonEmpty(updated.teacherName) ?? current.teacherName,
      studentImageURL: nonEmpty(updated.studentImageURL) ?? current.studentImageURL,
      teacherImageURL: nonEmpty(updated.teacherImageURL) ?? current.teacherImageURL,
      questionText: nonEmpty(updated.questionText) ?? current.questionText,
      questionPhotoUrls: updated.questionPhotoUrls.isEmpty ? current.questionPhotoUrls : updated.questionPhotoUrls,
      createdAt: updated.createdAt > 0 ? updated.createdAt : current.createdAt,
      acceptedAt: updated.acceptedAt > 0 ? updated.acceptedAt : current.acceptedAt,
      pricePerMinuteCents: updated.pricePerMinuteCents > 0 ? updated.pricePerMinuteCents : current.pricePerMinuteCents,
      teacherSharePercent: updated.teacherSharePercent > 0 ? updated.teacherSharePercent : current.teacherSharePercent,
      currencyCode: nonEmpty(updated.currencyCode) ?? current.currencyCode,
      // A later snapshot that omits the deadline must not clear a known one:
      // the hold would lift itself and the student would keep talking for free.
      minutesDeadlineAt: updated.minutesDeadlineAt > 0
        ? updated.minutesDeadlineAt
        : current.minutesDeadlineAt,
      conversationType: nonEmpty(updated.conversationType) ?? current.conversationType
    )
  }

  private func updateLocalQuestionText(_ questionText: String) {
    guard let current = details else { return }
    let trimmed = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != current.questionText else { return }
    details = ChatSessionDetails(
      questionId: current.questionId,
      studentId: current.studentId,
      teacherId: current.teacherId,
      studentName: current.studentName,
      teacherName: current.teacherName,
      studentImageURL: current.studentImageURL,
      teacherImageURL: current.teacherImageURL,
      questionText: trimmed,
      questionPhotoUrls: current.questionPhotoUrls,
      createdAt: current.createdAt,
      acceptedAt: current.acceptedAt,
      pricePerMinuteCents: current.pricePerMinuteCents,
      teacherSharePercent: current.teacherSharePercent,
      currencyCode: current.currencyCode,
      minutesDeadlineAt: current.minutesDeadlineAt,
      conversationType: current.conversationType
    )
    onSessionDetailsUpdated?()
  }

  private func loadParticipantProfiles() async {
    guard let current = details,
          let currentUserId = nonEmpty(Auth.auth().currentUser?.uid) else { return }
    var studentName = current.studentName
    var teacherName = current.teacherName
    var studentImageURL = current.studentImageURL
    var teacherImageURL = current.teacherImageURL

    if currentUserId == nonEmpty(current.studentId),
       let profile = try? await UserService.shared.fetchProfileSummary(uid: currentUserId) {
      if nonEmpty(studentName) == nil {
        studentName = profile.displayName
      }
      if nonEmpty(studentImageURL) == nil {
        studentImageURL = profile.profileImageURL
      }
    }

    if currentUserId == nonEmpty(current.teacherId),
       let profile = try? await UserService.shared.fetchProfileSummary(uid: currentUserId) {
      if nonEmpty(teacherName) == nil {
        teacherName = profile.displayName
      }
      if nonEmpty(teacherImageURL) == nil {
        teacherImageURL = profile.profileImageURL
      }
    }

    guard studentName != current.studentName
            || teacherName != current.teacherName
            || studentImageURL != current.studentImageURL
            || teacherImageURL != current.teacherImageURL else { return }
    details = ChatSessionDetails(
      questionId: current.questionId,
      studentId: current.studentId,
      teacherId: current.teacherId,
      studentName: studentName,
      teacherName: teacherName,
      studentImageURL: studentImageURL,
      teacherImageURL: teacherImageURL,
      questionText: current.questionText,
      questionPhotoUrls: current.questionPhotoUrls,
      createdAt: current.createdAt,
      acceptedAt: current.acceptedAt,
      pricePerMinuteCents: current.pricePerMinuteCents,
      teacherSharePercent: current.teacherSharePercent,
      currencyCode: current.currencyCode,
      minutesDeadlineAt: current.minutesDeadlineAt,
      conversationType: current.conversationType
    )
  }

  /// A switch this side wrote, reported as the shared medium until a read of
  /// the node agrees. On Android a poll that set off before the write can
  /// still come back with the old medium, which would otherwise look like the
  /// other side switching straight back.
  private var publishedConversationType: String?
  private var publishedConversationTypeAt = Date.distantPast
  private static let publishedConversationTypeGraceSeconds: TimeInterval = 5

  var sharedConversationType: String {
    publishedConversationType ?? details?.conversationType ?? ""
  }

  func prepareMedia(for conversationType: String) async -> String? {
    guard let type = ConversationType(rawValue: conversationType) else { return nil }

    if type.requiresMic {
      let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
      if !micState.isGranted {
        AnalyticsService.shared.logEvent(AnalyticsEvent.permissionDenied, parameters: [
          "permission_type": "microphone",
          "conversation_type": conversationType
        ])
        return type == .video
          ? LocalizationSupport.localized("Microphone and camera access are required for this video session.")
          : LocalizationSupport.localized("Microphone access is required for this audio session.")
      }
    }

    if type.requiresCamera {
      let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
      if !cameraState.isGranted {
        AnalyticsService.shared.logEvent(AnalyticsEvent.permissionDenied, parameters: [
          "permission_type": "camera",
          "conversation_type": conversationType
        ])
        return LocalizationSupport.localized("Microphone and camera access are required for this video session.")
      }
    }

    return nil
  }

  func publishConversationType(_ conversationType: String) async -> String? {
    guard ConversationType(rawValue: conversationType) != nil else { return nil }
    let previous = sharedConversationType
    publishedConversationType = conversationType
    publishedConversationTypeAt = Date()
    do {
      try await service.setConversationType(conversationType)
      publishedConversationTypeAt = Date()
      AnalyticsService.shared.logEvent(AnalyticsEvent.sessionTypeChanged, parameters: [
        "question_id": questionId,
        "role": role,
        "from_conversation_type": previous,
        "conversation_type": conversationType
      ])
      logger.info("[ChatSession] conversation type changed questionId=\(self.questionId) role=\(self.role) from=\(previous) to=\(conversationType)")
      return nil
    } catch {
      publishedConversationType = nil
      logger.error("[ChatSession] conversation type change failed questionId=\(self.questionId) to=\(conversationType): \(error.localizedDescription)")
      return sessionTypeChangeFailedNotice
    }
  }

  func fetchMediaCredentials() async -> MediaCredentials? {
    do {
      let result = try await FunctionsService.shared.getQuestionStatus(questionId: questionId)
      guard let room = nonEmpty(result.liveKitRoom), let token = nonEmpty(result.liveKitToken) else {
        logger.error("[ChatSession] media credentials missing questionId=\(self.questionId) status=\(result.status)")
        return nil
      }
      return MediaCredentials(room: room, token: token)
    } catch {
      logger.error("[ChatSession] media credentials failed questionId=\(self.questionId): \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: Media

  var mediaConnectionPhase: MediaConnectionPhase { LiveKitService.shared.connectionPhase }

  var mediaDidFallBackToAudioOnly: Bool { LiveKitService.shared.didFallBackToAudioOnly }

  func mediaQuality() -> SessionMediaQuality {
    LiveKitService.shared.currentMediaQuality()
  }

  func connectMedia(enableVideo: Bool) {
    logger.info("[ChatSession] connecting media questionId=\(self.questionId) role=\(self.role) video=\(enableVideo)")
    LiveKitService.shared.startConnecting(roomName: liveKitRoom, token: liveKitToken, enableVideo: enableVideo)
  }

  func waitUntilMediaConnected() async -> Bool {
    await LiveKitService.shared.waitUntilConnected()
  }

  func disconnectMedia() async {
    await LiveKitService.shared.disconnect()
  }

  func setMicrophoneEnabled(_ enabled: Bool) async {
    await LiveKitService.shared.setMicrophoneEnabled(enabled)
  }

  func setCameraEnabled(_ enabled: Bool) async {
    await LiveKitService.shared.setCameraEnabled(enabled)
  }

#if !os(Android)
  var onMediaTracksUpdated: (@MainActor @Sendable () -> Void)? {
    get { LiveKitService.shared.onTracksUpdated }
    set { LiveKitService.shared.onTracksUpdated = newValue }
  }

  var localCameraVideoTrack: VideoTrack? { LiveKitService.shared.localCameraVideoTrack }

  var remoteCameraVideoTrack: VideoTrack? { LiveKitService.shared.remoteCameraVideoTrack }
#else
  /// Android draws video through its own bridge and reports no track changes.
  var onMediaTracksUpdated: (@MainActor @Sendable () -> Void)?
#endif

  func logSessionStarted(conversationType: String) {
    AnalyticsService.shared.logEvent(AnalyticsEvent.studentChatStarted, parameters: [
      "question_id": questionId,
      "role": role,
      "conversation_type": conversationType
    ])
  }

#if !os(Android)
  func sendBoardSnapshot(_ snapshotData: Data, senderRole: String) async throws {
    let url = try await StorageService.shared.uploadBoardSnapshot(data: snapshotData, questionId: questionId)
    let service = ChatSessionService(questionId: questionId)
    try await service.sendImage(downloadURL: url, senderRole: senderRole)
  }
#endif
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
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let appendQuestionTextMethod = managerClass.getStaticMethodID(
    name: "appendQuestionText",
    sig: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"
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
  private static let fetchBoardViewportsMethod = managerClass.getStaticMethodID(
    name: "fetchBoardViewportsJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let updateBoardViewportMethod = managerClass.getStaticMethodID(
    name: "updateBoardViewport",
    sig: "(Ljava/lang/String;Ljava/lang/String;DDDD)V"
  )!
  private static let setChatPausedMethod = managerClass.getStaticMethodID(
    name: "setChatPaused",
    sig: "(Ljava/lang/String;Ljava/lang/String;Z)V"
  )!
  private static let fetchChatPausedMethod = managerClass.getStaticMethodID(
    name: "fetchChatPausedJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let setMediaPendingMethod = managerClass.getStaticMethodID(
    name: "setMediaPending",
    sig: "(Ljava/lang/String;Ljava/lang/String;Z)V"
  )!
  private static let setConversationTypeMethod = managerClass.getStaticMethodID(
    name: "setConversationType",
    sig: "(Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let fetchMediaPendingMethod = managerClass.getStaticMethodID(
    name: "fetchMediaPendingJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let setConnectionSetupSignalMethod = managerClass.getStaticMethodID(
    name: "setConnectionSetupSignal",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let fetchConnectionSetupMethod = managerClass.getStaticMethodID(
    name: "fetchConnectionSetupJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let markQuestionAcceptedMethod = managerClass.getStaticMethodID(
    name: "markQuestionAccepted",
    sig: "(Ljava/lang/String;Ljava/lang/String;)V"
  )!
  private static let fetchSessionDetailsMethod = managerClass.getStaticMethodID(
    name: "fetchSessionDetailsJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
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

  static func sendText(questionId: String, text: String, senderRole: String, kind: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: sendMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          text.toJavaParameter(options: [.kotlincompat]),
          senderRole.toJavaParameter(options: [.kotlincompat]),
          kind.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func appendQuestionText(questionId: String, addition: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: appendQuestionTextMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          addition.toJavaParameter(options: [.kotlincompat])
        ]
      )
    } as String
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

  static func fetchBoardViewports(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchBoardViewportsMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func updateBoardViewport(
    questionId: String,
    role: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) throws {
    try jniContext {
      try managerClass.callStatic(
        method: updateBoardViewportMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          role.toJavaParameter(options: [.kotlincompat]),
          x.toJavaParameter(options: [.kotlincompat]),
          y.toJavaParameter(options: [.kotlincompat]),
          width.toJavaParameter(options: [.kotlincompat]),
          height.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func setChatPaused(questionId: String, role: String, paused: Bool) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setChatPausedMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          role.toJavaParameter(options: [.kotlincompat]),
          paused.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func fetchChatPaused(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchChatPausedMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func setMediaPending(questionId: String, role: String, pending: Bool) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setMediaPendingMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          role.toJavaParameter(options: [.kotlincompat]),
          pending.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func setConversationType(questionId: String, conversationType: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setConversationTypeMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          conversationType.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func fetchMediaPending(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchMediaPendingMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  /// An empty `signal` removes this side's entry.
  static func setConnectionSetupSignal(questionId: String, role: String, signal: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: setConnectionSetupSignalMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          role.toJavaParameter(options: [.kotlincompat]),
          signal.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func fetchConnectionSetup(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchConnectionSetupMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func markQuestionAccepted(questionId: String, teacherId: String) throws {
    try jniContext {
      try managerClass.callStatic(
        method: markQuestionAcceptedMethod,
        options: [.kotlincompat],
        args: [
          questionId.toJavaParameter(options: [.kotlincompat]),
          teacherId.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }

  static func fetchSessionDetails(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchSessionDetailsMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }
}
#endif
