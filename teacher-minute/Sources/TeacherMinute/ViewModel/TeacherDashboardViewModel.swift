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
  /// Raw messages kept so we can look them up on accept / reject.
  private var rawMessages: [WaitingMessage] = []
  
  // MARK: - Init
  
  init() {
	configurePresence()
  }
  
  // MARK: - Setup
  
  private func configurePresence() {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	let service = TeacherPresenceService(teacherUID: uid)
	service.onMessagesUpdated = { [weak self] messages in
	  guard let self else { return }
	  self.rawMessages  = messages
	  self.liveRequests = messages.map(LiveStudentRequest.init)
	}
	presenceService = service
  }
  
  // MARK: - Actions
  
  func toggleOnline() {
	isOnline.toggle()
	if isOnline {
	  presenceService?.goOnline()
	} else {
	  presenceService?.goOffline()
	}
  }
  
  func accept(_ request: LiveStudentRequest) {
	guard let message = rawMessages.first(where: { $0.id == request.id }) else { return }
	Task { await presenceService?.accept(message: message) }
  }
  
  func reject(_ request: LiveStudentRequest) {
	guard let message = rawMessages.first(where: { $0.id == request.id }) else { return }
	presenceService?.reject(message: message)
  }
  
  func editSubjects() {
	// TODO: navigate to subject edit screen
  }
}
