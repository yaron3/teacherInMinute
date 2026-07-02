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
  case profile
  case settings
  
  var title: String {
	switch self {
	  case .home: LocalizationSupport.localized("Home")
	  case .lessons: LocalizationSupport.localized("Lessons")
	  case .profile: LocalizationSupport.localized("Profile")
	  case .settings: LocalizationSupport.localized("Settings")
	}
  }
  
  var systemImage: String {
	switch self {
	  case .home: "house.fill"
	  case .lessons: "teaching_tab_icon"
	  case .profile: "person.fill"
	  case .settings: "gearshape.fill"
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
final class MainTabViewModel {
  var selectedTab: MainTab = .home
  var userMode: AppUserMode

  private(set) var lessonCount = 0
  private(set) var hasUnseenLessons = false

  var shouldShowLessonsBadge: Bool {
	userMode == .teacher && hasUnseenLessons
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
