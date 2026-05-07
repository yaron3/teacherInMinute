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
