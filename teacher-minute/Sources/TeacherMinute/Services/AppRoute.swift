//
//  AppRoute.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//


import SwiftUI
import SkipFuse
#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

enum AppRoute: Hashable {
  case createAccount
  case login
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
  private var authListenerHandle: Any?

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
	path = NavigationPath()
	rootScreen = .mainTabs(role: role)
  }

  func signOut() {
	path = NavigationPath()
	rootScreen = .welcome
  }

  /// Returns to sign-in whenever Firebase has no user while the tab bar is up.
  ///
  /// Log Out and Delete Account route there themselves. This is for a session
  /// that ends without them — revoked, or its account deleted or disabled
  /// elsewhere — which used to leave the signed-in screens running with nobody
  /// behind them, every read they made refused.
  ///
  /// Registers once, however often it is called.
  func followAuthState() {
	guard authListenerHandle == nil else { return }
	authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
	  guard user == nil else { return }
	  Task { @MainActor [weak self] in
		guard let self, case .mainTabs = self.rootScreen else { return }
		logger.info("[Router] no signed-in user behind the tab bar; returning to sign-in")
		self.signOut()
	  }
	}
  }

  func resume(_ resume: OnboardingResume) {
	switch resume {
	case .teacherIdentityVerification:
	  replace(with: .teacherIdentityVerification)
	case .teacherSubjects:
	  replace(with: .teacherSubjects)
	case .completeProfile(let role):
	  replace(with: .completeProfile(role: role))
	case .home(let role):
	  enterMainTabs(role: role)
	case .otherApp:
	  // Nothing in this app is for that account. Whoever resolved this has
	  // already signed it out (`UserService.signOutOtherAppAccount`) and said
	  // which app it belongs to, so all that is left is the sign-in screen.
	  signOut()
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
