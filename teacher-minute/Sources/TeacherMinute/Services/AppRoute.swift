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
  case studentHome
  case teacherDashboard
}

enum RootScreen: Hashable {
  case welcome
  case mainTabs(role: AuthRole)
}

@Observable
final class AppRouter: @unchecked Sendable {
  var rootScreen: RootScreen = .welcome
  var path = NavigationPath()

  func push(_ route: AppRoute) {
	path.append(route)
  }

  func pop() {
	guard !path.isEmpty else { return }
	path.removeLast()
  }

  func popToRoot() {
	let count = path.count
	logger.info("[Router] popToRoot, count=\(count)")
	path = NavigationPath()
  }

  func replace(with route: AppRoute) {
	path = NavigationPath()
	path.append(route)
  }

  func enterMainTabs(role: AuthRole) {
	path = NavigationPath()
	rootScreen = .mainTabs(role: role)
  }

  func signOut() {
	path = NavigationPath()
	rootScreen = .welcome
  }

  func resume(_ resume: OnboardingResume) {
	switch resume {
	case .chooseRole:
	  replace(with: .chooseRole)
	case .teacherIdentityVerification:
	  replace(with: .teacherIdentityVerification)
	case .teacherSubjects:
	  replace(with: .teacherSubjects)
	case .completeProfile(let role):
	  replace(with: .completeProfile(role: role))
	case .home(let role):
	  enterMainTabs(role: role)
	}
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
