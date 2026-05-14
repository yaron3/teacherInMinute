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
  var invitePhotoUrls: [String: [String]] = [:]
  var inviteHasVoiceMessage: [String: Bool] = [:]
  var inviteStudentNames: [String: String] = [:]
  var inviteStudentUids: [String: String] = [:]
  var inviteConnectionFeeCents: [String: Int] = [:]
  var invitePricePerMinuteCents: [String: Int] = [:]
  var activeCallRoom: String? = nil
  var activeCallToken: String? = nil
  var activeCallStudentUid: String? = nil
  var activeLessonId: String? = nil
  var activeQuestionId: String? = nil
  var activeQuestionText = ""
  var activeStudentName = "Student"
  var activeConnectionFeeCents = 0
  var activePricePerMinuteCents = 50
  var activeAcceptedAt = 0.0
  var acceptingQuestionId: String? = nil
  var errorMessage: String? = nil
  var isAcceptingCalls = false

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
  private var acceptingTask: Task<Void, Never>?
  private var didLoadProfile = false

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
          await self.loadProfile(uid: uid)
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
    let service = InviteService(teacherId: uid) { [weak self] updated in
      self?.setInvites(
        updated.map {
          [
            "id": $0.id,
            "topic": $0.topic,
            "text": $0.text,
            "expiresAt": $0.expiresAt,
            "wave": $0.wave,
            "photoUrls": $0.photoUrls,
            "hasVoiceMessage": $0.hasVoiceMessage,
            "studentId": $0.studentId,
            "studentName": $0.studentName,
            "connectionFeeCents": $0.connectionFeeCents,
            "pricePerMinuteCents": $0.pricePerMinuteCents,
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
          let updated = try await AndroidInviteFetcher.fetchInvites(teacherId: uid)
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
    var photoUrlsByID: [String: [String]] = [:]
    var hasVoiceByID: [String: Bool] = [:]
    var studentNames: [String: String] = [:]
    var studentIds: [String: String] = [:]
    var connectionFees: [String: Int] = [:]
    var pricesPerMinute: [String: Int] = [:]

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
      photoUrlsByID[id] = row["photoUrls"] as? [String] ?? []
      hasVoiceByID[id] = row["hasVoiceMessage"] as? Bool ?? false
      studentNames[id] = Self.firstString(row, keys: ["studentName", "studentFullName", "studentDisplayName", "name"])
      studentIds[id] = Self.firstString(row, keys: ["studentId", "studentUID", "studentId"])
      connectionFees[id] = Self.intValue(row["connectionFeeCents"]) ?? Self.intValue(row["connectionFee"]) ?? 0
      pricesPerMinute[id] = Self.intValue(row["pricePerMinuteCents"])
        ?? Self.intValue(row["ratePerMinuteCents"])
        ?? Self.intValue(row["costPerMinuteCents"])
        ?? 50
    }

    inviteIDs = ids
    inviteTopics = topics
    inviteTexts = texts
    inviteExpiresAt = expiresAtByID
    inviteWaves = waves
    invitePhotoUrls = photoUrlsByID
    inviteHasVoiceMessage = hasVoiceByID
    inviteStudentNames = studentNames
    inviteStudentUids = studentIds
    inviteConnectionFeeCents = connectionFees
    invitePricePerMinuteCents = pricesPerMinute
  }

  // MARK: - Invite Actions

  func acceptInvite(questionId: String) {
    guard acceptingQuestionId == nil, activeQuestionId == nil else { return }
    errorMessage = nil
    acceptingQuestionId = questionId
    isAcceptingCalls = true
    activeQuestionText = inviteTexts[questionId] ?? ""
    activeStudentName = inviteStudentNames[questionId]?.isEmpty == false ? inviteStudentNames[questionId] ?? "Student" : "Student"
    activeConnectionFeeCents = inviteConnectionFeeCents[questionId] ?? 0
    activePricePerMinuteCents = invitePricePerMinuteCents[questionId] ?? 50
    activeAcceptedAt = Date().timeIntervalSince1970 * 1000.0
    print("TeacherMinute teacherAccept tapped questionId=\(questionId)")
    logger.info("[VM] acceptInvite tapped — questionId=\(questionId)")

    acceptingTask?.cancel()
    acceptingTask = Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await FunctionsService.shared.acceptInvite(questionId: questionId)
        try Task.checkCancellation()
        try await ChatSessionService.markQuestionAccepted(
          questionId: questionId,
          teacherId: Auth.auth().currentUser?.uid
        )
        try Task.checkCancellation()
        activeCallRoom = result.liveKitRoom
        activeCallToken = result.liveKitToken
        activeCallStudentUid = result.studentId ?? inviteStudentUids[questionId]
        activeLessonId = result.questionId
        if activeStudentName == "Student", let studentId = activeCallStudentUid, !studentId.isEmpty,
           let profile = try? await UserService.shared.fetchProfileSummary(uid: studentId) {
          activeStudentName = profile.displayName
        }
        inviteIDs = inviteIDs.filter { $0 != questionId }
        acceptingQuestionId = nil
        isAcceptingCalls = false
        activeQuestionId = questionId
        logger.info("[VM] acceptInvite ready — questionId=\(questionId) room=\(result.liveKitRoom ?? "")")
      } catch is CancellationError {
        acceptingQuestionId = nil
        isAcceptingCalls = false
        clearActiveCallState()
        logger.info("[VM] acceptInvite cancelled — questionId=\(questionId)")
      } catch {
        acceptingQuestionId = nil
        isAcceptingCalls = false
        clearActiveCallState()
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

  func cancelAcceptingInvite() {
    acceptingTask?.cancel()
    acceptingTask = nil
    acceptingQuestionId = nil
    isAcceptingCalls = false
    clearActiveCallState()
  }

  func endCall() {
    activeQuestionId = nil
    clearActiveCallState()
  }

  private func clearActiveCallState() {
    activeCallRoom = nil
    activeCallToken = nil
    activeCallStudentUid = nil
    activeLessonId = nil
    activeQuestionText = ""
    activeStudentName = "Student"
    activeConnectionFeeCents = 0
    activePricePerMinuteCents = 50
    activeAcceptedAt = 0
  }

  func editSubjects() {
    // TODO: navigate to subject edit screen
  }

  func activeChatInitialDetails() -> ChatSessionDetails {
    ChatSessionDetails(
      questionId: activeLessonId ?? "",
      studentId: activeCallStudentUid ?? "",
      teacherId: Auth.auth().currentUser?.uid ?? "",
      studentName: activeStudentName,
      teacherName: teacherName,
      questionText: activeQuestionText,
      createdAt: 0,
      acceptedAt: activeAcceptedAt > 0 ? activeAcceptedAt : Date().timeIntervalSince1970 * 1000.0,
      connectionFeeCents: activeConnectionFeeCents,
      pricePerMinuteCents: activePricePerMinuteCents,
      teacherSharePercent: 75
    )
  }

  private static func firstString(_ row: [String: Any], keys: [String]) -> String {
    for key in keys {
      if let value = row[key] as? String {
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

  private func loadProfile(uid: String) async {
    guard !didLoadProfile else { return }
    didLoadProfile = true
    if let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      teacherName = profile.displayName
    }
  }
}
