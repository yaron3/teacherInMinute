//
//  TeacherPresenceService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 08/05/2026.
//

import Foundation

// iOS: use the real FirebaseDatabase SDK.
// Android: FirebaseDatabaseBridge.swift provides matching Swift wrappers
//          that delegate to the Android Firebase Realtime Database API.
#if !SKIP_BRIDGE
#if !os(Android)
import FirebaseDatabase
private typealias FRTDB = FirebaseDatabase.Database
private typealias DBRef  = FirebaseDatabase.DatabaseReference
#else
// On Android the types come from FirebaseDatabaseBridge.swift (same module).
private typealias FRTDB = Database
private typealias DBRef  = DatabaseReference
#endif
#endif

// MARK: - TeacherPresenceService
//
// Manages two Firebase Realtime Database responsibilities for a logged-in teacher:
//   1. Presence – writes online / offline status to  `teachers/{uid}/status`
//   2. Live queue – observes `teachers/{uid}/waitingMessages` and publishes changes
//      via an `onMessagesUpdated` callback so the ViewModel can react.

@MainActor
final class TeacherPresenceService {
  
  // MARK: - Properties
  
  private let teacherUID: String
  
#if !SKIP_BRIDGE
  /// Root reference for this teacher: `teachers/{uid}`
  private let teacherRef: DBRef
#endif
  
  private var messagesHandle: UInt?
  
  /// Called every time the waiting-messages list changes in the DB.
  var onMessagesUpdated: (([WaitingMessage]) -> Void)?
  
  // MARK: - Init
  
  init(teacherUID: String) {
	self.teacherUID = teacherUID
#if !SKIP_BRIDGE
	self.teacherRef = FRTDB.database()
	  .reference(withPath: "teachers/\(teacherUID)")
#endif
  }
  
  // Note: no deinit — goOffline() is the explicit teardown path and handles
  // observer removal.  Firebase also cleans up observers on app termination.
  
  // MARK: - Presence
  
  func goOnline() {
#if !SKIP_BRIDGE
	teacherRef.child("status").setValue("online")
	startListeningToQueue(ref: teacherRef.child("waitingMessages"))
#endif
  }
  
  func goOffline() {
#if !SKIP_BRIDGE
	teacherRef.child("status").setValue("offline")
	stopListeningToQueue()
#endif
  }
  
  // MARK: - Live Queue Listener
  
#if !SKIP_BRIDGE
  private func startListeningToQueue(ref: DBRef) {
	messagesHandle = ref.observe(.value) { [weak self] snapshot in
	  guard let self else { return }
	  var messages: [WaitingMessage] = []
	  
	  for child in snapshot.children {
		guard
		  let snap = child as? DataSnapshot,
		  let dict = snap.value as? [String: Any],
		  let msg  = WaitingMessage(id: snap.key, data: dict),
		  msg.status == .waiting
		else { continue }
		messages.append(msg)
	  }
	  
	  messages.sort { $0.createdAt < $1.createdAt }
	  
	  // Dispatch to main actor. The trailing `()` forces the closure
	  // return type to Void/Unit in both Swift and Kotlin (Skip).
	  Task { @MainActor [weak self] in self?.onMessagesUpdated?(messages) }
	  ()
	}
  }
  
  private func stopListeningToQueue() {
	guard let handle = messagesHandle else { return }
	teacherRef.child("waitingMessages").removeObserver(withHandle: handle)
	messagesHandle = nil
  }
#endif
  
  // MARK: - Accept / Reject
  
  func accept(message: WaitingMessage) async {
#if !SKIP_BRIDGE
	updateStatus(of: message, to: .accepted)
	await startSession(for: message)
#endif
  }
  
  func reject(message: WaitingMessage) {
#if !SKIP_BRIDGE
	updateStatus(of: message, to: .rejected)
#endif
  }
  
  // MARK: - Helpers
  
#if !SKIP_BRIDGE
  private func updateStatus(of message: WaitingMessage, to status: WaitingMessage.MessageStatus) {
	teacherRef
	  .child("waitingMessages")
	  .child(message.id)
	  .child("status")
	  .setValue(status.rawValue)
  }
  
  // MARK: - HTTP Session Placeholder
  
  /// Placeholder HTTP call that would notify your backend to spin up a tutoring session.
  /// Replace the URL and body with your real API contract.
  private func startSession(for message: WaitingMessage) async {
	guard let url = URL(string: "https://api.teacherminute.com/v1/sessions/start") else { return }
	
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	
	let body: [String: Any] = [
	  "teacherUID":  teacherUID,
	  "studentUID":  message.studentUID,
	  "messageID":   message.id,
	  "subject":     message.subject,
	  "topic":       message.topic,
	]
	
	do {
	  request.httpBody = try JSONSerialization.data(withJSONObject: body)
	  let (data, response) = try await URLSession.shared.data(for: request)
	  if let httpResponse = response as? HTTPURLResponse {
		logger.info("Session start HTTP \(httpResponse.statusCode) for message \(message.id)")
	  }
	  _ = data // TODO: parse session token / room URL from response
	} catch {
	  logger.error("Failed to start session for message \(message.id): \(error)")
	}
  }
#endif
}
