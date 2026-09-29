import Foundation
import SkipFuse
import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#else
import SkipFirebaseCore
#endif
#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif


/// A logger for the TeacherMinute module.
let logger: Logger = Logger(subsystem: "com.yaronj.tim", category: "TeacherMinute")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct TeacherMinuteRootView : View {
  @State  var router = AppRouter()
  @State var isLaunching = true
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  @AppStorage("appearanceMode") var appearanceMode = "system"

  /* SKIP @bridge */public init() {
    TeacherMinuteAppDelegate.shared.onInit()
  }

  var preferredAppearanceColorScheme: ColorScheme? {
    // Instant Teacher is drawn on the brand's dark ground throughout.
    if AppTheme.isBrand { return .dark }
    switch appearanceMode {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
  }
  
      public var body: some View {
			@Bindable var router = router
			ZStack {
			Group {
			  switch router.rootScreen {
				case .mainTabs(let role):
				  MainTabView(userMode: AppUserMode(role: role))
				case .welcome:
				  NavigationStack(path: $router.path) {
					signedOutRoot
					  .navigationDestination(for: AppRoute.self) { route in
						switch route {
						  case .createAccount:
							createAccountScreen
						  case .login:
							loginScreen
						  case .teacherIdentityVerification:
							TeacherIdentityVerificationView()
							  .trackScreen(AnalyticsScreen.teacherIdentity)
						  case .teacherSubjects:
							TeacherSubjectsView()
							  .trackScreen(AnalyticsScreen.teacherSubjects)
						  case .completeProfile(let role):
							completeProfileScreen(role: role)
						  case .permissionsSetup(let role):
							PermissionsSetupView(role: role)
							  .trackScreen(AnalyticsScreen.permissionsSetup)
						  case .studentHome:
							StudentHomeView()
							  .trackScreen(AnalyticsScreen.studentHome)
						  case .teacherDashboard:
							TeacherDashboardView()
							  .trackScreen(AnalyticsScreen.teacherDashboard)
						}
					  }
				  }
			  }
				}

				if isLaunching {
				  LaunchSplashView()
					.transition(.opacity)
				}

#if DEBUG && !os(Android)
				if SessionTypeUITestHarness.isRequested {
				  SessionTypeUITestHarness()
				}
#endif
				}
				// The welcome branch owns a NavigationStack bound to the router's
				// path, and after a login that stack is displaying a pushed
				// `.login` route at the moment the root swaps to the tab bar.
				// Without an identity of its own the old subtree survived the
				// swap on Android and kept the login screen on screen, so a
				// successful sign-in looked like a failed one.
				.id(router.rootScreen)
				.environment(\.appRouter, router)
            .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
            .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
            .preferredColorScheme(preferredAppearanceColorScheme)
            .id("\(languagePreference)-\(appearanceMode)")
            .onAppear {
              LocalizationSupport.applyPlatformLayoutDirection(languagePreference: languagePreference)
            }
            .onChange(of: languagePreference) { _, newValue in
              LocalizationSupport.applyPlatformLayoutDirection(languagePreference: newValue)
            }
            .onOpenURL { url in
              logger.info("[PaymentReturn] root onOpenURL received \(url.absoluteString)")
              PaymentReturnStore.shared.handle(url: url)
            }
					.task {
				  logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
				  let remoteConfigReady = await RemoteConfigService.shared.readyForLaunch()
				  logger.info("[RemoteConfig] launch gate finished ready=\(remoteConfigReady)")
				  await performLaunchSessionResume()
				  withAnimation(.easeOut(duration: 0.25)) {
				isLaunching = false
			  }
			}
  }

  /// The first screen of a signed-out session. A student starts from the intro,
  /// without an account, and logs in to an existing one from the home screen's
  /// menu; a teacher registers or signs in on the welcome screen.
  @ViewBuilder
  var signedOutRoot: some View {
	if AuthRole.appRole == .student {
	  StudentIntroView()
	} else {
	  WelcomeView()
		.trackScreen(AnalyticsScreen.welcome)
	}
  }

  /// Instant Teacher logs its students in on the brand's own screen, as it
  /// signs them up; Pro Teacher keeps the standard one.
  @ViewBuilder
  var loginScreen: some View {
	if AuthRole.appRole == .student {
	  StudentLoginView()
	} else {
	  LoginView()
		.trackScreen(AnalyticsScreen.login)
	}
  }

  /// Instant Teacher signs its students up on the brand's own screens; Pro
  /// Teacher keeps the standard ones. Both run on the same view models.
  @ViewBuilder
  var createAccountScreen: some View {
	if AuthRole.appRole == .student {
	  StudentSignUpView()
	} else {
	  CreateAccountView()
		.trackScreen(AnalyticsScreen.createAccount)
	}
  }

  @ViewBuilder
  func completeProfileScreen(role: AuthRole) -> some View {
	if role == .student {
	  StudentCompleteProfileView(viewModel: CompleteProfileViewModel(role: role))
	} else {
	  CompleteProfileView(viewModel: CompleteProfileViewModel(role: role))
		.trackScreen(AnalyticsScreen.completeProfile)
	}
  }

  private func performLaunchSessionResume() async {
	#if !targetEnvironment(preview)
	// From here on, a session that ends on its own returns the app to sign-in.
	router.followAuthState()
	guard router.path.isEmpty else { return }
	guard let uid = Auth.auth().currentUser?.uid else { return }
	do {
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  if case .otherApp(let role) = resume {
		// Mostly a student whose app has just updated into Pro Teacher, still
		// signed in from before the apps split. Sign-in turns such an account
		// away too, but a session can outlive that check: resolving the route
		// can fail after Firebase has signed in, and a role can change after
		// the fact. Either way it ends here, and the welcome screen says which
		// app the account belongs to.
		UserService.shared.signOutOtherAppAccount(role: role)
		router.resume(resume)
		return
	  }
	  router.resume(resume)
	  logger.info("[Auth] auto-login restored session uid=\(uid)")
	} catch {
	  logger.error("[Auth] auto-login failed: \(error)")
	}
	#endif
  }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class TeacherMinuteAppDelegate : Sendable {
  /* SKIP @bridge */public static let shared = TeacherMinuteAppDelegate()
  
  nonisolated(unsafe) private(set) var isInForeground = true
  
  private init() {
  }
  /* SKIP @bridge */@MainActor public func onInit() {
			logger.debug("onInit")
			if FirebaseApp.app() == nil {
			  FirebaseApp.configure()
			  logger.info("Firebase configured")
			  AnalyticsService.shared.start()
			}
			RemoteConfigService.shared.start()
			PushNotificationService.shared.configureDelegates()
		  }
  
  /* SKIP @bridge */public func onLaunch() {
		logger.debug("onLaunch")
  }
  
  /* SKIP @bridge */public func onResume() {
			logger.debug("onResume")
    isInForeground = true
    Task { @MainActor in
      LocalNotificationService.shared.resetDeliveredCache()
    }
  }
  
  /* SKIP @bridge */public func onPause() {
			logger.debug("onPause")
    isInForeground = false
  }
  
  /* SKIP @bridge */public func onStop() {
			logger.debug("onStop")
    isInForeground = false
  }
  
  /* SKIP @bridge */public func onDestroy() {
		logger.debug("onDestroy")
  }
  
  /* SKIP @bridge */public func onLowMemory() {
		logger.debug("onLowMemory")
  }
}
