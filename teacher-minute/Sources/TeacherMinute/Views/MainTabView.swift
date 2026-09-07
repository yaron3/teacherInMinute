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
  @State var hidesTabBar = false
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
  }
  
  var body: some View {
	// The stack exists for the teacher's live session, which is pushed rather
	// than laid over the tabs. Its own bar stays hidden: every screen here
	// draws its own header.
	NavigationStack {
	  tabLayers
		.toolbar(.hidden, for: .navigationBar)
		.navigationDestination(isPresented: isTeacherInLiveSession) {
		  teacherSessionScreen
		}
	}
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

  var tabLayers: some View {
	ZStack {
	  // Driven by `visibleTabs` rather than an `if` around the teacher-only
	  // Earnings tab: a false branch inside TabView still contributes an empty
	  // slot under SkipUI, which rendered as a blank tab on Android.
	  TabView(selection: $viewModel.selectedTab) {
		ForEach(viewModel.visibleTabs, id: \.self) { tab in
		  tabContent(tab)
			.tabItem {
			  Label {
				Text(tab.title)
			  } icon: {
				tabIcon(tab)
			  }
			}
			.tag(tab)
			.badge(viewModel.badgeCount(for: tab))
		}
	  }
	  .toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
	  // Accent selection instead of the system blue.
	  //.tint(theme.accent)
	  
	  teacherGlobalOverlay
	}
	.onChange(of: viewModel.selectedTab) { _, newTab in
	  if !isTeacherGlobalOverlayVisible {
		hidesTabBar = false
	  }
	  if newTab == .lessons {
		viewModel.markLessonsTabEntered()
	  }
	}
	.onChange(of: teacherDashboardViewModel?.lessonCount ?? 0) { _, newCount in
	  viewModel.updateLessonCount(newCount)
	}
	.background(Color(.systemBackground))
	.navigationBarBackButtonHidden(true)
	.navigationBarHidden(true)
	.task {
	  print("[Push] MainTabView.task — calling registerCurrentDevice role=\(viewModel.userMode)")
	  PushNotificationService.shared.registerCurrentDevice(role: viewModel.userMode)
	  if let count = teacherDashboardViewModel?.lessonCount {
		viewModel.updateLessonCount(count)
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
  
  /// Tab bar icon for `tab`, filled while it is the selected tab.
  @ViewBuilder
  func tabIcon(_ tab: MainTab) -> some View {
	let name = tab.systemImage(isSelected: viewModel.selectedTab == tab)
	if tab == .lessons {
	  // Bundled asset, not an SF Symbol.
	  Image(name, bundle: .module)
		.renderingMode(.template)
		.resizable()
		.aspectRatio(contentMode: .fit)
		.frame(width: 40, height: 40)
	} else {
#if os(iOS)
	  // iOS forces the .fill variant on every tab bar symbol, so "house" and
	  // "house.fill" render identically. Opting out lets the name decide.
	  Image(systemName: name)
		.environment(\.symbolVariants, .none)
#else
	  // SkipUI maps only a subset of SF Symbols and draws a warning triangle
	  // for the rest — which is what "dollarsign.circle" was rendering as. Go
	  // through PlatformIcon so Android uses the app's own icon table, the
	  // same as every other icon in the app.
	  PlatformIcon(systemName: name, size: 22)
#endif
	}
  }

  @ViewBuilder
  func tabContent(_ tab: MainTab) -> some View {
	switch tab {
	  case .home:
		if viewModel.userMode == .student {
		  StudentHomeView(hidesTabBar: $hidesTabBar)
			.trackScreen(AnalyticsScreen.studentHome)
		} else if let teacherDashboardViewModel {
		  TeacherDashboardView(
			viewModel: teacherDashboardViewModel,
			hidesTabBar: $hidesTabBar,
			showsSessionOverlay: false,
			showsIncomingOverlay: false
		  )
		  .trackScreen(AnalyticsScreen.teacherDashboard)
		}
		
	  case .lessons:
		if viewModel.userMode == .student {
		  StudentLessonHistoryView()
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
	}
  }
  
  @ViewBuilder
  var teacherGlobalOverlay: some View {
	if viewModel.userMode == .teacher, let teacherDashboardViewModel {
	  if teacherDashboardViewModel.isAcceptingCalls, teacherDashboardViewModel.acceptingQuestionId != nil {
		ConnectionSetupView(
		  participantName: teacherDashboardViewModel.activeStudentName,
		  conversationType: teacherDashboardViewModel.activeConversationType,
		  footerText: LocalizationSupport.localized("Setting up the session")
		) {
		  teacherDashboardViewModel.cancelAcceptingInvite()
		}
		.frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		.zIndex(20)
		.onAppear {
		  hidesTabBar = true
		}
		.onDisappear {
		  hidesTabBar = false
		}
	  } else if teacherDashboardViewModel.activeQuestionId != nil {
		// Pushed instead — see `teacherSessionScreen`. The branch stays so a
		// running lesson still outranks a queued invite.
		EmptyView()
	  } else if let inviteID = teacherDashboardViewModel.inviteIDs.first {
		TeacherIncomingQuestionOverlay(inviteID: inviteID, viewModel: teacherDashboardViewModel)
		  .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
		  .zIndex(20)
		  .onAppear {
			hidesTabBar = true
		  }
		  .onDisappear {
			hidesTabBar = false
		  }
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
	  title: LocalizationSupport.localized("Student"),
	  conversationType: viewModel.activeConversationType,
	  liveKitRoom: viewModel.activeCallRoom ?? "",
	  liveKitToken: viewModel.activeCallToken ?? "",
	  initialDetails: viewModel.activeChatInitialDetails()
	) {
	  viewModel.endCall()
	  dismiss()
	}
	// The session draws its own header and end control, and must not be
	// escapable by a back tap or edge swipe while it is running.
	.toolbar(.hidden, for: .tabBar)
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

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
  static var previews: some View {
	MainTabView()
  }
}
#endif
