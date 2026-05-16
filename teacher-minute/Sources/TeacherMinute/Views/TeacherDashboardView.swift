//
//  TeacherDashboardView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct TeacherDashboardView: View {
  @State var viewModel: TeacherDashboardViewModel
  @Binding var hidesTabBar: Bool	
  let showsSessionOverlay: Bool
  let showsIncomingOverlay: Bool
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(
	viewModel: TeacherDashboardViewModel = TeacherDashboardViewModel(),
	hidesTabBar: Binding<Bool> = .constant(false),
	showsSessionOverlay: Bool = true,
	showsIncomingOverlay: Bool = true
  ) {
	self._viewModel = State(initialValue: viewModel)
	self._hidesTabBar = hidesTabBar
	self.showsSessionOverlay = showsSessionOverlay
	self.showsIncomingOverlay = showsIncomingOverlay
  }
  
  var body: some View {
	if showsSessionOverlay, viewModel.isAcceptingCalls, viewModel.acceptingQuestionId != nil {
	  ConnectionSetupView(
		participantName: viewModel.activeStudentName,
		hasAudio: false,
		footerText: "Setting up the session",
		onCancel: {
		  viewModel.cancelAcceptingInvite()
		}
	  )
	  .onAppear {
		hidesTabBar = true
	  }
	  .onDisappear {
		hidesTabBar = false
	  }
	} else if showsSessionOverlay, let questionId = viewModel.activeQuestionId {
	  ChatSessionView(
		questionId: questionId,
		role: "teacher",
		title: "Student",
		initialDetails: viewModel.activeChatInitialDetails()
	  ) {
		viewModel.endCall()
	  }
	  .onAppear {
		hidesTabBar = true
	  }
	  .onDisappear {
		hidesTabBar = false
	  }
	} else {
	  ZStack {
		ScrollView(.vertical, showsIndicators: false) {
		  VStack(alignment: .leading, spacing: 0) {
			AppTopHeader(
			  avatarSystemImage: "person.crop.circle.fill",
			  eyebrow: "Teacher Dashboard",
			  name: viewModel.teacherName,
			  showNotificationBadge: viewModel.isOnline
			)
			.padding(.top, 18)
			
			statusHero
			  .padding(.top, 34)
			if viewModel.isOnline {

			  
			  liveEarningsCard
				.padding(.top, 24)
			  
			  onlineStatusCard
				.padding(.top, 20)
			  ZStack {
				liveQueue
				  .padding(.top, 24)
				  .disabled(viewModel.isAcceptingCalls)
				if viewModel.isAcceptingCalls {
				  ProgressView()
				}
			  }
			} else {

			  
			  teacherStatusCard
				.padding(.top, 38)
			  
			  earningsSnapshot
				.padding(.top, 26)
			  
			  readinessChecklist
				.padding(.top, 24)
			}
		  }
		  .padding(.horizontal, 18)
		  .padding(.bottom, 24)
		}
		.background(theme.appCardBackground)
		
		if showsIncomingOverlay, let inviteID = viewModel.inviteIDs.first {
		  TeacherIncomingQuestionOverlay(inviteID: inviteID, viewModel: viewModel)
			.onAppear {
			  hidesTabBar = true
			}
			.onDisappear {
			  hidesTabBar = false
			}
		}
	  }
	  .sheet(isPresented: $viewModel.showsSubjectEditor, onDismiss: {
		viewModel.reloadSubjects()
	  }) {
		NavigationStack {
		  TeacherSubjectsView(isEditing: true)
		}
	  }

	}
  }
  var statusHero: some View {
	VStack(spacing: 0) {
	  Circle()
		.fill(viewModel.isOnline ? theme.appGreenSoft : theme.appGrayBackground)
		.frame(width: 112, height: 112)
		.overlay {
		  Circle()
			.fill(theme.appGreen)
			.frame(width: 84, height: 84)
			.overlay {
			  PlatformIcon(systemName: viewModel.isOnline ? "antenna.radiowaves.left.and.right" : "moon.fill", size: 34, weight: .semibold, color: theme.white)
			}
		}
	  
	  Text(viewModel.isOnline ? "You're Online" : "You're Offline")
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(theme.appPrimaryText)
		.padding(.top, 22)
	  
	  HStack {
		Text(viewModel.isOnline ? "Waiting for students..." : "Go online to start receiving student requests and\nearn money.")
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(theme.appGreen)
		  .lineSpacing(5)
		  .padding(.top, 10)
		  .multilineTextAlignment(.center)
	  }
	  Button {
		viewModel.toggleOnline()
	  } label: {
		HStack(spacing: 10) {
		  if viewModel.isOnline {
			Text("ON")
			  .font(.system(size: 12, weight: .bold))
			  .foregroundStyle(theme.appPrimaryText)
			  .padding(.leading, 16)
			Circle()
			  .fill(theme.appPrimaryText)
			  .frame(width: 44, height: 44)
		  } else {
			Circle()
			  .fill(theme.primaryText)
			  .frame(width: 44, height: 44)
			Text("OFF")
			  .font(.system(size: 12, weight: .bold))
			  .foregroundStyle(theme.appSecondaryText)
			  .padding(.trailing, 14)
		  }
		}
		.frame(height: 48)
		.background(viewModel.isOnline ? theme.appGreen : theme.appBorder)
		.clipShape(Capsule())
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 26)
	}
	.frame(maxWidth: .infinity)
	
  }
  
  var teacherStatusCard: some View {
	RoundedInfoCard {
	  HStack(spacing: 14) {
		Circle()
		  .fill(viewModel.isVerified ? theme.appGreenSoft : theme.appGrayBackground)
		  .frame(width: 38, height: 38)
		  .overlay {
			PlatformIcon(systemName: viewModel.isVerified ? "checkmark.seal" : "clock", size: 15, weight: .semibold, color: viewModel.isVerified ? theme.appGreen : theme.appSecondaryText)
		  }

		VStack(alignment: .leading, spacing: 4) {
		  Text(viewModel.isVerified ? "Verified Expert" : "Pending Verification")
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)

		  Text(viewModel.subjectsDisplayText)
			.font(.system(size: 12))
			.foregroundStyle(theme.appSecondaryText)
		}

		Spacer()

		Button {
		  viewModel.editSubjects()
		} label: {
		  Text("Edit Subjects")
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(theme.appPink)
		}
		.buttonStyle(.plain)
	  }
	}
  }
  
  var earningsSnapshot: some View {
	VStack(alignment: .leading, spacing: 14) {
	  Text("Earnings Snapshot")
		.font(.system(size: 18, weight: .bold))
		.foregroundStyle(theme.appPrimaryText)
	  
	  HStack(spacing: 16) {
		EarningsCard(title: "Today", amount: viewModel.formattedTodayEarnings, subtitle: "\(viewModel.todayMinutesTutored) mins tutored")
		  .frame(maxWidth: .infinity)
		EarningsCard(title: "This Week", amount: viewModel.formattedWeekEarnings, subtitle: viewModel.weekChangeText ?? "\(viewModel.weekMinutesTutored) mins tutored", subtitleColor: viewModel.weekChangeText != nil ? theme.appGreen : nil)
		  .frame(maxWidth: .infinity)
	  }
	}
  }
  
  var liveEarningsCard: some View {
	RoundedInfoCard {
	  HStack {
		VStack(alignment: .leading, spacing: 10) {
		  Text("Live Earnings Today")
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(theme.appSecondaryText)

		  Text(viewModel.formattedTodayEarnings)
			.font(.system(size: 25, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		}

		Spacer()

		VStack(alignment: .trailing, spacing: 8) {
		  SmallPill(title: "⚡ \(viewModel.formattedRate)/min", foreground: theme.appPink, background: theme.appPinkSoft)

		  Text("\(viewModel.todayMinutesTutored) mins tutored")
			.font(.system(size: 11))
			.foregroundStyle(theme.appSecondaryText)
		}
	  }
	}
	.background(theme.appPinkSoft.opacity(0.3))
  }
  
  var onlineStatusCard: some View {
	RoundedInfoCard {
	  HStack {
		statusItem(icon: "mic.fill", title: "Mic", subtitle: viewModel.hasMicAccess ? "On" : "Off", color: viewModel.hasMicAccess ? theme.appGreen : theme.appSecondaryText)
		Spacer()
		statusItem(icon: "video.fill", title: "Cam", subtitle: viewModel.hasCameraAccess ? "Ready" : "Off", color: viewModel.hasCameraAccess ? theme.appGreen : theme.appSecondaryText)
		Spacer()
		statusItem(icon: "circle.fill", title: "Status", subtitle: "Connected", color: theme.appGreen)
	  }
	}
  }
  
  var liveQueue: some View {
	VStack(alignment: .leading, spacing: 14) {
	  HStack {
		Text("Live Queue")
		  .font(.system(size: 18, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		
		Spacer()
		
		SmallPill(title: "\(viewModel.inviteIDs.count) Waiting", foreground: theme.appPrimaryText, background: theme.appGrayBackground)
	  }
	  
	  ForEach(viewModel.inviteIDs, id: \.self) { inviteID in
		LiveRequestCard(
		  id: inviteID,
		  topic: viewModel.inviteTopics[inviteID] ?? "",
		  text: viewModel.inviteTexts[inviteID] ?? "",
		  expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
		  wave: viewModel.inviteWaves[inviteID] ?? 1,
		  photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
		  hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false
		) {
		  viewModel.acceptInvite(questionId: inviteID)
		} decline: {
		  viewModel.declineInvite(questionId: inviteID)
		}
	  }
	}
  }
  
  func incomingQuestionOverlay(inviteID: String) -> some View {
	ZStack {
	  LinearGradient(
		colors: [theme.appPinkSoft.opacity(0.75), theme.appCardBackground],
		startPoint: .top,
		endPoint: .bottom
	  )
	  
	  ScrollView(.vertical, showsIndicators: false) {
		VStack(spacing: 0) {
		  LiveRequestCard(
			id: inviteID,
			topic: viewModel.inviteTopics[inviteID] ?? "",
			text: viewModel.inviteTexts[inviteID] ?? "",
			expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
			wave: viewModel.inviteWaves[inviteID] ?? 1,
			photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
			hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false
		  ) {
			viewModel.acceptInvite(questionId: inviteID)
		  } decline: {
			viewModel.declineInvite(questionId: inviteID)
		  }
		  .padding(.horizontal, 16)
		  .padding(.top, 24)
		  
		  if let errorMessage = viewModel.errorMessage {
			Text(errorMessage)
			  .font(.system(size: 12, weight: .semibold))
			  .foregroundStyle(theme.appPink)
			  .multilineTextAlignment(.center)
			  .padding(.horizontal, 24)
			  .padding(.top, 12)
		  }
		  
		  Spacer(minLength: 32)
		}
		.frame(maxWidth: CGFloat.infinity)
	  }
	}
	.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
  }
  
  var readinessChecklist: some View {
	VStack(alignment: .leading, spacing: 14) {
	  Text("Readiness Checklist")
		.font(.system(size: 16, weight: .bold))
		.foregroundStyle(theme.appPrimaryText)
	  
	  checklistRow(icon: "mic.fill", title: viewModel.hasMicAccess ? "Microphone Enabled" : "Microphone Disabled", subtitle: "Required for voice sessions.", color: viewModel.hasMicAccess ? theme.appGreen : theme.appSecondaryText)
	  checklistRow(icon: "camera.fill", title: viewModel.hasCameraAccess ? "Camera Enabled" : "Camera Disabled", subtitle: "Enable for video tutoring.", color: viewModel.hasCameraAccess ? theme.appGreen : theme.appSecondaryText)
	  checklistRow(icon: "wifi", title: "Connection", subtitle: "Connected", color: theme.appGreen)
	}
	.padding(20)
	.background(theme.appGrayBackground)
	.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
  
  func statusItem(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 6) {
	  PlatformIcon(systemName: icon, size: 13, weight: .semibold, color: color)
	  
	  VStack(alignment: .leading, spacing: 2) {
		Text(title)
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		
		Text(subtitle)
		  .font(.system(size: 10))
		  .foregroundStyle(theme.appSecondaryText)
	  }
	}
  }
  
  func checklistRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 12) {
	  Circle()
		.fill(color.opacity(0.12))
		.frame(width: 30, height: 30)
		.overlay {
		  PlatformIcon(systemName: icon, size: 12, weight: .semibold, color: color)
		}
	  
	  VStack(alignment: .leading, spacing: 3) {
		Text(title)
		  .font(.system(size: 13, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		
		Text(subtitle)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.appSecondaryText)
	  }
	  
	  Spacer()
	}
  }
  
  struct EarningsCard: View {
	@Environment(\.colorScheme) var colorScheme
	var theme: AppTheme {
	  AppTheme(colorScheme: colorScheme)
	}
	let title: String
	let amount: String
	let subtitle: String
	var subtitleColor: Color?
	
	var body: some View {
	  RoundedInfoCard {
		VStack(alignment: .leading, spacing: 8) {
		  Text(title)
			.font(.system(size: 12))
			.foregroundStyle(theme.appSecondaryText)
		  
		  Text(amount)
			.font(.system(size: 25, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  
		  Text(subtitle)
			.font(.system(size: 11))
			.foregroundStyle(subtitleColor ?? theme.appSecondaryText)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	  }
	}
  }
  
  struct LiveRequestCard: View {
	let id: String
	let topic: String
	let text: String
	let expiresAt: Double
	let wave: Int
	let photoUrls: [String]
	let hasVoiceMessage: Bool
	let accept: () -> Void
	let decline: () -> Void
	@State var now = Date().timeIntervalSince1970 * 1000.0
	
	private var isFirstWave: Bool { wave == 1 }
	private var timerValue: Int {
	  let delta = (expiresAt - now) / 1000.0
	  if delta >= 0 {
		return Int(ceil(delta))
	  }
	  return Int(abs(floor(delta)))
	}
	
	private var timerCaption: String {
	  now <= expiresAt ? "SECONDS" : "WAITING"
	}
	@Environment(\.colorScheme) var colorScheme
	var theme: AppTheme {
	  AppTheme(colorScheme: colorScheme)
	}
	
	var body: some View {
	  VStack(spacing: 16) {
		timerView
		studentCard
		questionCard
		acceptButton
		declineButton
	  }
	  .padding(.horizontal, 16)
	  .padding(.vertical, 18)
	  .background(
		LinearGradient(
		  colors: [theme.appPinkSoft.opacity(0.55), theme.appCardBackground],
		  startPoint: .top,
		  endPoint: .center
		)
	  )
	  .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
	  .shadow(color: theme.appPink.opacity(0.12), radius: 18, x: 0, y: 10)
	  .task {
		while true {
		  now = Date().timeIntervalSince1970 * 1000.0
		  try? await Task.sleep(nanoseconds: 1_000_000_000)
		}
	  }
	}
	
	var timerView: some View {
	  ZStack {
		Circle()
		  .stroke(theme.appGreenSoft.opacity(0.85), lineWidth: 4)
		  .frame(width: 74, height: 74)
		
		VStack(spacing: 1) {
		  Text("\(timerValue)")
			.font(.system(size: 21, weight: .bold))
			.foregroundStyle(theme.appPink)
		  Text(timerCaption)
			.font(.system(size: 7, weight: .bold))
			.foregroundStyle(theme.appSecondaryText)
		}
	  }
	}
	
	var studentCard: some View {
	  HStack(spacing: 12) {
		Circle()
		  .fill(theme.appPurpleSoft)
		  .frame(width: 44, height: 44)
		  .overlay {
			PlatformIcon(systemName: "person.crop.circle.fill", size: 24, color: theme.appPurple)
		  }
		
		VStack(alignment: .leading, spacing: 4) {
		  Text("Student")
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  
		  Text("Waiting now")
			.font(.system(size: 11, weight: .medium))
			.foregroundStyle(theme.appSecondaryText)
		}
		
		Spacer()
		
		Text(topic.capitalized)
		  .font(.system(size: 10, weight: .bold))
		  .foregroundStyle(.white)
		  .padding(.horizontal, 12)
		  .padding(.vertical, 8)
		  .background(theme.appPurple)
		  .clipShape(Capsule())
	  }
	  .padding(14)
	  .background(theme.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	var questionCard: some View {
	  VStack(alignment: .leading, spacing: 14) {
		HStack(spacing: 9) {
		  Circle()
			.fill(theme.appPinkSoft)
			.frame(width: 22, height: 22)
			.overlay {
			  PlatformIcon(systemName: "questionmark.circle", size: 11, weight: .bold, color: theme.appPink)
			}
		  
		  Text("QUESTION")
			.font(.system(size: 10, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		}
		
		Text(text)
		  .font(.system(size: 12))
		  .foregroundStyle(theme.appPrimaryText)
		  .lineSpacing(3)
		  .lineLimit(6)
		  .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
		
		if !photoUrls.isEmpty {
		  HStack(spacing: 8) {
			ForEach(photoUrls.prefix(2), id: \.self) { _ in
			  attachmentTile
			}
			Spacer()
		  }
		}
		
		if hasVoiceMessage {
		  voiceMessageRow
		}
	  }
	  .padding(14)
	  .background(theme.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	var attachmentTile: some View {
	  RoundedRectangle(cornerRadius: 9, style: .continuous)
		.fill(theme.appGrayBackground)
		.frame(width: 56, height: 56)
		.overlay {
		  PlatformIcon(systemName: "photo.fill", size: 16, weight: .semibold, color: theme.appSecondaryText)
		}
		.overlay {
		  RoundedRectangle(cornerRadius: 9, style: .continuous)
			.stroke(theme.appBorder, lineWidth: 1)
		}
	}
	
	var voiceMessageRow: some View {
	  HStack(spacing: 12) {
		Circle()
		  .fill(.white)
		  .frame(width: 34, height: 34)
		  .overlay {
			PlatformIcon(systemName: "play.fill", size: 12, weight: .bold, color: theme.appPink)
		  }
		
		VStack(alignment: .leading, spacing: 2) {
		  Text("Voice Message")
			.font(.system(size: 10, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  Text("0:23")
			.font(.system(size: 9, weight: .medium))
			.foregroundStyle(theme.appSecondaryText)
		}
		
		Spacer()
		
		HStack(spacing: 3) {
		  ForEach(0..<6, id: \.self) { index in
			Capsule()
			  .fill(theme.appPink.opacity(index % 2 == 0 ? 0.75 : 0.35))
			  .frame(width: 3, height: CGFloat(14 + (index % 3) * 7))
		  }
		}
	  }
	  .padding(10)
	  .background(theme.appPinkSoft.opacity(0.65))
	  .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
	}
	
	var acceptButton: some View {
	  Button(action: accept) {
		HStack(spacing: 9) {
		  PlatformIcon(systemName: "checkmark.circle.fill", size: 14, weight: .bold, color: theme.white)
		  Text("Accept Question")
			.font(.system(size: 15, weight: .bold))
		}
		.foregroundStyle(.white)
		.frame(maxWidth: .infinity)
		.frame(height: 52)
		.background(theme.appPink)
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.shadow(color: theme.appPink.opacity(0.25), radius: 16, x: 0, y: 8)
	  }
	  .buttonStyle(.plain)
	}
	
	var declineButton: some View {
	  Button(action: decline) {
		HStack(spacing: 6) {
		  PlatformIcon(systemName: "xmark", size: 10, weight: .semibold, color: theme.appSecondaryText)
		  Text("Decline")
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(theme.appSecondaryText)
		}
		.frame(height: 26)
	  }
	  .buttonStyle(.plain)
	}
  }
}
struct TeacherIncomingQuestionOverlay: View {
  let inviteID: String
  let viewModel: TeacherDashboardViewModel
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  LinearGradient(
		colors: [theme.appPinkSoft.opacity(0.75), theme.appCardBackground],
		startPoint: .top,
		endPoint: .bottom
	  )
	  
	  ScrollView(.vertical, showsIndicators: false) {
		VStack(spacing: 0) {
		  TeacherDashboardView.LiveRequestCard(
			id: inviteID,
			topic: viewModel.inviteTopics[inviteID] ?? "",
			text: viewModel.inviteTexts[inviteID] ?? "",
			expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
			wave: viewModel.inviteWaves[inviteID] ?? 1,
			photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
			hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false
		  ) {
			viewModel.acceptInvite(questionId: inviteID)
		  } decline: {
			viewModel.declineInvite(questionId: inviteID)
		  }
		  .padding(.horizontal, 16)
		  .padding(.top, 24)
		  .padding(.bottom, 32)
		}
		.frame(maxWidth: CGFloat.infinity)
	  }
	}
	.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
  }
}
