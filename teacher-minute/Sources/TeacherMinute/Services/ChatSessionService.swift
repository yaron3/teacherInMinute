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
  let isMine: Bool
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

struct ChatSessionDetails: Equatable {
  let questionId: String
  let studentId: String
  let teacherId: String
  let studentName: String
  let teacherName: String
  let studentImageURL: String
  let teacherImageURL: String
  let questionText: String
  let createdAt: Double
  let acceptedAt: Double
  let connectionFeeCents: Int
  let pricePerMinuteCents: Int
  let teacherSharePercent: Double
  let currencyCode: String
}

@MainActor
final class ChatSessionService {
  private let questionId: String
  private let currentUserUid: String
#if !os(Android)
  private let questionRef: FirebaseDatabase.DatabaseReference
  private let messagesRef: FirebaseDatabase.DatabaseReference
  private let boardRef: FirebaseDatabase.DatabaseReference
  private var sessionHandle: DatabaseHandle?
  private var messagesHandle: DatabaseHandle?
  private var boardHandle: DatabaseHandle?
#endif

  init(questionId: String, currentUserUid: String? = nil) {
    self.questionId = questionId
    self.currentUserUid = currentUserUid ?? Auth.auth().currentUser?.uid ?? ""
#if !os(Android)
    let questionRef = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    self.questionRef = questionRef
    self.messagesRef = questionRef.child("messages")
    self.boardRef = questionRef.child("board/strokes")
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

  func startSessionListening(onEnded: @escaping () -> Void) {
#if !os(Android)
    sessionHandle = questionRef.observe(.value) { snapshot in
      if !snapshot.exists() {
        onEnded()
        return
      }
      if let dict = snapshot.value as? [String: Any],
         Self.isTerminalStatus(dict["status"]) {
        onEnded()
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
      isMine: senderUid == currentUserUid
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
      createdAt: normalizedMilliseconds(doubleValue(dict["createdAt"]) ?? 0),
      acceptedAt: normalizedMilliseconds(
        doubleValue(dict["acceptedAt"])
          ?? doubleValue(dict["connectedAt"])
          ?? doubleValue(dict["startedAt"])
          ?? 0
      ),
      connectionFeeCents: intValue(dict["connectionFeeCents"]) ?? intValue(dict["connectionFee"]) ?? 0,
      pricePerMinuteCents: intValue(dict["pricePerMinuteCents"])
        ?? intValue(dict["ratePerMinuteCents"])
        ?? intValue(dict["costPerMinuteCents"])
        ?? 0,
      teacherSharePercent: doubleValue(dict["teacherSharePercent"]) ?? doubleValue(dict["teacherShare"]) ?? 75,
      currencyCode: currencyCode(from: dict)
    )
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
  var messages: [ChatMessage] { get set }
  var boardStrokes: [BoardStroke] { get set }
  var errorMessage: String? { get set }
  var isConnecting: Bool { get set }
  var participantName: String { get }
  var participantImageURL: String { get }
  var currentUserImageURL: String { get }
  var originalQuestion: String { get }
  var primaryAmountTitle: String { get }
  var primaryAmountSubtitle: String { get }
  var sessionNoticeText: String { get }
  var onMessagesUpdated: (([ChatMessage]) -> Void)? { get set }
  var onBoardStrokesUpdated: (([BoardStroke]) -> Void)? { get set }
  var onErrorUpdated: ((String?) -> Void)? { get set }
  var onConnectingUpdated: ((Bool) -> Void)? { get set }
  var onSessionDetailsUpdated: (() -> Void)? { get set }
  var onSessionEnded: (() -> Void)? { get set }

  func start()
  func stop()
  func primaryAmountText(at date: Date) -> String
  func sessionTimeText(at date: Date) -> String
  func messageTimeText(createdAt: Double, at date: Date) -> String
  func localMessage(text: String) -> ChatMessage
  func localStroke(points: [BoardPoint]) -> BoardStroke
  func send(_ messageText: String)
  func sendStroke(_ points: [BoardPoint])
  func clearBoard()
  func endLesson() async
}

@Observable
@MainActor
final class ChatSessionViewModel: ChatSessionViewModeling {
  let questionId: String
  let role: String
  var messages: [ChatMessage] = []
  var boardStrokes: [BoardStroke] = []
  var draft = ""
  var errorMessage: String?
  var isConnecting = true
  var details: ChatSessionDetails?
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
  var primaryAmountTitle: String {
    LocalizationSupport.localized(isTeacherRole ? "Live Earnings" : "Session Cost")
  }
  var primaryAmountSubtitle: String {
    if isTeacherRole {
      return String(
        format: LocalizationSupport.localized("Your share (%lld%%)"),
        Int64(teacherSharePercent)
      )
    }
    return LocalizationSupport.localized("Total so far")
  }
  let sessionNoticeText = LocalizationSupport.localized("Session started - Billing active")
  var onMessagesUpdated: (([ChatMessage]) -> Void)?
  var onBoardStrokesUpdated: (([BoardStroke]) -> Void)?
  var onErrorUpdated: ((String?) -> Void)?
  var onConnectingUpdated: ((Bool) -> Void)?
  var onSessionDetailsUpdated: (() -> Void)?
  var onSessionEnded: (() -> Void)?
  var boardRevision: String {
    boardStrokes.map { "\($0.id):\($0.points.count)" }.joined(separator: "|")
  }

  private let service: ChatSessionService
  private var pollingTask: Task<Void, Never>?
  private var hasReportedLessonEnd = false
  private var didObserveActiveSession = false

  init(questionId: String, role: String, initialDetails: ChatSessionDetails? = nil) {
    self.questionId = questionId
    self.role = role
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
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      guard !Task.isCancelled else {
        logger.info("[ChatSession] start cancelled before connected questionId=\(self.questionId) role=\(self.role)")
        return
      }
      isConnecting = false
      onConnectingUpdated?(false)
      logger.info("[ChatSession] connected questionId=\(self.questionId) role=\(self.role)")
      beginListening()
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
      onErrorUpdated?(errorMessage)
      logger.info("[ChatSession] details missing questionId=\(self.questionId) role=\(self.role)")
      return false
    } catch {
      errorMessage = error.localizedDescription
      onErrorUpdated?(errorMessage)
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
          if try await service.fetchSessionDetails() == nil {
            guard !Task.isCancelled else { return }
            await handleRemoteSessionEnded()
            return
          }
          didObserveActiveSession = true
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
    service.startSessionListening { [weak self] in
      Task { @MainActor in
        await self?.handleRemoteSessionEnded()
      }
    }
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
    isConnecting = true
    onConnectingUpdated?(true)
    service.stopListening()
  }

  func send() {
    send(draft)
  }

  func primaryAmountText(at date: Date) -> String {
    let elapsedMinutes = Double(sessionDurationSeconds(at: date)) / 60.0
    let grossCents = Double(connectionFeeCents) + elapsedMinutes * Double(pricePerMinuteCents)
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
        : String(format: LocalizationSupport.localized("%lld seconds ago"), Int64(elapsed))
    }
    let minutes = elapsed / 60
    if minutes < 60 {
      return minutes == 1
        ? LocalizationSupport.localized("1 min ago")
        : String(format: LocalizationSupport.localized("%lld min ago"), Int64(minutes))
    }
    let hours = minutes / 60
    if hours < 24 {
      return hours == 1
        ? LocalizationSupport.localized("1 hr ago")
        : String(format: LocalizationSupport.localized("%lld hrs ago"), Int64(hours))
    }
    let days = hours / 24
    return days == 1
      ? LocalizationSupport.localized("1 day ago")
      : String(format: LocalizationSupport.localized("%lld days ago"), Int64(days))
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

  func endLesson() async {
    await reportLessonEnded()
    await LiveKitService.shared.disconnect()
    stop()
  }

  private func handleRemoteSessionEnded() async {
    guard didObserveActiveSession || details != nil else { return }
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
      onErrorUpdated?(errorMessage)
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

  private var connectionFeeCents: Int {
    details?.connectionFeeCents ?? 0
  }

  private var pricePerMinuteCents: Int {
    details?.pricePerMinuteCents ?? 0
  }

  private var teacherSharePercent: Double {
    details?.teacherSharePercent ?? 75
  }

  private func sessionDurationSeconds(at date: Date) -> Int {
    let startMilliseconds = details?.acceptedAt ?? 0
    guard startMilliseconds > 0 else { return 0 }
    return max(0, Int(date.timeIntervalSince1970 - startMilliseconds / 1000.0))
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
      createdAt: updated.createdAt > 0 ? updated.createdAt : current.createdAt,
      acceptedAt: updated.acceptedAt > 0 ? updated.acceptedAt : current.acceptedAt,
      connectionFeeCents: updated.connectionFeeCents > 0 ? updated.connectionFeeCents : current.connectionFeeCents,
      pricePerMinuteCents: updated.pricePerMinuteCents > 0 ? updated.pricePerMinuteCents : current.pricePerMinuteCents,
      teacherSharePercent: updated.teacherSharePercent > 0 ? updated.teacherSharePercent : current.teacherSharePercent,
      currencyCode: nonEmpty(updated.currencyCode) ?? current.currencyCode
    )
  }

  private func loadParticipantProfiles() async {
    guard let current = details else { return }
    var studentName = current.studentName
    var teacherName = current.teacherName
    var studentImageURL = current.studentImageURL
    var teacherImageURL = current.teacherImageURL

    if let uid = nonEmpty(current.studentId),
       let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      if nonEmpty(studentName) == nil {
        studentName = profile.displayName
      }
      if nonEmpty(studentImageURL) == nil {
        studentImageURL = profile.profileImageURL
      }
    }

    if let uid = nonEmpty(current.teacherId),
       let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
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
      createdAt: current.createdAt,
      acceptedAt: current.acceptedAt,
      connectionFeeCents: current.connectionFeeCents,
      pricePerMinuteCents: current.pricePerMinuteCents,
      teacherSharePercent: current.teacherSharePercent,
      currencyCode: current.currencyCode
    )
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
