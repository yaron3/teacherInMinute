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
  
  var hasTeacherRequestBadge = true
  
  var shouldShowLessonsBadge: Bool {
	userMode == .teacher && hasTeacherRequestBadge
  }
  
  init(userMode: AppUserMode = .teacher) {
	self.userMode = userMode
  }
}
