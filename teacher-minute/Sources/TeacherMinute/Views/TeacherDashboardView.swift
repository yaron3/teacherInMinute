//
//  TeacherDashboardView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

@MainActor
struct TeacherDashboardView: View {
  @State var viewModel: TeacherDashboardViewModel
  @Binding var hidesTabBar: Bool
  let showsSessionOverlay: Bool
  let showsIncomingOverlay: Bool
  @State var showsDocumentsSuggestion = false
  @State var showsDocuments = false
  @State var showsQuestionSimulator = false
  @State  var isDemoEnabled = DemoStudentService.isEnabled
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
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
		conversationType: viewModel.activeConversationType,
		footerText: LocalizationSupport.localized("Setting up the session"),
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
			title: LocalizationSupport.localized("Student"),
			conversationType: viewModel.activeConversationType,
            liveKitRoom: viewModel.activeCallRoom ?? "",
            liveKitToken: viewModel.activeCallToken ?? "",
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
			FlatTopHeader(
			  eyebrow: LocalizationSupport.localized("Teacher Dashboard"),
			  name: viewModel.teacherName,
			  avatarSystemImage: "person.crop.circle.fill",
			  showNotificationBadge: viewModel.isOnline
			)
			.padding(.top, 16)

			statusHero
			  .padding(.top, 28)
			if viewModel.isOnline {


			  liveEarningsCard
				.padding(.top, 28)

			  onlineStatusCard
				.padding(.top, 12)
			  ZStack {
				liveQueue
				  .padding(.top, 28)
				  .disabled(viewModel.isAcceptingCalls)
				if viewModel.isAcceptingCalls {
				  ProgressView()
				}
			  }
			} else {


			  teacherStatusCard
				.padding(.top, 28)

			  earningsSnapshot
				.padding(.top, 28)

			  readinessChecklist
				.padding(.top, 28)
			}

			if isDemoEnabled {
			  simulateQuestionCard
				.padding(.top, 28)
			}
		  }
		  .padding(.horizontal, 20)
		  .padding(.bottom, 40)
		}
		.background(theme.screenBackground)

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
	  // After a teacher's first lesson (> 1 min) suggest completing the
	  // optional verification documents — a one-time, dismissible prompt (bug #24).
	  .sheet(isPresented: $showsDocumentsSuggestion) {
		TeacherDocumentsSuggestionView {
		  TeacherDocumentsPromptStore.markSuggestionShown()
		  showsDocumentsSuggestion = false
		  showsDocuments = true
		} onDismiss: {
		  TeacherDocumentsPromptStore.markSuggestionShown()
		  showsDocumentsSuggestion = false
		}
		.environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
		.environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
		.id(languagePreference)
	  }
	  .sheet(isPresented: $showsDocuments) {
		NavigationStack {
		  TeacherDocumentsView()
		}
		.environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
		.environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
		.id(languagePreference)
	  }
	  // Demo tool — sends this teacher a simulated question written by the
	  // local AI model behind the demo-student service.
	  .sheet(isPresented: $showsQuestionSimulator) {
		SimulateStudentQuestionView { simulation in
		  viewModel.startDemoSimulation(simulation)
		} onClose: {
		  showsQuestionSimulator = false
		}
		.environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
		.environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
		.id(languagePreference)
	  }
	  .onAppear {
		Task {
		  if await TeacherDocumentsPromptStore.shouldPresentSuggestion() {
			showsDocumentsSuggestion = true
		  }
		}
	  }
	  .task {
		await RemoteConfigService.shared.ready()
		isDemoEnabled = DemoStudentService.isEnabled
	  }

	}
  }

  // Status is carried by type weight and a single solid dot rather than a
  // stacked-circle badge, so the block reads as one clean left-aligned column.
  var statusHero: some View {
	VStack(alignment: .leading, spacing: 0) {
	  HStack(spacing: 8) {
		FlatStatusDot(color: viewModel.isOnline ? theme.positive : theme.secondaryText)

		Text(viewModel.isOnline ? LocalizationSupport.localized("ONLINE") : LocalizationSupport.localized("OFFLINE"))
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(viewModel.isOnline ? theme.positive : theme.secondaryText)
	  }

	  FlatPageTitle(title: viewModel.isOnline ? LocalizationSupport.localized("You're Online") : LocalizationSupport.localized("You're Offline"))
		.padding(.top, 10)

	  Text(viewModel.isOnline ? LocalizationSupport.localized("Waiting for students...") : LocalizationSupport.localized("Go online to start receiving student requests and\nearn money."))
		.font(.system(size: 15))
		.foregroundStyle(theme.secondaryText)
		.lineSpacing(4)
		.padding(.top, 6)
		.frame(maxWidth: .infinity, alignment: .leading)

	  if viewModel.isOnline {
		FlatSecondaryButton(title: LocalizationSupport.localized("Go Offline"), systemImage: "moon.fill") {
		  viewModel.toggleOnline()
		}
		.padding(.top, 22)
	  } else {
		FlatPrimaryButton(title: LocalizationSupport.localized("Go Online"), systemImage: "antenna.radiowaves.left.and.right") {
		  viewModel.toggleOnline()
		}
		.padding(.top, 22)
	  }
	}
	.frame(maxWidth: .infinity, alignment: .leading)
  }
  
  /// Demo-only entry point: sends this teacher a simulated student question,
  /// written by a local AI model. Hidden in release builds unless the
  /// `demo_student_enabled` Remote Config flag is on.
  var simulateQuestionCard: some View {
	FlatCard(outlined: true) {
	  VStack(alignment: .leading, spacing: 14) {
		HStack(alignment: .top, spacing: 12) {
		  FlatIconTile(
			systemName: "wand.and.stars",
			size: 44,
			tint: theme.accent,
			background: theme.accentBackground
		  )

		  VStack(alignment: .leading, spacing: 3) {
			Text(LocalizationSupport.localized("Demo Mode"))
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.primaryText)

			Text(LocalizationSupport.localized("Send yourself a question from a simulated student."))
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
			  .frame(maxWidth: .infinity, alignment: .leading)
		  }
		}

		FlatSecondaryButton(
		  title: LocalizationSupport.localized("Simulate a Student Question"),
		  systemImage: "paperplane.fill"
		) {
		  showsQuestionSimulator = true
		}

		if let demoStatusMessage = viewModel.demoStatusMessage {
		  HStack(spacing: 8) {
			ProgressView()
			Text(demoStatusMessage)
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
		  }
		}

		if let demoErrorMessage = viewModel.demoErrorMessage {
		  Text(demoErrorMessage)
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(theme.danger)
			.lineSpacing(3)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	  }
	}
  }

  var teacherStatusCard: some View {
	// The subject list wraps to several lines, so the action sits on its own row
	// underneath rather than competing with it for horizontal space.
	FlatCard {
	  VStack(alignment: .leading, spacing: 14) {
		HStack(alignment: .top, spacing: 12) {
		  FlatIconTile(
			systemName: viewModel.isVerified ? "checkmark.seal" : "clock",
			size: 44,
			tint: viewModel.isVerified ? theme.positive : theme.secondaryText,
			background: theme.screenBackground
		  )

		  VStack(alignment: .leading, spacing: 3) {
			Text(viewModel.isVerified ? LocalizationSupport.localized("Verified Expert") : LocalizationSupport.localized("Pending Verification"))
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.primaryText)

			Text(viewModel.subjectsDisplayText)
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
		  }

		  Spacer()
		}

		Button {
		  viewModel.editSubjects()
		} label: {
		  FlatChip(title: LocalizationSupport.localized("Edit Subjects"), systemImage: "pencil", outlined: true)
		}
		.buttonStyle(.plain)
	  }
	}
  }

  var earningsSnapshot: some View {
	VStack(alignment: .leading, spacing: 12) {
	  FlatSectionHeader(LocalizationSupport.localized("Earnings Snapshot"))

	  HStack(spacing: 12) {
		EarningsCard(title: LocalizationSupport.localized("Today"), amount: viewModel.formattedTodayEarnings, subtitle: String(format: LocalizationSupport.localized("%d mins tutored"), viewModel.todayMinutesTutored))
		  .frame(maxWidth: .infinity)
		EarningsCard(title: LocalizationSupport.localized("This Week"), amount: viewModel.formattedWeekEarnings, subtitle: viewModel.weekChangeText ?? String(format: LocalizationSupport.localized("%d mins tutored"), viewModel.weekMinutesTutored), subtitleColor: viewModel.weekChangeText != nil ? theme.positive : nil)
		  .frame(maxWidth: .infinity)
	  }

	  EarningsCard(
		title: LocalizationSupport.localized("All Time"),
		amount: String(format: LocalizationSupport.localized("%d min"), viewModel.totalMinutes),
		subtitle: LocalizationSupport.localized("Total minutes tutored")
	  )
	  .frame(maxWidth: .infinity)
	}
  }

  // Filled rather than outlined so the live figure reads as the one emphasised
  // surface on the online dashboard.
  var liveEarningsCard: some View {
	FlatCard(padding: 20) {
	  HStack(alignment: .top) {
		VStack(alignment: .leading, spacing: 6) {
		  Text(LocalizationSupport.localized("Live Earnings Today"))
			.font(.system(size: 14))
			.foregroundStyle(theme.secondaryText)

		  Text(viewModel.formattedTodayEarnings)
			.font(.system(size: 40, weight: .bold))
			.foregroundStyle(theme.primaryText)

		  Text(String(format: LocalizationSupport.localized("%d mins tutored"), viewModel.todayMinutesTutored))
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
		}

		Spacer()

		FlatBadge(title: String(format: LocalizationSupport.localized("%@/min"), viewModel.formattedRate))
	  }
	}
  }

  var onlineStatusCard: some View {
	FlatCard(padding: 14) {
	  HStack(spacing: 0) {
		statusItem(icon: "mic.fill", title: LocalizationSupport.localized("Mic"), subtitle: viewModel.hasMicAccess ? LocalizationSupport.localized("On") : LocalizationSupport.localized("Off"), color: viewModel.hasMicAccess ? theme.positive : theme.secondaryText)
		verticalRule
		statusItem(icon: "video.fill", title: LocalizationSupport.localized("Cam"), subtitle: viewModel.hasCameraAccess ? LocalizationSupport.localized("Ready") : LocalizationSupport.localized("Off"), color: viewModel.hasCameraAccess ? theme.positive : theme.secondaryText)
		verticalRule
		statusItem(icon: "circle.fill", title: LocalizationSupport.localized("Status"), subtitle: LocalizationSupport.localized("Connected"), color: theme.positive)
	  }
	}
  }

  var verticalRule: some View {
	Rectangle()
	  .fill(theme.separator)
	  .frame(width: flatHairline, height: 30)
  }

  var liveQueue: some View {
	VStack(alignment: .leading, spacing: 12) {
	  FlatSectionHeader(LocalizationSupport.localized("Live Queue")) {
		FlatChip(title: String(format: LocalizationSupport.localized("%d Waiting"), viewModel.inviteIDs.count))
	  }

	  ForEach(viewModel.inviteIDs, id: \.self) { inviteID in
		LiveRequestCard(
		  id: inviteID,
		  topic: viewModel.inviteTopics[inviteID] ?? "",
		  text: viewModel.inviteTexts[inviteID] ?? "",
		  expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
		  wave: viewModel.inviteWaves[inviteID] ?? 1,
		  photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
		  hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false,
		  voiceMessageDurationSeconds: viewModel.inviteVoiceMessageDurations[inviteID],
		  conversationType: viewModel.inviteConversationTypes[inviteID] ?? "text",
			  studentName: viewModel.inviteStudentNames[inviteID] ?? "",
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? ""
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
	  theme.screenBackground

	  ScrollView(.vertical, showsIndicators: false) {
		VStack(spacing: 0) {
		  LiveRequestCard(
			id: inviteID,
			topic: viewModel.inviteTopics[inviteID] ?? "",
			text: viewModel.inviteTexts[inviteID] ?? "",
			expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
			wave: viewModel.inviteWaves[inviteID] ?? 1,
			photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
			hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false,
			voiceMessageDurationSeconds: viewModel.inviteVoiceMessageDurations[inviteID],
			conversationType: viewModel.inviteConversationTypes[inviteID] ?? "text",
			  studentName: viewModel.inviteStudentNames[inviteID] ?? "",
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? ""
		  ) {
			viewModel.acceptInvite(questionId: inviteID)
		  } decline: {
			viewModel.declineInvite(questionId: inviteID)
		  }
		  .padding(.horizontal, 20)
		  .padding(.top, 24)

		  if let errorMessage = viewModel.errorMessage {
			Text(errorMessage)
			  .font(.system(size: 13, weight: .semibold))
			  .foregroundStyle(theme.danger)
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
	VStack(alignment: .leading, spacing: 12) {
	  FlatSectionHeader(LocalizationSupport.localized("Readiness Checklist"))

	  FlatCard(padding: 0, outlined: true) {
		VStack(spacing: 0) {
		  checklistRow(icon: "mic.fill", title: viewModel.hasMicAccess ? LocalizationSupport.localized("Microphone Enabled") : LocalizationSupport.localized("Microphone Disabled"), subtitle: LocalizationSupport.localized("Required for voice sessions."), color: viewModel.hasMicAccess ? theme.positive : theme.secondaryText)
		  FlatRule()
		  checklistRow(icon: "camera.fill", title: viewModel.hasCameraAccess ? LocalizationSupport.localized("Camera Enabled") : LocalizationSupport.localized("Camera Disabled"), subtitle: LocalizationSupport.localized("Enable for video tutoring."), color: viewModel.hasCameraAccess ? theme.positive : theme.secondaryText)
		  FlatRule()
		  checklistRow(icon: "wifi", title: LocalizationSupport.localized("Connection"), subtitle: LocalizationSupport.localized("Connected"), color: theme.positive)
		}
	  }
	}
  }

  func statusItem(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 8) {
	  PlatformIcon(systemName: icon, size: 14, weight: .semibold, color: color)

	  VStack(alignment: .leading, spacing: 1) {
		Text(title)
		  .font(.system(size: 12, weight: .bold))
		  .foregroundStyle(theme.primaryText)

		Text(subtitle)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.secondaryText)
	  }
	}
	.frame(maxWidth: .infinity)
  }

  func checklistRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 14) {
	  FlatIconTile(systemName: icon, size: 44, tint: color)

	  VStack(alignment: .leading, spacing: 2) {
		Text(title)
		  .font(.system(size: 15, weight: .bold))
		  .foregroundStyle(theme.primaryText)

		Text(subtitle)
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
	  }

	  Spacer()
	}
	.padding(.horizontal, 16)
	.padding(.vertical, 12)
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
	  FlatCard {
		VStack(alignment: .leading, spacing: 6) {
		  Text(title)
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(theme.secondaryText)

		  Text(amount)
			.font(.system(size: 26, weight: .bold))
			.foregroundStyle(theme.primaryText)

		  Text(subtitle)
			.font(.system(size: 12))
			.foregroundStyle(subtitleColor ?? theme.secondaryText)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	  }
	}
  }

  // One bordered container split by hairlines, instead of nested rounded cards
  // floating on a gradient.
  struct LiveRequestCard: View {
	let id: String
	let topic: String
	let text: String
	let expiresAt: Double
	let wave: Int
	let photoUrls: [String]
	let hasVoiceMessage: Bool
	let voiceMessageDurationSeconds: Int?
	var conversationType: String = "text"
	var studentName: String = ""
	var studentImageURL: String = ""
	let accept: () -> Void
	let decline: () -> Void

	private var displayStudentName: String {
	  let trimmed = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
	  return trimmed.isEmpty ? LocalizationSupport.localized("Student") : trimmed
	}

	private var sessionIcon: String? {
	  switch conversationType {
	  case "audio": return "mic.fill"
	  case "video": return "video.fill"
	  default: return nil
	  }
	}

	private var formattedVoiceMessageDuration: String? {
	  guard let seconds = voiceMessageDurationSeconds, seconds >= 0 else { return nil }
	  return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
	}
	@State var now = Date().timeIntervalSince1970 * 1000.0

	private var isFirstWave: Bool { wave == 1 }
	private var timerValue: Int {
	  let delta = (expiresAt - now) / 1000.0
	  if delta >= 0 {
		return Int(ceil(delta))
	  }
	  return Int(abs(floor(delta)))
	}

	private var isExpired: Bool { now > expiresAt }

	private var timerCaption: String {
	  now <= expiresAt ? LocalizationSupport.localized("SECONDS") : LocalizationSupport.localized("WAITING")
	}
	@Environment(\.colorScheme) var colorScheme
	@Environment(\.horizontalSizeClass) var hSizeClass
	var theme: AppTheme {
	  AppTheme(colorScheme: colorScheme)
	}

	var body: some View {
	  FlatCard(padding: 0, outlined: true) {
		VStack(spacing: 0) {
		  headerRow
		  FlatRule()
		  studentRow
		  FlatRule()
		  questionSection
		  actions
		}
	  }
	  .task {
		while true {
		  now = Date().timeIntervalSince1970 * 1000.0
		  try? await Task.sleep(nanoseconds: 1_000_000_000)
		}
	  }
	}

	var headerRow: some View {
	  HStack(alignment: .firstTextBaseline, spacing: 8) {
		Text("\(timerValue)")
		  .font(.system(size: 32, weight: .bold))
		  .foregroundStyle(isExpired ? theme.secondaryText : theme.primaryText)

		Text(timerCaption)
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.secondaryText)

		Spacer()

		HStack(spacing: 6) {
		  if let icon = sessionIcon {
			PlatformIcon(systemName: icon, size: 14, weight: .medium, color: theme.primaryText)
		  }
		  FlatChip(title: LocalizationSupport.localized(topic.capitalized))
		}
	  }
	  .padding(.horizontal, 16)
	  .padding(.vertical, 14)
	}

	var studentRow: some View {
	  HStack(spacing: 12) {
		ProfileAvatarView(
		  imageURL: studentImageURL,
		  size: 40,
		  fallbackSystemImage: "person.crop.circle.fill",
		  background: theme.cardBackground,
		  tint: theme.primaryText
		)

		VStack(alignment: .leading, spacing: 2) {
		  Text(displayStudentName)
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(theme.primaryText)

		  Text(LocalizationSupport.localized("Waiting now"))
			.font(.system(size: 12))
			.foregroundStyle(theme.secondaryText)
		}

		Spacer()
	  }
	  .padding(.horizontal, 16)
	  .padding(.vertical, 14)
	}

	var questionSection: some View {
	  VStack(alignment: .leading, spacing: 12) {
		Text(LocalizationSupport.localized("QUESTION"))
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.secondaryText)

		Text(text)
		  .font(.system(size: 15))
		  .foregroundStyle(theme.primaryText)
		  .lineSpacing(4)
		  .lineLimit(6)
		  .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)

		if !photoUrls.isEmpty {
		  VStack(spacing: 10) {
			ForEach(photoUrls.prefix(4), id: \.self) { url in
			  attachmentTile(url: url)
			}
		  }
		}

		if hasVoiceMessage {
		  voiceMessageRow
		}
	  }
	  .padding(.horizontal, 16)
	  .padding(.vertical, 14)
	}

	func attachmentTile(url: String) -> some View {
	  let minSide: CGFloat = hSizeClass == .regular ? 700 : 500
	  return RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
		.fill(theme.cardBackground)
		.frame(maxWidth: CGFloat.infinity)
		.frame(minHeight: minSide)
		.overlay {
		  CachedRemoteImage(url: url, contentMode: .fit)
			.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		}
		.clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
			.stroke(theme.separator, lineWidth: flatHairline)
		}
	}

	var voiceMessageRow: some View {
	  HStack(spacing: 12) {
		FlatIconTile(systemName: "play.fill", size: 40, background: theme.screenBackground)

		VStack(alignment: .leading, spacing: 1) {
		  Text(LocalizationSupport.localized("Voice Message"))
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(theme.primaryText)
		  if let formatted = formattedVoiceMessageDuration {
			Text(formatted)
			  .font(.system(size: 12))
			  .foregroundStyle(theme.secondaryText)
		  }
		}

		Spacer()

		HStack(spacing: 3) {
		  ForEach(0..<6, id: \.self) { index in
			Capsule()
			  .fill(theme.primaryText)
			  .frame(width: 3, height: CGFloat(10 + (index % 3) * 6))
		  }
		}
	  }
	  .padding(12)
	  .background(theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
	}

	var actions: some View {
	  VStack(spacing: 10) {
		FlatPrimaryButton(title: LocalizationSupport.localized("Accept Question"), action: accept)

		Button(action: decline) {
		  Text(LocalizationSupport.localized("Decline"))
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(theme.secondaryText)
			.frame(maxWidth: .infinity)
			.frame(height: 36)
		}
		.buttonStyle(.plain)
	  }
	  .padding(.horizontal, 16)
	  .padding(.bottom, 16)
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
	  theme.screenBackground

	  ScrollView(.vertical, showsIndicators: false) {
		VStack(spacing: 0) {
		  TeacherDashboardView.LiveRequestCard(
			id: inviteID,
			topic: viewModel.inviteTopics[inviteID] ?? "",
			text: viewModel.inviteTexts[inviteID] ?? "",
			expiresAt: viewModel.inviteExpiresAt[inviteID] ?? 0.0,
			wave: viewModel.inviteWaves[inviteID] ?? 1,
			photoUrls: viewModel.invitePhotoUrls[inviteID] ?? [],
			hasVoiceMessage: viewModel.inviteHasVoiceMessage[inviteID] ?? false,
			voiceMessageDurationSeconds: viewModel.inviteVoiceMessageDurations[inviteID],
			conversationType: viewModel.inviteConversationTypes[inviteID] ?? "text",
			  studentName: viewModel.inviteStudentNames[inviteID] ?? "",
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? ""
		  ) {
			viewModel.acceptInvite(questionId: inviteID)
		  } decline: {
			viewModel.declineInvite(questionId: inviteID)
		  }
		  .padding(.horizontal, 20)
		  .padding(.top, 24)
		  .padding(.bottom, 32)
		}
		.frame(maxWidth: CGFloat.infinity)
	  }
	}
	.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
  }
}
