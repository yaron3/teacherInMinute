//
//  AppRoute.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//


import SwiftUI

enum AppRoute: Hashable {
  case createAccount
  case login
  case chooseRole
  case teacherIdentityVerification
  case teacherSubjects
  case completeProfile(role: AuthRole)
  case mainTabs(role: AuthRole)
  case studentHome
  case teacherDashboard
  
  static func resumeDestination(for resume: OnboardingResume) -> AppRoute {
	 switch resume {
	   case .chooseRole:
		 return .chooseRole
	   case .teacherIdentityVerification:
		 return .teacherIdentityVerification
	   case .teacherSubjects:
		 return .teacherSubjects
	   case .completeProfile(let role):
		 return .completeProfile(role: role)
	   case .home(let role):
		 return .mainTabs(role: role)
	 }
  }
}

@Observable
final class AppRouter: @unchecked Sendable {
  var path: [AppRoute] = []
  
  func push(_ route: AppRoute) {
	path.append(route)
  }
  
  func pop() {
	guard !path.isEmpty else { return }
	path.removeLast()
  }
  
  func popToRoot() {
	path.removeAll()
  }
  
  func replace(with route: AppRoute) {
	path = [route]
  }
}

// MARK: - Environment key so any child view can access the router
private struct AppRouterKey: EnvironmentKey {
  static let defaultValue = AppRouter()
}

extension EnvironmentValues {
  var appRouter: AppRouter {
	get { self[AppRouterKey.self] }
	set { self[AppRouterKey.self] = newValue }
  }
}
