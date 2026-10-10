//
//  MainTab.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

enum MainTab: Hashable, CaseIterable {
  case home
  case lessons
  case earnings
  case profile
  case settings
  case help

  var title: String {
	switch self {
	  case .home: LocalizationSupport.localized("Home")
	  case .lessons: LocalizationSupport.localized("Lessons")
	  case .earnings: LocalizationSupport.localized("Earnings")
	  case .profile: LocalizationSupport.localized("Profile")
	  case .settings: LocalizationSupport.localized("Settings")
	  case .help: LocalizationSupport.localized("Help & Support")
	}
  }
  
  var systemImage: String {
	switch self {
	  case .home: "house"
	  case .lessons: "teaching_tab_icon"
	  case .earnings: Self.earningsSymbol
	  case .profile: "person"
	  case .settings: "gearshape"
	  case .help: "questionmark.circle"
	}
  }

  var selectedSystemImage: String {
	switch self {
	  case .home: "house.fill"
	  case .lessons: "teaching_tab_icon.fill"
	  case .earnings: "\(Self.earningsSymbol).fill"
	  case .profile: "person.fill"
	  case .settings: "gearshape.fill"
	  case .help: "questionmark.circle.fill"
	}
  }

  /// The Earnings tab wears the currency the money is actually in, rather than
  /// a fixed dollar sign — everything the tab leads to is priced in shekels.
  static var earningsSymbol: String { LessonFormatting.currencySignIcon }
  
  func systemImage(isSelected: Bool) -> String {
	isSelected ? selectedSystemImage : systemImage
  }

  /// Stable, untranslated name for accessibility identifiers.
  var identifier: String {
	switch self {
	  case .home: "home"
	  case .lessons: "lessons"
	  case .earnings: "earnings"
	  case .profile: "profile"
	  case .settings: "settings"
	  case .help: "help"
	}
  }
}

/// A row of the side menu, and a tab of the tab bar. Each shows a section,
/// except Minutes, which opens the purchase screen over Home, and Tutorial,
/// a menu row only, which opens the tutorial. Ask, Minutes, Activity and
/// Tutorial are Instant Teacher's; Home, Lessons and Earnings, Pro Teacher's.
enum MenuItem: Hashable, CaseIterable {
  case ask
  case minutes
  case activity
  case home
  case lessons
  case earnings
  case profile
  case settings
  case help
  case tutorial

  /// The section on screen after the row is picked. Tutorial leaves the
  /// section as it was (see `MainTabViewModel.select(_:)`).
  var tab: MainTab {
	switch self {
	  case .ask, .minutes, .home, .tutorial: .home
	  case .activity, .lessons: .lessons
	  case .earnings: .earnings
	  case .profile: .profile
	  case .settings: .settings
	  case .help: .help
	}
  }

  /// The system icon for a row without one in the brand's set.
  func systemImage(isSelected: Bool) -> String {
	switch self {
	  case .tutorial: isSelected ? "lightbulb.fill" : "lightbulb"
	  default: tab.systemImage(isSelected: isSelected)
	}
  }

  var title: String {
	switch self {
	  case .ask: LocalizationSupport.localized("Ask")
	  case .minutes: LocalizationSupport.localized("Minutes")
	  case .activity: LocalizationSupport.localized("Activity")
	  case .tutorial: LocalizationSupport.localized("Tutorial")
	  case .home, .lessons, .earnings, .profile, .settings, .help: tab.title
	}
  }

  /// Stable, untranslated name for accessibility identifiers.
  var identifier: String {
	switch self {
	  case .ask: "ask"
	  case .minutes: "minutes"
	  case .activity: "activity"
	  case .tutorial: "tutorial"
	  case .home, .lessons, .earnings, .profile, .settings, .help: tab.identifier
	}
  }
}

enum AppUserMode {
  case student
  case teacher
  
  init(role: AuthRole) {
	self = role == .teacher ? .teacher : .student
  }
  
  var rawValue: String {
	switch self {
	  case .student: return "student"
	  case .teacher: return "teacher"
	}
  }
}

@Observable
@MainActor
final class MainTabViewModel {
  var selectedTab: MainTab = .home
  var userMode: AppUserMode

  private(set) var lessonCount = 0
  private(set) var hasUnseenLessons = false

  var shouldShowLessonsBadge: Bool {
	userMode == .teacher && hasUnseenLessons
  }

  /// Whether the side menu — the app's navigation — is open.
  var isSideMenuOpen = false

  /// The menu, in order.
  var menuItems: [MenuItem] {
	switch userMode {
	  case .student: tabItems + [.help, .tutorial]
	  case .teacher: tabItems + [.help]
	}
  }

  /// The tabs along the bottom of the sections: the menu, less Help &
  /// Support. A student's Home, the camera, has no tab bar.
  var tabItems: [MenuItem] {
	switch userMode {
	  case .student: [.ask, .minutes, .activity, .profile, .settings]
	  case .teacher: [.home, .lessons, .earnings, .profile, .settings]
	}
  }

  /// The tab for the section on screen, or nil for Help & Support, which has
  /// none.
  var selectedTabItem: MenuItem? {
	tabItems.first { isSelected($0) }
  }

  /// Whether `item` leads to news waiting inside it: new lessons.
  func showsBadge(_ item: MenuItem) -> Bool {
	item.tab == .lessons && shouldShowLessonsBadge
  }

  /// Set by the menu's Minutes, for Home to open the purchase screen; Home
  /// clears it as it does.
  var isPurchaseScreenRequested = false

  /// The student's tutorial, while it is on screen. It stands in for the
  /// sections rather than over them: the student's Home asks for the camera
  /// as it appears, and that prompt would land on top of the tutorial.
  private(set) var tutorial: StudentTutorialViewModel?

  /// A student who has not made an account yet, and so has no email or phone
  /// to show in the menu, but may have one to log in to.
  var isAnonymousAccount: Bool {
	Auth.auth().currentUser?.isAnonymous == true
  }

  init(userMode: AppUserMode = .teacher) {
	self.userMode = userMode
	// Decided here, before the first frame, so a student's Home never
	// appears — and asks for the camera — under a tutorial about to cover it.
	if userMode == .student, StudentTutorialStore.shouldPresentAutomatically {
	  presentTutorial(source: .launch)
	}
  }

  /// Called whenever the current lesson count is known. Shows the badge only
  /// when new lessons were added since the user last opened the Lessons tab.
  func updateLessonCount(_ count: Int) {
	lessonCount = count

	// Already viewing the tab — treat everything as seen.
	if selectedTab == .lessons {
	  LessonsBadgeStore.markSeen(count: count)
	  hasUnseenLessons = false
	  return
	}

	guard let seen = LessonsBadgeStore.seenCount() else {
	  // First time we learn the count — baseline it so the badge only ever
	  // appears for lessons added from now on, not pre-existing history.
	  LessonsBadgeStore.markSeen(count: count)
	  hasUnseenLessons = false
	  return
	}

	hasUnseenLessons = count > seen
  }

  /// The user opened the Lessons tab — mark all current lessons as seen.
  func markLessonsTabEntered() {
	LessonsBadgeStore.markSeen(count: lessonCount)
	hasUnseenLessons = false
  }

  // MARK: - Side menu

  func openSideMenu() {
	isSideMenuOpen = true
  }

  func closeSideMenu() {
	isSideMenuOpen = false
  }

  /// A section was picked from the menu: show it and close the menu.
  func select(_ tab: MainTab) {
	selectedTab = tab
	isSideMenuOpen = false
	if tab == .lessons {
	  markLessonsTabEntered()
	}
  }

  /// Whether `item` is the row for the section on screen. Minutes never is:
  /// the purchase screen it opens is part of Home, which Ask stands for.
  /// Nor is Tutorial, which opens over whatever section is on screen.
  func isSelected(_ item: MenuItem) -> Bool {
	item != .minutes && item != .tutorial && item.tab == selectedTab
  }

  /// A row of the menu, or a tab, was picked.
  func select(_ item: MenuItem) {
	if item == .tutorial {
	  closeSideMenu()
	  presentTutorial(source: .menu)
	  return
	}
	select(item.tab)
	isPurchaseScreenRequested = item == .minutes
  }

  // MARK: - Tutorial

  func presentTutorial(source: StudentTutorialViewModel.Source) {
	tutorial = StudentTutorialViewModel(source: source) { [weak self] in
	  self?.tutorial = nil
	}
  }
}
