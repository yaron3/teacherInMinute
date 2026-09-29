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

/// A row of Instant Teacher's menu. Each shows a section, except Minutes,
/// which opens the purchase screen over Home.
enum StudentMenuItem: Hashable, CaseIterable {
  case ask
  case minutes
  case activity
  case profile
  case settings
  case help

  /// The section on screen after the row is picked.
  var tab: MainTab {
	switch self {
	  case .ask, .minutes: .home
	  case .activity: .lessons
	  case .profile: .profile
	  case .settings: .settings
	  case .help: .help
	}
  }

  var title: String {
	switch self {
	  case .ask: LocalizationSupport.localized("Ask")
	  case .minutes: LocalizationSupport.localized("Minutes")
	  case .activity: LocalizationSupport.localized("Activity")
	  case .profile, .settings, .help: tab.title
	}
  }

  /// Stable, untranslated name for accessibility identifiers.
  var identifier: String {
	switch self {
	  case .ask: "ask"
	  case .minutes: "minutes"
	  case .activity: "activity"
	  case .profile, .settings, .help: tab.identifier
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

  /// Instant Teacher's menu, in order.
  var studentMenuItems: [StudentMenuItem] {
	StudentMenuItem.allCases
  }

  /// The tabs along the bottom of every student section but Home: the menu,
  /// less Help & Support.
  var studentTabItems: [StudentMenuItem] {
	[.ask, .minutes, .activity, .profile, .settings]
  }

  /// The tab for the section on screen, or nil for Help & Support, which has
  /// none.
  var selectedStudentTab: StudentMenuItem? {
	studentTabItems.first { isSelected($0) }
  }

  /// Set by the menu's Minutes, for Home to open the purchase screen; Home
  /// clears it as it does.
  var isPurchaseScreenRequested = false

  /// A student who has not made an account yet, and so has no email or phone
  /// to show in the menu, but may have one to log in to.
  var isAnonymousAccount: Bool {
	Auth.auth().currentUser?.isAnonymous == true
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

  /// Whether `item` is the row for the section on screen. Minutes never is:
  /// the purchase screen it opens is part of Home, which Ask stands for.
  func isSelected(_ item: StudentMenuItem) -> Bool {
	item != .minutes && item.tab == selectedTab
  }

  /// A row was picked from Instant Teacher's menu.
  func select(_ item: StudentMenuItem) {
	select(item.tab)
	isPurchaseScreenRequested = item == .minutes
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
