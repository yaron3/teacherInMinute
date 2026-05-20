//
//  TeacherPresenceService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 08/05/2026.
//

import Foundation

#if SKIP

private func presenceInfo(_ msg: String) {
  print(msg)
}

private func presenceError(_ msg: String) {
  print(msg)
}

@MainActor
final class TeacherPresenceService {
  private let teacherUID: String
  private var teacherRef: DatabaseReference?
  private var messagesHandle: UInt?
  var onMessagesUpdated: (([WaitingMessage]) -> Void)?
  
  init(teacherUID: String, statusWriter: ((String) -> Void)? = nil) {
	self.teacherUID = teacherUID
	if let statusWriter {
	  self.teacherRef = nil
	  presenceInfo("[Presence] initialized with injected status writer uid=\(teacherUID)")
	  self.injectedStatusWriter = statusWriter
	} else {
	  presenceInfo("[Presence] init uid=\(teacherUID)")
	  self.teacherRef = Database.database().reference(withPath: "teachers/\(teacherUID)")
	  presenceInfo("[Presence] teacherRef created")
	}
  }
  
  private var injectedStatusWriter: ((String) -> Void)?
  
  func goOnline(subjects: [String] = []) {
	presenceInfo("[Presence] goOnline called uid=\(self.teacherUID)")
	writeStatus("online", subjects: subjects)
	guard let ref = teacherRef else { return }
	startListeningToQueue(ref: ref.child("waitingMessages"))
  }

  func goOffline() {
	presenceInfo("[Presence] goOffline called uid=\(self.teacherUID)")
	writeStatus("offline", subjects: [])
	stopListeningToQueue()
  }

  private func writeStatus(_ status: String, subjects: [String]) {
	if let injectedStatusWriter {
	  injectedStatusWriter(status)
	  return
	}
	guard let ref = teacherRef else {
	  presenceError("[Presence] writeStatus aborted, teacherRef is nil status=\(status)")
	  return
	}
	ref.child("status").setValue(status)
	if status == "online" {
	  ref.child("subjects").setValue(subjects)
	}
	presenceInfo("[Presence] wrote status=\(status) subjects=\(subjects) to DB")
  }
  
  private func startListeningToQueue(ref: DatabaseReference) {
	presenceInfo("[Presence] startListeningToQueue attaching observer")
	messagesHandle = ref.observe(DataEventType.value) { [weak self] snapshot in
	  guard let self else { return }
	  presenceInfo("[Presence] snapshot received childrenCount=\(snapshot.childrenCount)")
	  var messages: [WaitingMessage] = []
	  
	  for child in snapshot.children {
		guard
		  let snap = child as? DataSnapshot,
		  let dict = snap.value as? [String: Any],
		  let studentUID = dict["studentUID"] as? String,
		  let studentName = dict["studentName"] as? String,
		  let topic = dict["topic"] as? String,
		  let subject = dict["subject"] as? String,
		  let createdAt = dict["createdAt"] as? Double
		else { continue }
		
		let statusRaw = dict["status"] as? String ?? "waiting"
		guard statusRaw == "waiting" else { continue }
		let isHighPriority = dict["isHighPriority"] as? Bool ?? false
		let message = WaitingMessage(
		  id: snap.key,
		  studentUID: studentUID,
		  studentName: studentName,
		  topic: topic,
		  subject: subject,
		  isHighPriority: isHighPriority,
		  createdAt: createdAt,
		  statusRaw: statusRaw
		)
		messages.append(message)
	  }
	  
	  messages.sort { $0.createdAt < $1.createdAt }
	  self.onMessagesUpdated?(messages)
	  ()
	}
  }
  
  private func stopListeningToQueue() {
	guard let handle = messagesHandle else { return }
	teacherRef?.child("waitingMessages").removeObserver(withHandle: handle)
	messagesHandle = nil
  }
  
  func accept(message: WaitingMessage) {
	updateStatus(of: message, to: "accepted")
  }
  
  func reject(message: WaitingMessage) {
	updateStatus(of: message, to: "rejected")
  }
  
  private func updateStatus(of message: WaitingMessage, to status: String) {
	teacherRef?
	  .child("waitingMessages")
	  .child(message.id)
	  .child("status")
	  .setValue(status)
  }
}

#elseif !SKIP_BRIDGE

import FirebaseDatabase

@MainActor
final class TeacherPresenceService {
  private let teacherUID: String
  private let injectedStatusWriter: ((String) -> Void)?
  private var teacherRef: FirebaseDatabase.DatabaseReference?
  private var messagesHandle: UInt?
  var onMessagesUpdated: (([WaitingMessage]) -> Void)?
  
  init(teacherUID: String, statusWriter: ((String) -> Void)? = nil) {
	self.teacherUID = teacherUID
	self.injectedStatusWriter = statusWriter
	if statusWriter == nil {
	  self.teacherRef = FirebaseDatabase.Database.database()
		.reference(withPath: "teachers/\(teacherUID)")
	}
  }
  
  func goOnline(subjects: [String] = []) {
	logger.info("[Presence] goOnline called uid=\(self.teacherUID)")
	writeStatus("online", subjects: subjects)
	guard let ref = teacherRef else { return }
	startListeningToQueue(ref: ref.child("waitingMessages"))
  }

  func goOffline() {
	logger.info("[Presence] goOffline called uid=\(self.teacherUID)")
	writeStatus("offline", subjects: [])
	stopListeningToQueue()
  }

  private func writeStatus(_ status: String, subjects: [String]) {
	if let injectedStatusWriter {
	  injectedStatusWriter(status)
	  return
	}
	teacherRef?.child("status").setValue(status)
	if status == "online" {
	  teacherRef?.child("subjects").setValue(subjects)
	}
	logger.info("[Presence] wrote status=\(status) subjects=\(subjects) to DB")
  }
  
  private func startListeningToQueue(ref: FirebaseDatabase.DatabaseReference) {
	messagesHandle = ref.observe(FirebaseDatabase.DataEventType.value) { [weak self] snapshot in
	  guard let self else { return }
	  var messages: [WaitingMessage] = []
	  
	  for child in snapshot.children {
		guard
		  let snap = child as? DataSnapshot,
		  let dict = snap.value as? [String: Any],
		  let msg = WaitingMessage(id: snap.key, data: dict),
		  msg.status == .waiting
		else { continue }
		messages.append(msg)
	  }
	  
	  messages.sort { $0.createdAt < $1.createdAt }
	  self.onMessagesUpdated?(messages)
	}
  }
  
  private func stopListeningToQueue() {
	guard let handle = messagesHandle else { return }
	teacherRef?.child("waitingMessages").removeObserver(withHandle: handle)
	messagesHandle = nil
  }
  
  func accept(message: WaitingMessage) {
	updateStatus(of: message, to: .accepted)
  }
  
  func reject(message: WaitingMessage) {
	updateStatus(of: message, to: .rejected)
  }
  
  private func updateStatus(of message: WaitingMessage, to status: WaitingMessage.MessageStatus) {
	teacherRef?
	  .child("waitingMessages")
	  .child(message.id)
	  .child("status")
	  .setValue(status.rawValue)
  }
}

#endif
