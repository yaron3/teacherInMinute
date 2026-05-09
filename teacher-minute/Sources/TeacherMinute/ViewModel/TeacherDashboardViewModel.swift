//
//  TeacherDashboardViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

// MARK: - LiveStudentRequest
// A display-friendly wrapper around WaitingMessage used by the View layer.

struct LiveStudentRequest: Identifiable {
  let id: String
  let studentName: String
  let topic: String
  let waitingTime: String
  let isHighPriority: Bool
  
  init(message: WaitingMessage) {
	self.id             = message.id
	self.studentName    = message.studentName
	self.topic          = message.topic
	self.waitingTime    = message.waitingTimeLabel
	self.isHighPriority = message.isHighPriority
  }
}

// MARK: - ViewModel

@Observable
@MainActor
final class TeacherDashboardViewModel {
  
  // MARK: - State
  
  var teacherName = "Teacher"
  var isOnline = false
  var liveRequests: [LiveStudentRequest] = []
  
  // MARK: - Private
  
  private var presenceService: TeacherPresenceService?
#if SKIP
  private var androidTeacherRef: DatabaseReference?
#endif
  private var rawMessages: [WaitingMessage] = []
  /// Retains the Auth state listener handle so it can be removed.
  private var authListenerHandle: Any?
  
  // MARK: - Init
  
  init() {
	// Listen for auth state — creates presenceService as soon as a user is available.
	// This handles the race between ViewModel init and Firebase Auth session restore.
	authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
	  guard let self else { return }
	  if let uid = user?.uid {
		logger.info("[VM] authStateDidChange — uid=\(uid)")
		Task { @MainActor [weak self] in
		  guard let self, self.presenceService == nil else { return }
		  self.configurePresence(uid: uid)
		}
	  } else {
		logger.warning("[VM] authStateDidChange — user signed out, clearing presenceService")
		Task { @MainActor [weak self] in
		  self?.presenceService = nil
		}
	  }
	}
  }
  
  // MARK: - Setup
  
  private func configurePresence(uid: String) {
	logger.info("[VM] configurePresence — uid=\(uid)")
#if SKIP
	androidTeacherRef = Database.database().reference(withPath: "teachers/\(uid)")
	presenceService = nil
	logger.info("[VM] configurePresence done — Android database ref ready")
#else
	let service = TeacherPresenceService(teacherUID: uid)
#if !os(Android)
	service.onMessagesUpdated = { [weak self] messages in
	  logger.info("[VM] onMessagesUpdated callback fired — \(messages.count) message(s)")
	  Task { @MainActor [weak self] in
		guard let self else { return }
		self.rawMessages  = messages
		self.liveRequests = messages.map(LiveStudentRequest.init)
		logger.info("[VM] liveRequests updated on MainActor — count=\(messages.count)")
	  }
	}
#endif
	presenceService = service
	logger.info("[VM] configurePresence done — presenceService ready")
#endif
  }
  
  // MARK: - Actions
  
  func toggleOnline() {
	// Safety net: if auth state listener hasn't fired yet, try now.
#if SKIP
	if androidTeacherRef == nil, let uid = Auth.auth().currentUser?.uid {
	  logger.info("[VM] toggleOnline — Android database ref nil, configuring now uid=\(uid)")
	  configurePresence(uid: uid)
	}
	isOnline.toggle()
	logger.info("[VM] toggleOnline — isOnline=\(self.isOnline) androidRef=\(self.androidTeacherRef != nil ? "ready" : "nil")")
	guard let ref = androidTeacherRef else { return }
	let status = isOnline ? "online" : "offline"
	ref.child("status").setValue(status)
	logger.info("[VM] Android wrote teacher status=\(status)")
#else
	if presenceService == nil, let uid = Auth.auth().currentUser?.uid {
	  logger.info("[VM] toggleOnline — presenceService nil, configuring now uid=\(uid)")
	  configurePresence(uid: uid)
	}
	isOnline.toggle()
	logger.info("[VM] toggleOnline — isOnline=\(self.isOnline) presenceService=\(self.presenceService != nil ? "ready" : "nil")")
#if os(Android)
	let status = isOnline ? "online" : "offline"
	Task { await writeAndroidStatusWithREST(status) }
#else
	if isOnline {
	  presenceService?.goOnline()
	} else {
	  presenceService?.goOffline()
	}
#endif
#endif
  }

#if os(Android)
  private func writeAndroidStatusWithREST(_ status: String) async {
	guard let user = Auth.auth().currentUser else { return }
	do {
	  let token = try await user.getIDToken()
	  guard let encodedUID = user.uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
			let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
			let url = URL(string: "https://teacher-in-a-moment-default-rtdb.firebaseio.com/teachers/\(encodedUID)/status.json?auth=\(encodedToken)")
	  else { return }
	  
	  var request = URLRequest(url: url)
	  request.httpMethod = "PUT"
	  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	  request.httpBody = "\"\(status)\"".data(using: .utf8)
	  let (_, response) = try await URLSession.shared.data(for: request)
	  if let httpResponse = response as? HTTPURLResponse {
		logger.info("[VM] Android REST wrote teacher status=\(status) code=\(httpResponse.statusCode)")
	  }
	} catch {
	  logger.error("[VM] Android REST status write failed: \(error)")
	}
  }
#endif
  
  func accept(_ request: LiveStudentRequest) {
	guard let message = rawMessages.first(where: { $0.id == request.id }) else { return }
	presenceService?.accept(message: message)
  }
  
  func reject(_ request: LiveStudentRequest) {
	guard let message = rawMessages.first(where: { $0.id == request.id }) else { return }
	presenceService?.reject(message: message)
  }
  
  func editSubjects() {
	// TODO: navigate to subject edit screen
  }
}
