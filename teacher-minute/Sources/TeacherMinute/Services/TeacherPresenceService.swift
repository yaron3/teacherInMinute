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
  }

  func goOffline() {
	presenceInfo("[Presence] goOffline called uid=\(self.teacherUID)")
	writeStatus("offline", subjects: [])
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
  
}

#elseif !SKIP_BRIDGE

import FirebaseDatabase

@MainActor
final class TeacherPresenceService {
  private let teacherUID: String
  private let injectedStatusWriter: ((String) -> Void)?
  private var teacherRef: FirebaseDatabase.DatabaseReference?
  /// What `writeStatus` last wrote. A keep-alive only ever repeats an
  /// "online" — it must not undo a teacher going offline.
  private var lastWrittenStatus: String?
  
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
  }

  func goOffline() {
	logger.info("[Presence] goOffline called uid=\(self.teacherUID)")
	writeStatus("offline", subjects: [])
  }

  /// Tells the backend the app is still running — see `TeacherKeepAlive`.
  ///
  /// Re-sends `status: "online"` with the timestamp: if the backend took the
  /// teacher offline while the app was away, this puts them back.
  func sendKeepAlive() {
	guard lastWrittenStatus == "online" else { return }
	if let injectedStatusWriter {
	  injectedStatusWriter("online")
	  return
	}
	teacherRef?.updateChildValues([
	  "status": "online",
	  // The server's clock, not the phone's: the backend compares it with its
	  // own, and the database rules refuse anything else.
	  "lastSeenAt": FirebaseDatabase.ServerValue.timestamp(),
	]) { error, _ in
	  if let error {
		logger.error("[Presence] keep-alive write failed: \(error.localizedDescription)")
	  }
	}
  }

  private func writeStatus(_ status: String, subjects: [String]) {
	lastWrittenStatus = status
	if let injectedStatusWriter {
	  injectedStatusWriter(status)
	  return
	}
	// Two separate facts. `availability` is what the teacher asked for, and only
	// this method writes it. `status` is whether they are in the dispatch pool,
	// which the backend writes too: it takes offline a teacher whose app has
	// stopped sending keep-alives and who has no push token to be reached by
	// instead (functions/src/keepAlive.ts). It leaves `availability` alone, so
	// the app's next keep-alive puts them back when it runs again.
	//
	// There is no `onDisconnect` handler any more. It set `status` offline
	// whenever the socket closed, with no regard for whether a push could still
	// reach the teacher.
	var values: [String: Any] = [
	  "availability": status == "online" ? "available" : "dnd",
	  "status": status,
	]
	if status == "online" {
	  values["subjects"] = subjects
	  // In the same update as the status, so the backend never sees this
	  // teacher online beside a keep-alive left over from an earlier session.
	  values["lastSeenAt"] = FirebaseDatabase.ServerValue.timestamp()
	}
	teacherRef?.updateChildValues(values)
	logger.info("[Presence] wrote status=\(status) subjects=\(subjects) to DB")
  }
  
}

#endif
