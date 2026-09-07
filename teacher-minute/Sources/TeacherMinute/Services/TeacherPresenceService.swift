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

  private func writeStatus(_ status: String, subjects: [String]) {
	if let injectedStatusWriter {
	  injectedStatusWriter(status)
	  return
	}
	teacherRef?.child("status").setValue(status)
	if status == "online" {
	  teacherRef?.child("subjects").setValue(subjects)
	  // Dead man's switch: Firebase server sets status offline if the connection drops
	  // (app killed, crash, network loss) without an explicit goOffline() call
	  teacherRef?.onDisconnectUpdateChildValues(["status": "offline"])
	} else {
	  teacherRef?.cancelDisconnectOperations()
	}
	logger.info("[Presence] wrote status=\(status) subjects=\(subjects) to DB")
  }
  
}

#endif
