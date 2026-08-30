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
	  } else if let questionId = teacherDashboardViewModel.activeQuestionId {
		ChatSessionView(
		  questionId: questionId,
		  role: "teacher",
		  title: LocalizationSupport.localized("Student"),
		  conversationType: teacherDashboardViewModel.activeConversationType,
		  liveKitRoom: teacherDashboardViewModel.activeCallRoom ?? "",
		  liveKitToken: teacherDashboardViewModel.activeCallToken ?? "",
		  initialDetails: teacherDashboardViewModel.activeChatInitialDetails()
		) {
		  teacherDashboardViewModel.endCall()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.zIndex(20)
		.onAppear {
		  hidesTabBar = true
		}
		.onDisappear {
		  hidesTabBar = false
		}
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

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
  static var previews: some View {
	MainTabView()
  }
}
#endif
