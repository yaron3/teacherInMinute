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

// MARK: - ViewModel

@Observable
@MainActor
final class TeacherDashboardViewModel {

  // MARK: - State

  var teacherName = "Teacher"
  var isOnline = false
  var inviteIDs: [String] = []
  var inviteTopics: [String: String] = [:]
  var inviteTexts: [String: String] = [:]
  var inviteExpiresAt: [String: Double] = [:]
  var inviteWaves: [String: Int] = [:]
  var activeCallRoom: String? = nil
  var activeCallToken: String? = nil
  var activeCallStudentUid: String? = nil
  var activeQuestionId: String? = nil
  var errorMessage: String? = nil

  // MARK: - Private

  private var presenceService: TeacherPresenceService?
#if !os(Android)
  private var inviteService: InviteService?
#endif
#if os(Android)
  private var androidInvitePollingTask: Task<Void, Never>?
#endif
#if SKIP
  private var androidTeacherRef: DatabaseReference?
#endif
  private var authListenerHandle: Any?

  // MARK: - Init

  init() {
    authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      guard let self else { return }
      if let uid = user?.uid {
        Task { @MainActor [weak self] in
#if os(Android)
          guard let self, self.androidInvitePollingTask == nil else { return }
#else
          guard let self, self.inviteService == nil else { return }
#endif
          self.configurePresence(uid: uid)
        }
      } else {
        Task { @MainActor [weak self] in
#if os(Android)
          self?.androidInvitePollingTask?.cancel()
          self?.androidInvitePollingTask = nil
#else
          self?.inviteService?.stopListening()
          self?.inviteService = nil
#endif
          self?.presenceService = nil
        }
      }
    }
  }

  // MARK: - Setup

  private func configurePresence(uid: String) {
    logger.info("[VM] configurePresence — uid=\(uid)")
#if os(Android)
    presenceService = nil
    logger.info("[VM] configurePresence — Android path")
    startAndroidInvitePolling(uid: uid)
    logger.info("[VM] configurePresence — Android invite polling uid=\(uid)")
    return
#elseif SKIP
    androidTeacherRef = Database.database().reference(withPath: "teachers/\(uid)")
    presenceService = nil
    logger.info("[VM] configurePresence — Android RTDB ref ready")
#else
    presenceService = TeacherPresenceService(teacherUID: uid)
    logger.info("[VM] configurePresence — presenceService ready")
#endif

#if !os(Android)
    let service = InviteService(teacherUid: uid) { [weak self] updated in
      self?.setInvites(
        updated.map {
          [
            "id": $0.id,
            "topic": $0.topic,
            "text": $0.text,
            "expiresAt": $0.expiresAt,
            "wave": $0.wave,
          ]
        }
      )
    }
    service.startListening()
    inviteService = service
    logger.info("[VM] configurePresence — InviteService listening uid=\(uid)")
#endif
  }

  // MARK: - Online Toggle

  func toggleOnline() {
#if os(Android)
    if androidInvitePollingTask == nil, let uid = Auth.auth().currentUser?.uid {
      logger.info("[VM] toggleOnline — Android invite polling nil, configuring now uid=\(uid)")
      configurePresence(uid: uid)
    }
    isOnline.toggle()
    logger.info("[VM] toggleOnline — isOnline=\(self.isOnline)")
    let status = isOnline ? "online" : "offline"
    AndroidTeacherPresenceWriter.setCurrentTeacherStatus(status)
    logger.info("[VM] Android wrote teacher status=\(status)")
#elseif SKIP
    if androidTeacherRef == nil, let uid = Auth.auth().currentUser?.uid {
      logger.info("[VM] toggleOnline — Android ref nil, configuring now uid=\(uid)")
      configurePresence(uid: uid)
    }
    isOnline.toggle()
    logger.info("[VM] toggleOnline — isOnline=\(self.isOnline)")
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
    logger.info("[VM] toggleOnline — isOnline=\(self.isOnline)")
#if os(Android)
    let status = isOnline ? "online" : "offline"
    AndroidTeacherPresenceWriter.setCurrentTeacherStatus(status)
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
  private func startAndroidInvitePolling(uid: String) {
    androidInvitePollingTask?.cancel()
    androidInvitePollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          let updated = try await AndroidInviteFetcher.fetchInvites(teacherUid: uid)
          guard !Task.isCancelled else { return }
          self?.setInvites(updated)
          logger.info("[VM] Android invite polling fetched count=\(updated.count) uid=\(uid)")
        } catch {
          guard !Task.isCancelled else { return }
          self?.errorMessage = error.localizedDescription
          logger.error("[VM] Android invite polling failed — \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }
#endif

  private func setInvites(_ rows: [[String: Any]]) {
    var ids: [String] = []
    var topics: [String: String] = [:]
    var texts: [String: String] = [:]
    var expiresAtByID: [String: Double] = [:]
    var waves: [String: Int] = [:]

    for row in rows {
      guard let id = row["id"] as? String,
            let topic = row["topic"] as? String,
            let text = row["text"] as? String else {
        continue
      }

      let expiresAt: Double
      if let value = row["expiresAt"] as? Double {
        expiresAt = value
      } else if let value = row["expiresAt"] as? NSNumber {
        expiresAt = value.doubleValue
      } else {
        expiresAt = Date().timeIntervalSince1970 * 1000.0 + 12_000.0
      }

      let wave: Int
      if let value = row["wave"] as? Int {
        wave = value
      } else if let value = row["wave"] as? NSNumber {
        wave = value.intValue
      } else {
        wave = 1
      }

      ids.append(id)
      topics[id] = topic
      texts[id] = text
      expiresAtByID[id] = expiresAt
      waves[id] = wave
    }

    inviteIDs = ids
    inviteTopics = topics
    inviteTexts = texts
    inviteExpiresAt = expiresAtByID
    inviteWaves = waves
  }

  // MARK: - Invite Actions

  func acceptInvite(questionId: String) {
    Task {
      do {
        let result = try await FunctionsService.shared.acceptInvite(questionId: questionId)
        activeQuestionId = questionId
        activeCallRoom = result.liveKitRoom
        activeCallToken = result.liveKitToken
        activeCallStudentUid = result.studentUid
        logger.info("[VM] acceptInvite — questionId=\(questionId) room=\(result.liveKitRoom ?? "")")
      } catch {
        errorMessage = error.localizedDescription
        logger.error("[VM] acceptInvite failed — \(error.localizedDescription)")
      }
    }
  }

  func declineInvite(questionId: String) {
    Task {
      do {
        try await FunctionsService.shared.declineInvite(questionId: questionId)
        logger.info("[VM] declineInvite — qid=\(questionId)")
      } catch {
        errorMessage = error.localizedDescription
        logger.error("[VM] declineInvite failed — \(error.localizedDescription)")
      }
    }
  }

  func endCall() {
    activeQuestionId = nil
    activeCallRoom = nil
    activeCallToken = nil
    activeCallStudentUid = nil
  }

  func editSubjects() {
    // TODO: navigate to subject edit screen
  }
}
