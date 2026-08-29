//
//  MainTab.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation

enum MainTab: Hashable, CaseIterable {
  case home
  case lessons
  case earnings
  case profile
  case settings
  
  var title: String {
	switch self {
	  case .home: LocalizationSupport.localized("Home")
	  case .lessons: LocalizationSupport.localized("Lessons")
	  case .earnings: LocalizationSupport.localized("Earnings")
	  case .profile: LocalizationSupport.localized("Profile")
	  case .settings: LocalizationSupport.localized("Settings")
	}
  }
  
  var systemImage: String {
	switch self {
	  case .home: "house"
	  case .lessons: "teaching_tab_icon"
	  case .earnings: "dollarsign.circle"
	  case .profile: "person"
	  case .settings: "gearshape"
	}
  }
  
  var selectedSystemImage: String {
	switch self {
	  case .home: "house.fill"
	  case .lessons: "teaching_tab_icon.fill"
	  case .earnings: "dollarsign.circle.fill"
	  case .profile: "person.fill"
	  case .settings: "gearshape.fill"
	}
  }
  
  func systemImage(isSelected: Bool) -> String {
	isSelected ? selectedSystemImage : systemImage
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
final class MainTabViewModel {
  var selectedTab: MainTab = .home
  var userMode: AppUserMode

  private(set) var lessonCount = 0
  private(set) var hasUnseenLessons = false

  var shouldShowLessonsBadge: Bool {
	userMode == .teacher && hasUnseenLessons
  }

  /// The tabs to show, in order. Earnings is teacher-only.
  ///
  /// The view builds its tab bar from this list rather than wrapping a tab in
  /// an `if`: on iOS a false branch inside `TabView` omits the tab, but under
  /// SkipUI it still contributes an empty slot, which showed up on Android as
  /// a blank tab between Lessons and Profile.
  var visibleTabs: [MainTab] {
	if userMode == .teacher {
	  return [.home, .lessons, .earnings, .profile, .settings]
	}
	return [.home, .lessons, .profile, .settings]
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
}
