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
import AVFoundation
#else
import SkipFirebaseAuth
#endif

// MARK: - Protocol

@MainActor
protocol TeacherDashboardViewModeling: AnyObject {
  var teacherName: String { get set }
  var teacherImageURL: String { get set }
  var isOnline: Bool { get set }
  var inviteIDs: [String] { get set }
  var inviteTopics: [String: String] { get set }
  var inviteTexts: [String: String] { get set }
  var inviteExpiresAt: [String: Double] { get set }
  var inviteWaves: [String: Int] { get set }
  var invitePhotoUrls: [String: [String]] { get set }
  var inviteHasVoiceMessage: [String: Bool] { get set }
  var inviteVoiceMessageDurations: [String: Int] { get set }
  var inviteStudentNames: [String: String] { get set }
  var inviteStudentImageURLs: [String: String] { get set }
  var inviteConversationTypes: [String: String] { get set }
  var activeCallRoom: String? { get set }
  var activeCallToken: String? { get set }
  var activeQuestionId: String? { get set }
  var activeQuestionText: String { get set }
  var activeStudentName: String { get set }
  var activeStudentImageURL: String { get set }
  var activeConversationType: String { get set }
  var acceptingQuestionId: String? { get set }
  var errorMessage: String? { get set }
  var isAcceptingCalls: Bool { get set }
  var isVerified: Bool { get set }
  var todayEarningsCents: Int { get set }
  var todayMinutesTutored: Int { get set }
  var weekEarningsCents: Int { get set }
  var weekMinutesTutored: Int { get set }
  var totalMinutes: Int { get set }
  var lessonCount: Int { get set }
  var monthEarningsCents: Int { get set }
  var teacherRating: Double { get set }
  var reviewCount: Int { get set }
  var ratePerMinuteCents: Int { get set }
  var hasMicAccess: Bool { get set }
  var hasCameraAccess: Bool { get set }
  var showsSubjectEditor: Bool { get set }
  /// True from launch until the first earnings and rating fetch has come back.
  /// The counters all start at zero, and zero is a perfectly plausible answer
  /// for a teacher's income — so until this clears, the dashboard says the
  /// numbers are still coming rather than showing a total nobody earned.
  var isLoadingStats: Bool { get }
  /// The same idea for the teacher's own profile. Its defaults are not neutral
  /// either: an unloaded profile claims the teacher is awaiting verification,
  /// teaches nothing, and charges the built-in starter rate.
  var isLoadingProfile: Bool { get }

  var formattedTodayEarnings: String { get }
  var formattedWeekEarnings: String { get }
  var formattedMonthEarnings: String { get }
  var formattedRate: String { get }
  var weekChangeText: String? { get }
  var hasRating: Bool { get }
  var ratingText: String { get }
  var reviewCountText: String { get }
  var subjectsDisplayText: String { get }

  func toggleOnline()
  func enforceNotificationRequirement()
  func acceptInvite(questionId: String)
  func declineInvite(questionId: String)
  func cancelAcceptingInvite()
  func endCall()
  func editSubjects()
  func reloadSubjects()
  func activeChatInitialDetails() -> ChatSessionDetails
  func refreshEarnings()
}

// MARK: - Protocol default strings

extension TeacherDashboardViewModeling {

  // MARK: Navigation / overlay titles

  var settingUpSessionText: String { LocalizationSupport.localized("Setting up the session") }
  var chatStudentTitle: String { LocalizationSupport.localized("Student") }
  var teacherEyebrow: String { LocalizationSupport.localized("Teacher") }
  var teacherDashboardTitle: String { LocalizationSupport.localized("Teacher Dashboard") }
  var notificationsRequiredMessage: String {
    LocalizationSupport.localized("Turn on notifications to stay online. Questions reach you by notification when the app is in the background.")
  }

  // MARK: Status toggle card

  var statusToggleTitle: String {
    isOnline
      ? LocalizationSupport.localized("Available")
      : LocalizationSupport.localized("Not available")
  }

  var statusToggleSubtitle: String {
    isOnline
      ? LocalizationSupport.localized("Waiting for students...")
      : LocalizationSupport.localized("Tap to start")
  }

  // MARK: Stats cards

  var lessonsLabel: String { LocalizationSupport.localized("Lessons") }
  var monthlyIncomeLabel: String { LocalizationSupport.localized("Monthly income") }

  // MARK: Rating section

  var myRatingLabel: String { LocalizationSupport.localized("My Rating") }

  // MARK: Teacher status card

  var verificationStatusText: String {
    loadedProfileValue(
      isVerified
        ? LocalizationSupport.localized("Verified Expert")
        : LocalizationSupport.localized("Pending Verification")
    )
  }

  var editSubjectsLabel: String { LocalizationSupport.localized("Edit Subjects") }

  // MARK: Earnings snapshot

  var earningsSnapshotHeader: String { LocalizationSupport.localized("Earnings Snapshot") }
  var earningsTodayTitle: String { LocalizationSupport.localized("Today") }
  var earningsThisWeekTitle: String { LocalizationSupport.localized("This Week") }
  var earningsAllTimeTitle: String { LocalizationSupport.localized("All Time") }
  var totalMinutesTutoredLabel: String { LocalizationSupport.localized("Total minutes tutored") }

  /// Stands in for any figure the dashboard has not fetched yet.
  var updatingValueText: String { LocalizationSupport.localized("Updating\u{2026}") }

  /// Wraps a figure so it is only shown once it means something. Every number
  /// on the dashboard that comes from the earnings or rating fetch goes
  /// through here — see `isLoadingStats`.
  func loadedValue(_ settled: String) -> String {
    isLoadingStats ? updatingValueText : settled
  }

  /// The profile equivalent of `loadedValue`. Kept separate because the
  /// profile arrives before the earnings do, and there is no reason to hold
  /// back a subject list that is already known.
  func loadedProfileValue(_ settled: String) -> String {
    isLoadingProfile ? updatingValueText : settled
  }

  var lessonCountText: String {
    loadedValue("\(lessonCount)")
  }

  var todayMinutesTutoredText: String {
    loadedValue(String(format: LocalizationSupport.localized("%d mins tutored"), todayMinutesTutored))
  }

  var weekMinutesTutoredText: String {
    loadedValue(String(format: LocalizationSupport.localized("%d mins tutored"), weekMinutesTutored))
  }

  /// Lifetime minutes come off the profile document, not the earnings fetch.
  var totalMinutesText: String {
    loadedProfileValue(String(format: LocalizationSupport.localized("%d min"), totalMinutes))
  }

  // MARK: Live earnings card

  var liveEarningsTodayLabel: String { LocalizationSupport.localized("Live Earnings Today") }

  var ratePerMinBadgeText: String {
    loadedProfileValue(String(format: LocalizationSupport.localized("%@/min"), formattedRate))
  }

  // MARK: Online status card

  var micStatusTitle: String { LocalizationSupport.localized("Mic") }
  var micStatusSubtitle: String {
    hasMicAccess ? LocalizationSupport.localized("On") : LocalizationSupport.localized("Off")
  }

  var camStatusTitle: String { LocalizationSupport.localized("Cam") }
  var camStatusSubtitle: String {
    hasCameraAccess ? LocalizationSupport.localized("Ready") : LocalizationSupport.localized("Off")
  }

  var connectionStatusTitle: String { LocalizationSupport.localized("Status") }
  var connectionStatusSubtitle: String { LocalizationSupport.localized("Connected") }

  // MARK: Live queue

  var liveQueueHeader: String { LocalizationSupport.localized("Live Queue") }

  var liveQueueWaitingText: String {
    String(format: LocalizationSupport.localized("%d Waiting"), inviteIDs.count)
  }

  // MARK: Readiness checklist

  var readinessChecklistHeader: String { LocalizationSupport.localized("Readiness Checklist") }

  var micChecklistTitle: String {
    hasMicAccess
      ? LocalizationSupport.localized("Microphone Enabled")
      : LocalizationSupport.localized("Microphone Disabled")
  }

  var micChecklistSubtitle: String { LocalizationSupport.localized("Required for voice sessions.") }

  var camChecklistTitle: String {
    hasCameraAccess
      ? LocalizationSupport.localized("Camera Enabled")
      : LocalizationSupport.localized("Camera Disabled")
  }

  var camChecklistSubtitle: String { LocalizationSupport.localized("Enable for video tutoring.") }

  var connectionChecklistTitle: String { LocalizationSupport.localized("Connection") }
  var connectionChecklistSubtitle: String { LocalizationSupport.localized("Connected") }
}

// MARK: - ViewModel

@Observable
@MainActor
final class TeacherDashboardViewModel: TeacherDashboardViewModeling {
  
  // MARK: - State
  
  var teacherName = "Teacher"
  var teacherImageURL: String {
    get { UserPhotoStore.shared.profileImageURL }
    set { UserPhotoStore.shared.profileImageURL = newValue }
  }
  var isOnline = false
  var inviteIDs: [String] = []
  var inviteTopics: [String: String] = [:]
  var inviteTexts: [String: String] = [:]
  var inviteExpiresAt: [String: Double] = [:]
  var inviteWaves: [String: Int] = [:]
  var invitePhotoUrls: [String: [String]] = [:]
  var inviteHasVoiceMessage: [String: Bool] = [:]
  var inviteVoiceMessageDurations: [String: Int] = [:]
  var inviteStudentNames: [String: String] = [:]
  var inviteStudentImageURLs: [String: String] = [:]
  var inviteStudentUids: [String: String] = [:]
  var invitePricePerMinuteCents: [String: Int] = [:]
  var inviteConversationTypes: [String: String] = [:]
  var activeCallRoom: String? = nil
  var activeCallToken: String? = nil
  var activeCallStudentUid: String? = nil
  var activeLessonId: String? = nil
  var activeQuestionId: String? = nil
  var activeQuestionText = ""
  var activeQuestionPhotoUrls: [String] = []
  var activeStudentName = "Student"
  var activeStudentImageURL = ""
  var activePricePerMinuteCents = 50
  var activeConversationType = "text"
  var activeAcceptedAt = 0.0
  var activeCurrencyCode = LessonFormatting.defaultCurrencyCode
  var acceptingQuestionId: String? = nil
  var errorMessage: String? = nil
  var isAcceptingCalls = false
  var isVerified = false
  var subjects: [String] = []
  private var subjectRawKeys: [String] = []
  var todayEarningsCents = 0
  var todayMinutesTutored = 0
  var weekEarningsCents = 0
  var weekMinutesTutored = 0
  var lastWeekEarningsCents = 0
  var totalMinutes = 0
  var lessonCount = 0
  var monthEarningsCents = 0
  /// The teacher's own reputation, from `teacherRatingSummary`. Zero until it
  /// loads and while the teacher has no reviews yet — `hasRating` is what the
  /// view checks before showing stars.
  var teacherRating: Double = 0
  var reviewCount: Int = 0
  var ratePerMinuteCents = 200
  var hasMicAccess = false
  var hasCameraAccess = false
  var showsSubjectEditor = false
  /// Cleared once — after the first profile/rating/earnings load. Later
  /// refreshes (`refreshEarnings`) leave it alone, so finishing a lesson
  /// updates the figures in place instead of blanking them out again.
  var isLoadingStats = true
  var isLoadingProfile = true

  var formattedTodayEarnings: String {
	loadedValue(Self.formatCents(todayEarningsCents, currency: earningsCurrencyCode))
  }

  var formattedWeekEarnings: String {
	loadedValue(Self.formatCents(weekEarningsCents, currency: earningsCurrencyCode))
  }

  var formattedMonthEarnings: String {
	loadedValue(Self.formatCents(monthEarningsCents, currency: earningsCurrencyCode))
  }
  
  var formattedRate: String {
	Self.formatCents(ratePerMinuteCents)
  }
  
  var weekChangeText: String? {
	guard lastWeekEarningsCents > 0 else { return nil }
	let change = Int(((Double(weekEarningsCents) - Double(lastWeekEarningsCents)) / Double(lastWeekEarningsCents) * 100).rounded())
	let sign = change >= 0 ? "+" : ""
	return String(format: LocalizationSupport.localized("%@%d%% vs last week"), sign, change)
  }
  
  /// A brand-new teacher has no reviews, so the dashboard says so instead of
  /// showing an empty five-star row that reads as a score of zero. Suppressed
  /// while the rating is still loading, for the same reason.
  var hasRating: Bool { !isLoadingStats && reviewCount > 0 }

  var ratingText: String { LessonFormatting.ratingText(teacherRating) }

  /// "1 reviews" reads wrong in both languages, and one format string cannot
  /// carry both forms, so the singular gets its own — the same shape as
  /// `onlineTeachersCountText` and `LessonFormatting.reviewCountText`, which
  /// already spell "(1 review)" out separately.
  var reviewCountText: String {
	let text: String
	if reviewCount == 0 {
	  text = LocalizationSupport.localized("No reviews yet")
	} else if reviewCount == 1 {
	  text = LocalizationSupport.localized("1 review")
	} else {
	  text = String(format: LocalizationSupport.localized("%d reviews"), reviewCount)
	}
	return loadedValue(text)
  }

  var subjectsDisplayText: String {
	if subjects.isEmpty {
	  return loadedProfileValue(LocalizationSupport.localized("No subjects selected"))
	}
	return subjects.map { LocalizationSupport.localized($0) }.joined(separator: ", ")
  }

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
	isOnline = false
	AndroidTeacherPresenceWriter.setCurrentTeacherStatus("offline")
	logger.info("[VM] configurePresence — Android path initialized offline")
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
			"voiceMessageDurationSeconds": $0.voiceMessageDurationSeconds as Any,
			"studentId": $0.studentId,
			"studentName": $0.studentName,
			"studentImageURL": $0.studentImageURL,
			"pricePerMinuteCents": $0.pricePerMinuteCents,
			"conversationType": $0.conversationType,
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
	AnalyticsService.shared.logEvent(AnalyticsEvent.teacherAcceptingToggled, parameters: ["is_online": isOnline])
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
	AnalyticsService.shared.logEvent(AnalyticsEvent.teacherAcceptingToggled, parameters: ["is_online": isOnline])
	guard let ref = androidTeacherRef else { return }
	let status = isOnline ? "online" : "offline"
	ref.child("status").setValue(status)
	if isOnline {
	  ref.child("subjects").setValue(subjectKeys)
	}
	logger.info("[VM] Android wrote teacher status=\(status) subjectKeys=\(isOnline ? subjectKeys : [])")
#else
	if presenceService == nil, let uid = Auth.auth().currentUser?.uid {
	  logger.info("[VM] toggleOnline — presenceService nil, configuring now uid=\(uid)")
	  configurePresence(uid: uid)
	}
	isOnline.toggle()
	logger.info("[VM] toggleOnline — isOnline=\(self.isOnline)")
	AnalyticsService.shared.logEvent(AnalyticsEvent.teacherAcceptingToggled, parameters: ["is_online": isOnline])
#if os(Android)
	let status = isOnline ? "online" : "offline"
	AndroidTeacherPresenceWriter.setCurrentTeacherStatus(status)
#else
	if isOnline {
	  presenceService?.goOnline(subjects: subjectKeys)
	} else {
	  presenceService?.goOffline()
	}
#endif
#endif
	enforceNotificationRequirement()
  }

  /// A backgrounded teacher only learns about a question from a notification —
  /// the RTDB invite listener (and, on Android, the invite poll) stops with the
  /// app. A teacher who has not granted notifications therefore sits in the
  /// dispatch pool unreachable, and every wave they are picked for burns its
  /// timeout before moving on. So permission is a precondition for being
  /// online: it is requested when going online, and refusing takes the teacher
  /// straight back offline.
  ///
  /// Called after every toggle and whenever the dashboard returns to the
  /// foreground, since permission can be revoked in system settings while the
  /// app is away.
  func enforceNotificationRequirement() {
	guard isOnline else { return }
	Task { @MainActor [weak self] in
	  guard let self else { return }
	  // A no-op once granted on both platforms, so this is safe to re-run.
	  let state = await PermissionService.shared.requestNotifications()
	  guard state != .granted else { return }
	  guard self.isOnline else { return }
	  self.isOnline = false
	  self.writePresence(online: false)
	  self.errorMessage = self.notificationsRequiredMessage
	  logger.info("[VM] went offline — notifications not granted (state=\(String(describing: state)))")
	}
  }

  /// The platform-specific presence write, shared by the toggle and by the
  /// notification rule above so both take the same path off.
  private func writePresence(online: Bool) {
	let status = online ? "online" : "offline"
#if os(Android)
	AndroidTeacherPresenceWriter.setCurrentTeacherStatus(status)
#elseif SKIP
	guard let ref = androidTeacherRef else { return }
	ref.child("status").setValue(status)
	if online {
	  ref.child("subjects").setValue(subjectKeys)
	}
#else
	if online {
	  presenceService?.goOnline(subjects: subjectKeys)
	} else {
	  presenceService?.goOffline()
	}
#endif
	logger.info("[VM] writePresence status=\(status)")
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
		  AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherDashboard.androidInvitePolling")
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
	var voiceDurationsByID: [String: Int] = [:]
	var studentNames: [String: String] = [:]
	var studentImageURLs: [String: String] = [:]
	var studentIds: [String: String] = [:]
	var pricesPerMinute: [String: Int] = [:]
	var conversationTypes: [String: String] = [:]
	
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
	  if let duration = Self.intValue(row["voiceMessageDurationSeconds"]) {
		voiceDurationsByID[id] = duration
	  }
	  studentNames[id] = Self.firstString(row, keys: ["studentName", "studentFullName", "studentDisplayName", "name"])
	  studentImageURLs[id] = Self.firstString(row, keys: ["studentImageURL", "studentImageUrl", "studentPhotoUrl", "studentPhotoURL"])
	  studentIds[id] = Self.firstString(row, keys: ["studentId", "studentUID", "studentId"])
	  pricesPerMinute[id] = Self.intValue(row["pricePerMinuteCents"])
	  ?? Self.intValue(row["ratePerMinuteCents"])
	  ?? Self.intValue(row["costPerMinuteCents"])
	  ?? 50
	  conversationTypes[id] = (row["conversationType"] as? String) ?? "text"
	}
	
	let newInviteIDs = Set(ids).subtracting(Set(inviteIDs))
	for id in newInviteIDs {
	  LocalNotificationService.shared.scheduleTeacherQuestion(
		questionId: id,
		topic: topics[id] ?? "",
		text: texts[id] ?? ""
	  )
	}
	
	inviteIDs = ids
	inviteTopics = topics
	inviteTexts = texts
	inviteExpiresAt = expiresAtByID
	inviteWaves = waves
	invitePhotoUrls = photoUrlsByID
	inviteHasVoiceMessage = hasVoiceByID
	inviteVoiceMessageDurations = voiceDurationsByID
	inviteStudentNames = studentNames
	inviteStudentImageURLs = studentImageURLs
	inviteStudentUids = studentIds
	invitePricePerMinuteCents = pricesPerMinute
	inviteConversationTypes = conversationTypes
  }
  
  // MARK: - Invite Actions
  
  func acceptInvite(questionId: String) {
	guard acceptingQuestionId == nil, activeQuestionId == nil else { return }
	errorMessage = nil
	let conversationType = inviteConversationTypes[questionId] ?? "text"
	
	acceptingTask?.cancel()
	acceptingTask = Task { [weak self] in
	  guard let self else { return }
	  
	  if conversationType == "audio" || conversationType == "video" {
		let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
		if !micState.isGranted {
		  errorMessage = conversationType == "video"
		  ? LocalizationSupport.localized("Microphone and camera access are required to accept a video session.")
		  : LocalizationSupport.localized("Microphone access is required to accept an audio session.")
		  logger.info("[VM] acceptInvite blocked — mic permission denied qid=\(questionId)")
		  return
		}
	  }
	  if conversationType == "video" {
		let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
		if !cameraState.isGranted {
		  errorMessage = LocalizationSupport.localized("Microphone and camera access are required to accept a video session.")
		  logger.info("[VM] acceptInvite blocked — camera permission denied qid=\(questionId)")
		  return
		}
	  }
	  
	  guard self.acceptingQuestionId == nil, self.activeQuestionId == nil else { return }
	  acceptingQuestionId = questionId
	  isAcceptingCalls = true
	  activeQuestionText = inviteTexts[questionId] ?? ""
	  activeQuestionPhotoUrls = invitePhotoUrls[questionId] ?? []
	  activeStudentName = inviteStudentNames[questionId]?.isEmpty == false ? inviteStudentNames[questionId] ?? "Student" : "Student"
	  activePricePerMinuteCents = invitePricePerMinuteCents[questionId] ?? 50
	  activeConversationType = conversationType
	  activeAcceptedAt = Date().timeIntervalSince1970 * 1000.0
	  AnalyticsService.shared.logEvent(AnalyticsEvent.teacherInviteAccepted, parameters: [
		"question_id": questionId,
		"price_per_minute_cents": activePricePerMinuteCents
	  ])
	  logger.info("TeacherMinute teacherAccept tapped questionId=\(questionId)")
	  logger.info("[VM] acceptInvite tapped — questionId=\(questionId) conversationType=\(conversationType)")
	  
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
		if (conversationType == "audio" || conversationType == "video"),
		   (activeCallRoom?.isEmpty ?? true || activeCallToken?.isEmpty ?? true) {
		  acceptingQuestionId = nil
		  isAcceptingCalls = false
		  clearActiveCallState()
		  errorMessage = LocalizationSupport.localized("Could not start the audio/video connection. Please try again.")
		  logger.error("[VM] acceptInvite missing media credentials questionId=\(questionId) conversationType=\(conversationType) roomEmpty=\(result.liveKitRoom?.isEmpty ?? true) tokenEmpty=\(result.liveKitToken?.isEmpty ?? true)")
		  return
		}
		activeCallStudentUid = result.studentId ?? inviteStudentUids[questionId]
		activeLessonId = result.questionId
		if let studentId = activeCallStudentUid, !studentId.isEmpty,
		   let profile = try? await UserService.shared.fetchProfileSummary(uid: studentId) {
		  if activeStudentName == "Student" {
			activeStudentName = profile.displayName
		  }
		  activeStudentImageURL = profile.profileImageURL
		  activeCurrencyCode = profile.currency
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
		AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherDashboard.acceptInvite")
	  }
	}
  }
  
  func declineInvite(questionId: String) {
	AnalyticsService.shared.logEvent(AnalyticsEvent.teacherInviteDeclined, parameters: ["question_id": questionId])
	Task {
	  do {
		try await FunctionsService.shared.declineInvite(questionId: questionId)
		logger.info("[VM] declineInvite — qid=\(questionId)")
	  } catch {
		AnalyticsService.shared.recordError(error, context: "declineInvite")
		AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherDashboard.declineInvite")
		errorMessage = error.localizedDescription
		logger.error("[VM] declineInvite failed — \(error.localizedDescription)")
	  }
	}
  }
  
  func cancelAcceptingInvite() {
	let questionId = acceptingQuestionId
	acceptingTask?.cancel()
	acceptingTask = nil
	acceptingQuestionId = nil
	isAcceptingCalls = false
	clearActiveCallState()
	if let questionId {
	  declineInvite(questionId: questionId)
	}
  }
  
  func endCall() {
	activeQuestionId = nil
	clearActiveCallState()
	// A lesson just finished — refresh earnings and the Lessons-tab badge count.
	refreshEarnings()
  }
  
  private func clearActiveCallState() {
	activeCallRoom = nil
	activeCallToken = nil
	activeCallStudentUid = nil
	activeLessonId = nil
	activeQuestionText = ""
	activeQuestionPhotoUrls = []
	activeStudentName = "Student"
	activeStudentImageURL = ""
	activePricePerMinuteCents = 50
	activeConversationType = "text"
	activeAcceptedAt = 0
	activeCurrencyCode = LessonFormatting.defaultCurrencyCode
  }
  
  func editSubjects() {
	showsSubjectEditor = true
  }
  
  func reloadSubjects() {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	Task {
	  if let data = try? await UserService.shared.fetchRaw(uid: uid) {
		let summary = UserProfileSummary(uid: uid, data: data)
		subjects = summary?.subjects ?? []
		subjectRawKeys = summary?.rawSubjectKeys ?? []
	  }
	}
  }
  
  func activeChatInitialDetails() -> ChatSessionDetails {
	ChatSessionDetails(
	  questionId: activeLessonId ?? "",
	  studentId: activeCallStudentUid ?? "",
	  teacherId: Auth.auth().currentUser?.uid ?? "",
	  studentName: activeStudentName,
	  teacherName: teacherName,
	  studentImageURL: activeStudentImageURL,
	  teacherImageURL: teacherImageURL,
	  questionText: activeQuestionText,
	  questionPhotoUrls: activeQuestionPhotoUrls,
	  createdAt: 0,
	  acceptedAt: activeAcceptedAt > 0 ? activeAcceptedAt : Date().timeIntervalSince1970 * 1000.0,
	  pricePerMinuteCents: activePricePerMinuteCents,
	  teacherSharePercent: 75,
	  currencyCode: activeCurrencyCode
	)
  }
  
  // English normalized topic keys for RTDB, derived directly from the stored English subtopic names.
  // These are locale-independent regardless of the teacher's language setting.
  var subjectKeys: [String] { subjectRawKeys }
  
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
	
	if let data = try? await UserService.shared.fetchRaw(uid: uid) {
	  let summary = UserProfileSummary(uid: uid, data: data)
	  teacherName = summary?.displayName ?? "Teacher"
	  teacherImageURL = summary?.profileImageURL ?? ""
	  subjects = summary?.subjects ?? []
	  subjectRawKeys = summary?.rawSubjectKeys ?? []
	  ratePerMinuteCents = Self.intValue(data["ratePerMinuteCents"]) ?? 50
	  totalMinutes = summary?.totalMinutes ?? 0
	}
	
	isVerified = (try? await UserService.shared.isTeacherVerified(uid: uid)) ?? false
	// Verification status, subjects and the rate are all known now, so they are
	// released before waiting on the slower rating and earnings queries.
	isLoadingProfile = false
	checkPermissions()
	await loadRating()
	await loadEarnings(uid: uid)
	// Every figure on the dashboard is settled by this point, including the
	// ones a failed fetch left at zero — that is a real answer now, not a
	// placeholder, so the counters can show it.
	isLoadingStats = false
  }

  /// Star average and review count come from the backend rather than the
  /// teacher document, which the app cannot aggregate on its own.
  private func loadRating() async {
	do {
	  let summary = try await FunctionsService.shared.teacherRatingSummary()
	  teacherRating = summary.averageRating
	  reviewCount = summary.ratingCount
	  logger.info("[Rating] dashboard rating=\(summary.averageRating) reviews=\(summary.ratingCount)")
	} catch {
	  logger.error("[Rating] failed loading teacher rating: \(error.localizedDescription)")
	  AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherDashboard.loadRating")
	}
  }
  
  private var earningsCurrencyCode = LessonFormatting.defaultCurrencyCode
  
  /// Reads the same backend summary the Lessons and Earnings tabs do, so the
  /// three screens cannot report different money — see TeacherEarningsStore.
  private func loadEarnings(uid: String) async {
	guard let summary = try? await TeacherEarningsStore.shared.summary() else { return }
	let lessons = summary.lessons

	let calendar = Calendar.current
	let now = Date()
	let startOfToday = calendar.startOfDay(for: now)
	guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
		  let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) else { return }

	var todayEarnings = 0
	var todayMinutes = 0
	var weekEarnings = 0
	var weekMinutes = 0
	var lastWeekEarnings = 0

	for lesson in lessons {
	  let date = lesson.acceptedAt
	  if date >= startOfToday {
		todayEarnings += lesson.teacherEarningsCents
		todayMinutes += max(1, lesson.durationSeconds / 60)
	  }
	  if date >= startOfWeek {
		weekEarnings += lesson.teacherEarningsCents
		weekMinutes += max(1, lesson.durationSeconds / 60)
	  }
	  if date >= startOfLastWeek && date < startOfWeek {
		lastWeekEarnings += lesson.teacherEarningsCents
	  }
	}

	earningsCurrencyCode = summary.currency
	todayEarningsCents = todayEarnings
	todayMinutesTutored = todayMinutes
	weekEarningsCents = weekEarnings
	weekMinutesTutored = weekMinutes
	lastWeekEarningsCents = lastWeekEarnings
	// Taken from the backend's own month bucket rather than re-added here, so
	// this is the identical figure the Earnings tab labels "Current Month".
	monthEarningsCents = summary.months.first(where: { $0.isCurrentMonth })?.earningsCents ?? 0
	lessonCount = lessons.count
	logger.info("[Earnings] dashboard uid=\(uid) currency=\(self.earningsCurrencyCode) lessonCount=\(lessons.count) todayCents=\(todayEarnings) todayMins=\(todayMinutes) weekCents=\(weekEarnings) weekMins=\(weekMinutes) lastWeekCents=\(lastWeekEarnings) monthCents=\(self.monthEarningsCents)")
  }

  /// Re-fetches lessons/earnings so the dashboard and the Lessons-tab badge
  /// reflect a lesson that was just completed.
  func refreshEarnings() {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	Task {
	  // A lesson just ended, so the cached summary is known to be stale.
	  TeacherEarningsStore.shared.invalidate()
	  await loadEarnings(uid: uid)
	}
  }
  
  private func checkPermissions() {
#if !os(Android)
	hasMicAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
	hasCameraAccess = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
#endif
  }
  
  private static func formatCents(_ cents: Int, currency: String = LessonFormatting.defaultCurrencyCode) -> String {
	LessonFormatting.currencyText(cents: cents, currencyCode: currency)
  }
}

// MARK: - Mock

@Observable
@MainActor
final class MockTeacherDashboardViewModel: TeacherDashboardViewModeling {
  var teacherName: String
  var teacherImageURL: String = ""
  var isOnline: Bool
  var inviteIDs: [String] = []
  var inviteTopics: [String: String] = [:]
  var inviteTexts: [String: String] = [:]
  var inviteExpiresAt: [String: Double] = [:]
  var inviteWaves: [String: Int] = [:]
  var invitePhotoUrls: [String: [String]] = [:]
  var inviteHasVoiceMessage: [String: Bool] = [:]
  var inviteVoiceMessageDurations: [String: Int] = [:]
  var inviteStudentNames: [String: String] = [:]
  var inviteStudentImageURLs: [String: String] = [:]
  var inviteConversationTypes: [String: String] = [:]
  var activeCallRoom: String? = nil
  var activeCallToken: String? = nil
  var activeQuestionId: String? = nil
  var activeQuestionText: String = ""
  var activeStudentName: String = "Student"
  var activeStudentImageURL: String = ""
  var activeConversationType: String = "text"
  var acceptingQuestionId: String? = nil
  var errorMessage: String? = nil
  var isAcceptingCalls: Bool = false
  var isVerified: Bool
  var todayEarningsCents: Int
  var todayMinutesTutored: Int
  var weekEarningsCents: Int
  var weekMinutesTutored: Int
  var totalMinutes: Int
  var lessonCount: Int
  var monthEarningsCents: Int
  var teacherRating: Double
  var reviewCount: Int
  var ratePerMinuteCents: Int
  var hasMicAccess: Bool
  var hasCameraAccess: Bool
  var showsSubjectEditor: Bool = false
  /// The mock is handed its figures up front, so nothing is ever pending.
  var isLoadingStats: Bool = false
  var isLoadingProfile: Bool = false
  var subjects: [String]

  var formattedTodayEarnings: String { LessonFormatting.currencyText(cents: todayEarningsCents, currencyCode: LessonFormatting.defaultCurrencyCode) }
  var formattedWeekEarnings: String { LessonFormatting.currencyText(cents: weekEarningsCents, currencyCode: LessonFormatting.defaultCurrencyCode) }
  var formattedMonthEarnings: String { LessonFormatting.currencyText(cents: monthEarningsCents, currencyCode: LessonFormatting.defaultCurrencyCode) }
  var formattedRate: String { LessonFormatting.currencyText(cents: ratePerMinuteCents, currencyCode: LessonFormatting.defaultCurrencyCode) }
  var weekChangeText: String? { nil }
  var hasRating: Bool { reviewCount > 0 }
  var ratingText: String { LessonFormatting.ratingText(teacherRating) }
  var reviewCountText: String {
    if !hasRating {
      return LocalizationSupport.localized("No reviews yet")
    }
    if reviewCount == 1 {
      return LocalizationSupport.localized("1 review")
    }
    return String(format: LocalizationSupport.localized("%d reviews"), reviewCount)
  }
  var subjectsDisplayText: String {
    if subjects.isEmpty {
      return LocalizationSupport.localized("No subjects selected")
    }
    return subjects.map { LocalizationSupport.localized($0) }.joined(separator: ", ")
  }

  init(
    teacherName: String = "Dr. Sarah Cohen",
    isOnline: Bool = false,
    isVerified: Bool = true,
    subjects: [String] = ["Mathematics", "Physics"],
    lessonCount: Int = 47,
    todayEarningsCents: Int = 9600,
    todayMinutesTutored: Int = 80,
    weekEarningsCents: Int = 38500,
    weekMinutesTutored: Int = 320,
    monthEarningsCents: Int = 142000,
    totalMinutes: Int = 2840,
    teacherRating: Double = 4.8,
    reviewCount: Int = 23,
    ratePerMinuteCents: Int = 120,
    hasMicAccess: Bool = true,
    hasCameraAccess: Bool = true
  ) {
    self.teacherName = teacherName
    self.isOnline = isOnline
    self.isVerified = isVerified
    self.subjects = subjects
    self.lessonCount = lessonCount
    self.todayEarningsCents = todayEarningsCents
    self.todayMinutesTutored = todayMinutesTutored
    self.weekEarningsCents = weekEarningsCents
    self.weekMinutesTutored = weekMinutesTutored
    self.monthEarningsCents = monthEarningsCents
    self.totalMinutes = totalMinutes
    self.teacherRating = teacherRating
    self.reviewCount = reviewCount
    self.ratePerMinuteCents = ratePerMinuteCents
    self.hasMicAccess = hasMicAccess
    self.hasCameraAccess = hasCameraAccess

    if isOnline {
      let id = "mock-invite-1"
      inviteIDs = [id]
      inviteTopics = [id: "Calculus"]
      inviteTexts = [id: "Can you help me solve an integral by parts? I'm stuck on ∫x·eˣ dx"]
      inviteExpiresAt = [id: Date().timeIntervalSince1970 * 1000 + 30_000]
      inviteWaves = [id: 1]
      inviteStudentNames = [id: "Alex Kim"]
      inviteStudentImageURLs = [id: ""]
      inviteConversationTypes = [id: "text"]
      invitePhotoUrls = [id: []]
      inviteHasVoiceMessage = [id: false]
    }
  }

  func toggleOnline() { isOnline.toggle() }
  /// Inert in previews: the mock never touches the permission system, so a
  /// preview teacher stays online regardless of the host's notification state.
  func enforceNotificationRequirement() {}
  func acceptInvite(questionId: String) {}
  func declineInvite(questionId: String) { inviteIDs = inviteIDs.filter { $0 != questionId } }
  func cancelAcceptingInvite() {}
  func endCall() { activeQuestionId = nil }
  func editSubjects() { showsSubjectEditor = true }
  func reloadSubjects() {}
  func refreshEarnings() {}
  func activeChatInitialDetails() -> ChatSessionDetails {
    ChatSessionDetails(
      questionId: "",
      studentId: "",
      teacherId: "",
      studentName: activeStudentName,
      teacherName: teacherName,
      studentImageURL: activeStudentImageURL,
      teacherImageURL: teacherImageURL,
      questionText: activeQuestionText,
      questionPhotoUrls: [],
      createdAt: 0,
      acceptedAt: 0,
      pricePerMinuteCents: ratePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: LessonFormatting.defaultCurrencyCode
    )
  }
}
