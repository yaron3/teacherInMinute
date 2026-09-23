//
//  MainTab.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation
import SkipFuse

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
  var isConfirmingLogOut = false

  /// The menu's main sections, in order. Earnings is teacher-only.
  var primaryMenuTabs: [MainTab] {
	if userMode == .teacher {
	  return [.home, .lessons, .earnings, .profile]
	}
	return [.home, .lessons, .profile]
  }

  /// Listed below the divider, apart from the main sections.
  var secondaryMenuTabs: [MainTab] {
	[.settings, .help]
  }

  /// Badge count for `tab` — only Lessons ever carries one; 0 means no badge.
  func badgeCount(for tab: MainTab) -> Int {
	tab == .lessons && shouldShowLessonsBadge ? 1 : 0
  }

  init(userMode: AppUserMode = .teacher) {
	self.userMode = userMode
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

  // MARK: - Navigation stacks

  /// Whether the section on screen brings its own `NavigationStack`. Those
  /// sections must not be wrapped in another: on Android SkipUI lays a nested
  /// stack out against the outer one's safe area and pushes its content far
  /// down the screen, leaving a large gap above the header.
  var selectedSectionOwnsNavigationStack: Bool {
	switch selectedTab {
	  case .lessons, .settings, .help: true
	  case .home, .earnings, .profile: false
	}
  }

  /// A teacher's lesson started. It is pushed on the stack the teacher's home
  /// sits in, which a section with its own stack is not inside — so bring the
  /// teacher home for it.
  func teacherLessonStarted() {
	if selectedSectionOwnsNavigationStack {
	  select(.home)
	}
  }

  /// Log Out was tapped in the menu. It asks first, as Settings does.
  func logOutTapped() {
	isSideMenuOpen = false
	isConfirmingLogOut = true
  }

  /// Signs out. The caller routes back to sign-in whatever the outcome, the
  /// same as leaving onboarding does: a failed Firebase sign-out still must
  /// not leave the user on a signed-in screen.
  func logOut() {
	isConfirmingLogOut = false
	do {
	  try AuthService().signOut()
	} catch {
	  logger.error("[SideMenu] sign out failed: \(error)")
	}
  }
}
