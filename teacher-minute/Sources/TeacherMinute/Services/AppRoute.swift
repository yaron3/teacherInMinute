//
//  AppRoute.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//


import SwiftUI
import SkipFuse

enum AppRoute: Hashable {
  case createAccount
  case login
  case chooseRole
  case teacherIdentityVerification
  case teacherSubjects
  case completeProfile(role: AuthRole)
  case permissionsSetup(role: AuthRole)
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

  /// Swaps the whole app root over to the tab bar.
  ///
  /// Called from two places that do not look alike to the navigator: at launch,
  /// where the path is empty (`performLaunchSessionResume` even guards on it),
  /// and after a login, where the path still holds the pushed `.login` route
  /// that the welcome stack is displaying. The second case is why the root view
  /// gives the root screen its own identity — clearing a bound, non-empty path
  /// in the same breath as swapping the stack out from under it left the login
  /// screen on top of the new root on Android.
  func enterMainTabs(role: AuthRole) {
	//logger.info("[Router] enterMainTabs role=\(role) pathCount=\(path.count)")
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
