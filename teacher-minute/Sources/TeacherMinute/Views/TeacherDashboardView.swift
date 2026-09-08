//
//  TeacherDashboardView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

@MainActor
struct TeacherDashboardView: View {
  @State var viewModel: any TeacherDashboardViewModeling
  @Binding var hidesTabBar: Bool
  let showsSessionOverlay: Bool
  let showsIncomingOverlay: Bool
  /// The warning the header is currently showing. Mirrors the view model, but
  /// is only ever assigned inside `withAnimation`, which is what gives the
  /// banner something to animate — a modifier on the banner itself would be
  /// inserted and removed along with it and never drive the transition.
  @State var warningMessage: String?
  @State var showsDocumentsSuggestion = false
  @State var showsDocuments = false
  @State var showsQuestionSimulator = false
  @State var showsMessages = false
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? "en" : SettingsLanguageChoice.system.rawValue
  //@AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.scenePhase) var scenePhase
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(
	viewModel: any TeacherDashboardViewModeling = TeacherDashboardViewModel(),
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
		footerText: viewModel.settingUpSessionText,
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
		title: viewModel.chatStudentTitle,
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
	  VStack(spacing: 0) {
		generalWarningHeader

		ScrollView(.vertical, showsIndicators: false) {
		  VStack(alignment: .leading, spacing: 0) {
			FlatTopHeader(
			  eyebrow: viewModel.teacherEyebrow,
			  name: viewModel.teacherName,
			  avatarImageURL: viewModel.teacherImageURL,
			  avatarSystemImage: "person.crop.circle.fill",
			  showNotificationBadge: false
			)
			.padding(.top, 16)

			statusToggleCard
			  .padding(.top, 20)

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

			  statsCards
				.padding(.top, 28)

			  ratingSection
				.padding(.top, 16)

			  readinessChecklist
				.padding(.top, 28)
			}

			if DemoStudentService.isEnabled {
			  simulateQuestionCard
				.padding(.top, 28)
			}
		  }
		  .padding(.horizontal, 20)
		  .padding(.bottom, 40)
	  }
	  .background(theme.screenBackground)
	  }
	  // Drawn over the whole screen, header included, so an arriving question
	  // covers the warning rather than leaving a stripe above it.
	  .overlay {
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
	  .sheet(isPresented: $showsMessages) {
		NotificationMessagesView()
	  }
	  .sheet(isPresented: Binding(get: { viewModel.showsSubjectEditor }, set: { viewModel.showsSubjectEditor = $0 }), onDismiss: {
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
		SimulateStudentQuestionView(teacherName: viewModel.teacherName) {
		  showsQuestionSimulator = false
		}
		.environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
		.environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
		.id(languagePreference)
	  }
	  .onAppear {
		// Seeded without animation: a banner that is already true on the first
		// frame should be there, not slide in.
		warningMessage = viewModel.errorMessageGeneral
		guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
		Task {
		  if await TeacherDocumentsPromptStore.shouldPresentSuggestion() {
			showsDocumentsSuggestion = true
		  }
		}
	  }
	  .onChange(of: viewModel.errorMessageGeneral) { _, message in
		withAnimation(.easeInOut(duration: 0.25)) {
		  warningMessage = message
		}
	  }
	  .onChange(of: scenePhase) { _, phase in
		if phase == .background {
		  // If notifications are disabled, an online teacher cannot be reached
		  // in the background, so take them offline immediately.
		  viewModel.enforceNotificationRequirement()
		}
	  }

	}
  }

  var teacherHeader: some View {
	HStack(alignment: .center, spacing: 14) {
		ProfileAvatarView(
		  imageURL: viewModel.teacherImageURL,
		  size: 72,
		  fallbackSystemImage: "person.crop.circle.fill",
		  background: theme.cardBackground,
		  tint: theme.primaryText
		)

  
	  VStack(alignment: .leading, spacing: 4) {
		Text(viewModel.teacherDashboardTitle)
		  .font(.system(size: 12, weight: .semibold))
		  .foregroundStyle(theme.accent)

		Text(viewModel.teacherName)
		  .font(.system(size: 22, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		  .multilineTextAlignment(.leading)
	  }
	  Spacer()
	  Button {
		showsMessages = true
	  } label: {
		ZStack {
		  Circle()
			.fill(theme.cardBackground)
			.frame(width: 20, height: 20)
			.overlay {
			  Circle()
				.stroke(theme.screenBackground, lineWidth: 2)
			}
		  PlatformIcon(systemName: "bell", size: 20, weight: .medium, color: theme.primaryText)
		}
	  }
	  .buttonStyle(.plain)

	}
  }

  var statusToggleCard: some View {
	HStack(spacing: 16) {

	  VStack(alignment: .leading, spacing: 4) {
		  Text(viewModel.statusToggleTitle)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(theme.primaryText)
		  
		
		Text(viewModel.statusToggleSubtitle)
		  .font(.system(size: 12))
		  .foregroundStyle(theme.secondaryText)
		  .frame(maxWidth: .infinity, alignment: .leading)
	  }
	  Spacer()

	  // Reads the pending state too: going online waits on the notification
	  // permission, and without this the switch springs back to off while the
	  // system dialog is up, which reads as the tap having been rejected.
	  Toggle("", isOn: Binding(
		get: { viewModel.isOnline || viewModel.isAwaitingOnlinePermission },
		set: { _ in viewModel.toggleOnline() }
	  ))
	  .labelsHidden()
	  .disabled(viewModel.isAwaitingOnlinePermission)
	}
	.padding(16)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  var statsCards: some View {
	HStack(spacing: 12) {
	  statCard(
		value: viewModel.lessonCountText,
		label: viewModel.lessonsLabel,
		valueColor: theme.accent
	  )
	  statCard(
		value: viewModel.formattedMonthEarnings,
		label: viewModel.monthlyIncomeLabel,
		valueColor: theme.positive
	  )
	}
  }

  func statCard(value: String, label: String, valueColor: Color) -> some View {
	FlatCard {
	  VStack(alignment: .leading, spacing: 6) {
		Text(value)
		  .font(.system(size: 32, weight: .bold))
		  .foregroundStyle(valueColor)
		  // The placeholder shown while the figures load is a word, not a
		  // number, and is far wider than anything this card was sized for.
		  .lineLimit(1)
		  .minimumScaleFactor(0.5)
		Text(label)
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
	  }
	  .frame(maxWidth: .infinity, alignment: .leading)
	}
	.frame(maxWidth: .infinity)
  }

  var ratingSection: some View {
	FlatCard {
	  VStack(alignment: .leading, spacing: 8) {
		HStack {
		  Text(viewModel.myRatingLabel)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(theme.primaryText)
			.frame(maxWidth: .infinity, alignment: .leading)
		  Spacer()
		  Text(viewModel.reviewCountText)
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
		}
	  

		  // Until someone has rated this teacher there is no score to draw, and
		  // five empty stars would read as a rating of zero.
		if viewModel.hasRating {
		  HStack {
			Spacer()
			RatingStarsView(rating: viewModel.teacherRating, size: 16, filledColor: theme.warning)
			
			Text(viewModel.ratingText)
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.primaryText)
			Spacer()
		  }
		}
	  }
	}
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
			Text(viewModel.verificationStatusText)
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.primaryText)

			Text(viewModel.subjectsDisplayText)
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
		  }

		  Spacer()
		}
		HStack {
		  Spacer()
		  Button {
			viewModel.editSubjects()
		  } label: {
			FlatChip(title: viewModel.editSubjectsLabel, systemImage: "pencil", outlined: true)
		  }
		  .buttonStyle(.plain)
		  Spacer()
		}
	  }
	}
  }

  var earningsSnapshot: some View {
	VStack(alignment: .leading, spacing: 12) {
	  FlatSectionHeader(viewModel.earningsSnapshotHeader)

	  HStack(spacing: 12) {
		EarningsCard(title: viewModel.earningsTodayTitle, amount: viewModel.formattedTodayEarnings, subtitle: viewModel.todayMinutesTutoredText)
		  .frame(maxWidth: .infinity)
		EarningsCard(title: viewModel.earningsThisWeekTitle, amount: viewModel.formattedWeekEarnings, subtitle: viewModel.weekChangeText ?? viewModel.weekMinutesTutoredText, subtitleColor: viewModel.weekChangeText != nil ? theme.positive : nil)
		  .frame(maxWidth: .infinity)
	  }

	  EarningsCard(
		title: viewModel.earningsAllTimeTitle,
		amount: viewModel.totalMinutesText,
		subtitle: viewModel.totalMinutesTutoredLabel
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
		  Text(viewModel.liveEarningsTodayLabel)
			.font(.system(size: 14))
			.foregroundStyle(theme.secondaryText)

		  Text(viewModel.formattedTodayEarnings)
			.font(.system(size: 40, weight: .bold))
			.foregroundStyle(theme.primaryText)
			.lineLimit(1)
			.minimumScaleFactor(0.5)

		  Text(viewModel.todayMinutesTutoredText)
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
		}

		Spacer()

		FlatBadge(title: viewModel.ratePerMinBadgeText)
	  }
	}
  }

  /// A standing warning that the teacher cannot be reached — notifications
  /// switched off while online, or no connection to the server. It sits above
  /// the scrolling dashboard rather than inside it, because the state it
  /// reports is one a teacher must not be able to scroll past.
  ///
  /// The message is the view model's, so what counts as unreachable is decided
  /// in one place; the view only decides that it is drawn in warning colours.
  @ViewBuilder
  var generalWarningHeader: some View {
	if let warning = warningMessage, !warning.isEmpty {
	  HStack(alignment: .top, spacing: 10) {
		PlatformIcon(systemName: "exclamationmark.triangle.fill", size: 14, weight: .bold, color: theme.warning)
		  .padding(.top, 1)

		Text(warning)
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(theme.warning)
		  .multilineTextAlignment(.leading)
		  .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
	  }
	  .padding(.horizontal, 20)
	  .padding(.vertical, 12)
	  .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
	  .background(theme.warningBackground)
	  .overlay(alignment: .bottom) {
		Rectangle()
		  .fill(theme.warningBorder)
		  .frame(height: flatHairline)
	  }
	  .transition(.opacity)
	}
  }

  var onlineStatusCard: some View {
	FlatCard(padding: 14) {
	  HStack(spacing: 0) {
		statusItem(icon: "mic.fill", title: viewModel.micStatusTitle, subtitle: viewModel.micStatusSubtitle, color: viewModel.hasMicAccess ? theme.positive : theme.secondaryText)
		verticalRule
		statusItem(icon: "video.fill", title: viewModel.camStatusTitle, subtitle: viewModel.camStatusSubtitle, color: viewModel.hasCameraAccess ? theme.positive : theme.secondaryText)
		verticalRule
		statusItem(icon: "circle.fill", title: viewModel.connectionStatusTitle, subtitle: viewModel.connectionStatusSubtitle, color: theme.positive)
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
	  FlatSectionHeader(viewModel.liveQueueHeader) {
		FlatChip(title: viewModel.liveQueueWaitingText)
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
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? "",
			  viewModel: viewModel
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
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? "",
			  viewModel: viewModel
		  ) {
			viewModel.acceptInvite(questionId: inviteID)
		  } decline: {
			viewModel.declineInvite(questionId: inviteID)
		  }
		  .padding(.horizontal, 20)
		  .padding(.top, 24)

		  // `errorMessage`, not `errorMessageGeneral`: this line reports the
		  // accept or decline that just failed. The standing "you are
		  // unreachable" warning has the dashboard header now, and showing it
		  // here as well would bury a failed accept under it.
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
	  FlatSectionHeader(viewModel.readinessChecklistHeader)

	  FlatCard(padding: 0, outlined: true) {
		VStack(spacing: 0) {
		  permissionChecklistRow(
			icon: "mic.fill",
			title: viewModel.micChecklistTitle,
			subtitle: viewModel.micChecklistSubtitle,
			actionTitle: viewModel.micChecklistActionTitle,
			isGranted: viewModel.hasMicAccess,
			action: viewModel.requestMicrophoneAccess
		  )
		  FlatRule()
		  permissionChecklistRow(
			icon: "camera.fill",
			title: viewModel.camChecklistTitle,
			subtitle: viewModel.camChecklistSubtitle,
			actionTitle: viewModel.camChecklistActionTitle,
			isGranted: viewModel.hasCameraAccess,
			action: viewModel.requestCameraAccess
		  )
		  FlatRule()
		  checklistRow(icon: "wifi", title: viewModel.connectionChecklistTitle, subtitle: viewModel.connectionChecklistSubtitle, color: theme.positive)
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

  /// A checklist row the teacher can act on. The plain `checklistRow` reports
  /// something the app cannot change — the network — while these two stand for
  /// a switch the OS owns, so tapping one goes and asks for it.
  func permissionChecklistRow(
	icon: String,
	title: String,
	subtitle: String,
	actionTitle: String,
	isGranted: Bool,
	action: @escaping () -> Void
  ) -> some View {
	Button(action: action) {
	  HStack(spacing: 14) {
		FlatIconTile(systemName: icon, size: 44, tint: isGranted ? theme.positive : theme.secondaryText)

		VStack(alignment: .leading, spacing: 2) {
		  Text(title)
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(theme.primaryText)

		  Text(subtitle)
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
		}

		Spacer()

		Text(actionTitle)
		  .font(.system(size: 14, weight: .bold))
		  .foregroundStyle(isGranted ? theme.secondaryText : theme.accent)
	  }
	  .frame(maxWidth: .infinity, alignment: .leading)
	  .padding(.horizontal, 16)
	  .padding(.vertical, 12)
	  // An opaque background keeps the whole row tappable rather than just the
	  // glyphs in it; `contentShape` is not available in Skip's SwiftUI. This
	  // is the outlined card's own fill, so nothing looks different.
	  .background(theme.screenBackground)
	}
	.buttonStyle(.plain)
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
			.lineLimit(1)
			.minimumScaleFactor(0.5)

		  Text(subtitle)
			.font(.system(size: 12))
			.foregroundStyle(subtitleColor ?? theme.secondaryText)
			.lineLimit(1)
			.minimumScaleFactor(0.7)
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
	let viewModel: any TeacherDashboardViewModeling
	let accept: () -> Void
	let decline: () -> Void

	private var displayStudentName: String {
	  let trimmed = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
	  return trimmed.isEmpty ? viewModel.unnamedStudentLabel : trimmed
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
	  viewModel.liveRequestTimerCaption(isExpired: isExpired)
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
		  FlatChip(title: viewModel.localizedTopicName(topic))
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

		  Text(viewModel.waitingNowLabel)
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
		Text(viewModel.questionSectionHeader)
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.secondaryText)

		// A student can build the question out of equations, so this is the
		// same formula-aware renderer the chat bubbles use: the teacher decides
		// on the question as the student wrote it, not on raw LaTeX.
		FormulaAwareText(
		  text: text,
		  textColor: theme.primaryText,
		  font: .system(size: 15),
		  lineLimit: 6
		)
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
		  Text(viewModel.voiceMessageLabel)
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
		FlatPrimaryButton(title: viewModel.acceptQuestionLabel, action: accept)

		Button(action: decline) {
		  Text(viewModel.declineLabel)
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
  let viewModel: any TeacherDashboardViewModeling
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
			  studentImageURL: viewModel.inviteStudentImageURLs[inviteID] ?? "",
			  viewModel: viewModel
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

#if os(iOS)
#Preview("Offline") {
  TeacherDashboardView(
    viewModel: MockTeacherDashboardViewModel(),
    showsSessionOverlay: false,
    showsIncomingOverlay: false
  )
}

#Preview("Online — Unreachable") {
  let viewModel = MockTeacherDashboardViewModel(isOnline: true)
  viewModel.errorMessageGeneral = viewModel.poorConnectionWarning
  return TeacherDashboardView(
    viewModel: viewModel,
    showsSessionOverlay: false,
    showsIncomingOverlay: false
  )
}

#Preview("Online — Live Queue") {
  TeacherDashboardView(
	viewModel: MockTeacherDashboardViewModel(isOnline: true, errorMessageGeneral: "Must have notification enabled"),
    showsSessionOverlay: false,
    showsIncomingOverlay: false
  )
}
#endif
