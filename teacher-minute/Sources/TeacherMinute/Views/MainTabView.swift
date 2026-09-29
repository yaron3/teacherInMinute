//
//  MainTabView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct MainTabView: View {
  @State var viewModel: MainTabViewModel
  @State var teacherDashboardViewModel: TeacherDashboardViewModel?
  /// Held here rather than built inside `tabContent`: constructing it in the
  /// body makes a new instance on every evaluation, so the one the load
  /// mutates need not be the one the view observes — on Android that showed up
  /// as the profile only appearing after switching tabs and back.
  @State var profileViewModel: ProfileViewModel
  /// Held here for the same reason: the home screen is rebuilt whenever the
  /// user comes back to it from the menu, and must not lose a search or a
  /// checkout that is under way.
  @State var studentHomeViewModel: StudentHomeViewModel?
  @Environment(\.appRouter) var router
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  
  init(userMode: AppUserMode = .teacher) {
	self._viewModel = State(wrappedValue: MainTabViewModel(userMode: userMode))
	self._teacherDashboardViewModel = State(wrappedValue: userMode == .teacher ? TeacherDashboardViewModel() : nil)
	self._profileViewModel = State(
	  wrappedValue: ProfileViewModel(roleType: userMode == .teacher ? .teacher : .student)
	)
	self._studentHomeViewModel = State(wrappedValue: userMode == .student ? StudentHomeViewModel() : nil)
  }
  
  var body: some View {
	// The stack exists for the teacher's live session, which is pushed rather
	// than laid over the sections. Its bar stays hidden: every section draws
	// its own header.
	ZStack {
	  NavigationStack {
		tabLayers
		  .toolbar(.hidden, for: .navigationBar)
		  .navigationDestination(isPresented: isTeacherInLiveSession) {
			teacherSessionScreen
		  }
	  }
	  .blurredUnderMenu(viewModel.isSideMenuOpen)

	  sideMenu
	}
	.appDialog(
	  teacherDashboardViewModel?.studentCancelledTitle ?? "",
	  isPresented: isStudentCancelledDialogPresented,
	  message: teacherDashboardViewModel?.studentCancelledMessage,
	  actions: [AppDialogAction(teacherDashboardViewModel?.okLabel ?? "")]
	)
  }

  var sideMenu: some View {
	BrandSideMenuView(viewModel: viewModel, profile: profileViewModel) {
	  viewModel.closeSideMenu()
	  router.startLogin()
	}
  }

  /// The student cancelled while this teacher's accept was on its way. By then
  /// the question's card is gone, so a dialog says what happened.
  var isStudentCancelledDialogPresented: Binding<Bool> {
	Binding(
	  get: { teacherDashboardViewModel?.studentCancelledBeforeStart ?? false },
	  set: { teacherDashboardViewModel?.studentCancelledBeforeStart = $0 }
	)
  }

  /// Drives the push off `activeQuestionId` alone. As on the student side the
  /// setter is inert: a lesson is billed by the minute, so it ends through the
  /// session's own control — which clears the id and so pops this screen.
  var isTeacherInLiveSession: Binding<Bool> {
	Binding(
	  get: { viewModel.userMode == .teacher && teacherDashboardViewModel?.activeQuestionId != nil },
	  set: { _ in }
	)
  }

  @ViewBuilder
  var teacherSessionScreen: some View {
	if let teacherDashboardViewModel, let questionId = teacherDashboardViewModel.activeQuestionId {
	  TeacherLiveSessionScreen(viewModel: teacherDashboardViewModel, questionId: questionId)
	}
  }

  /// Only the selected section is on screen; the side menu and the tab bar
  /// switch between them. Each section places `BrandMenuButton` in its own
  /// header, and the button and the bar find their actions through the
  /// environment.
  var tabLayers: some View {
	ZStack {
	  tabContent(viewModel.selectedTab)
		// Each section starts afresh. On Android, SkipUI otherwise handed the
		// state one section remembered to the next in its place: going from
		// Profile to Settings, Settings' `onChange` of a URL was given a Bool
		// Profile had kept, and the app aborted on the cast.
		.id(viewModel.selectedTab)
		.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		.environment(\.sideMenuAction, sideMenuAction)
		.environment(\.tabBarAction, tabBarAction)

	  teacherGlobalOverlay
	}
	.onChange(of: teacherDashboardViewModel?.lessonCount ?? 0) { _, newCount in
	  viewModel.updateLessonCount(newCount)
	}
	.onChange(of: isTeacherGlobalOverlayVisible) { _, isVisible in
	  // An arriving question or a starting lesson takes the whole screen.
	  if isVisible { viewModel.closeSideMenu() }
	}
	.background { BrandScreenBackground() }
	.navigationBarBackButtonHidden(true)
	.task {
	  print("[Push] MainTabView.task — calling registerCurrentDevice role=\(viewModel.userMode)")
	  PushNotificationService.shared.registerCurrentDevice(role: viewModel.userMode)
	  if let count = teacherDashboardViewModel?.lessonCount {
		viewModel.updateLessonCount(count)
	  }
	}
	.task {
	  // The menu's header shows the user's name, email and photo.
	  if !profileViewModel.hasDisplayableProfileData {
		await profileViewModel.loadProfile()
	  }
	}
	.onAppear {
#if os(Android)
	  AndroidBackNavigationBridge.setSystemBackBlocked(true)
#endif
	}
	.onDisappear {
#if os(Android)
	  AndroidBackNavigationBridge.setSystemBackBlocked(false)
#endif
	}
  }

  var sideMenuAction: SideMenuAction {
	SideMenuAction(
	  accessibilityLabel: viewModel.openMenuLabel,
	  showsBadge: viewModel.shouldShowLessonsBadge,
	  open: { viewModel.openSideMenu() }
	)
  }

  /// The tabs along the bottom of the sections.
  var tabBarAction: TabBarAction {
	TabBarAction(
	  items: viewModel.tabItems,
	  selected: viewModel.selectedTabItem,
	  badged: Set(viewModel.tabItems.filter { viewModel.showsBadge($0) }),
	  select: { item in viewModel.select(item) }
	)
  }

  @ViewBuilder
  func tabContent(_ tab: MainTab) -> some View {
	switch tab {
	  case .home:
		if viewModel.userMode == .student, let studentHomeViewModel {
		  StudentHomeView(
			viewModel: studentHomeViewModel,
			purchaseScreenRequested: $viewModel.isPurchaseScreenRequested
		  )
			.trackScreen(AnalyticsScreen.studentHome)
		} else if let teacherDashboardViewModel {
		  TeacherDashboardView(
			viewModel: teacherDashboardViewModel,
			showsSessionOverlay: false,
			showsIncomingOverlay: false
		  )
		  .trackScreen(AnalyticsScreen.teacherDashboard)
		}
		
	  case .lessons:
		if viewModel.userMode == .student {
		  StudentActivityView()
			.trackScreen(AnalyticsScreen.studentLessonHistory)
		} else {
		  TeacherLessonHistoryView()
			.trackScreen(AnalyticsScreen.teacherLessonHistory)
		}

	  case .earnings:
		TeacherEarningsView()

	  case .profile:
		ProfileView(viewModel: profileViewModel)
		  .trackScreen(AnalyticsScreen.profile)

	  case .settings:
		SettingsView(role: viewModel.userMode, viewModel: nil)
		  .trackScreen(AnalyticsScreen.settings)

	  case .help:
		HelpSupportView(role: viewModel.userMode)
	}
  }
  
  @ViewBuilder
  var teacherGlobalOverlay: some View {
	if viewModel.userMode == .teacher, let teacherDashboardViewModel {
	  if teacherDashboardViewModel.isAcceptingCalls, teacherDashboardViewModel.acceptingQuestionId != nil {
		ConnectionSetupView(
		  participantName: teacherDashboardViewModel.activeStudentName,
		  conversationType: teacherDashboardViewModel.activeConversationType,
		  footerText: teacherDashboardViewModel.settingUpSessionText
		) {
		  teacherDashboardViewModel.cancelAcceptingInvite()
		}
		.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		.zIndex(20)
	  } else if teacherDashboardViewModel.activeQuestionId != nil {
		// Pushed instead — see `teacherSessionScreen`. The branch stays so a
		// running lesson still outranks a queued invite.
		EmptyView()
	  } else if let inviteID = teacherDashboardViewModel.inviteIDs.first {
		TeacherIncomingQuestionOverlay(inviteID: inviteID, viewModel: teacherDashboardViewModel)
		  .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		  .zIndex(20)
	  }
	}
  }
  
  var isTeacherGlobalOverlayVisible: Bool {
	guard viewModel.userMode == .teacher, let teacherDashboardViewModel else { return false }
	return teacherDashboardViewModel.isAcceptingCalls || teacherDashboardViewModel.activeQuestionId != nil || teacherDashboardViewModel.inviteIDs.first != nil
  }
}


/// The teacher's lesson, as a pushed screen.
///
/// It pops itself rather than letting `MainTabView` pop it by clearing
/// `activeQuestionId`: on Android the pushed destination is the only thing
/// composed, so the modifier that would notice the cleared state is not running
/// and the screen would stay up after the lesson ended.
struct TeacherLiveSessionScreen: View {
  let viewModel: any TeacherDashboardViewModeling
  let questionId: String
  @Environment(\.dismiss) var dismiss

  var body: some View {
	ChatSessionView(
	  questionId: questionId,
	  role: "teacher",
	  title: viewModel.chatStudentTitle,
	  conversationType: viewModel.activeConversationType,
	  liveKitRoom: viewModel.activeCallRoom ?? "",
	  liveKitToken: viewModel.activeCallToken ?? "",
	  initialDetails: viewModel.activeChatInitialDetails(),
	  finishesSetupInSettings: viewModel.activeFinishesSetupInSettings,
	  returnsFromSettings: viewModel.activeReturnsFromSettings,
	  onFinishingSetupInSettings: {
		viewModel.rememberLessonLeftForSettings()
	  }
	) {
	  viewModel.endCall()
	  dismiss()
	}
	// The session draws its own header and end control, and must not be
	// escapable by a back tap or edge swipe while it is running.
	.toolbar(.hidden, for: .navigationBar)
	.navigationBarBackButtonHidden(true)
	// Covers the ends this view does not drive itself — a lesson closed out
	// by the other side, or by the dashboard.
	.onChange(of: viewModel.activeQuestionId) { _, id in
	  if id == nil { dismiss() }
	}
	// Compose Navigation would otherwise pop a running lesson on a system
	// back press, so back is taken over for as long as it lasts.
	.onAppear {
#if os(Android)
	  AndroidBackNavigationBridge.setSessionBackBlocked(true)
#endif
	}
	.onDisappear {
#if os(Android)
	  AndroidBackNavigationBridge.setSessionBackBlocked(false)
#endif
	}
  }
}

extension View {
  /// Blurs what an open menu covers, as the design's scrim does: SwiftUI
  /// has no backdrop blur, so the content under the scrim is blurred itself.
  /// On iOS the blur animates with the menu alone, not with the section a
  /// menu tap swaps in at the same moment. Android blurs from API 31.
  func blurredUnderMenu(_ isBlurred: Bool) -> some View {
#if os(Android)
	blur(radius: isBlurred ? 6 : 0)
#else
	animation(.easeOut(duration: 0.25)) { content in
	  content.blur(radius: isBlurred ? 6 : 0, opaque: true)
	}
#endif
  }
}

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
  static var previews: some View {
	MainTabView()
  }
}
#endif
