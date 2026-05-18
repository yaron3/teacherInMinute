import Foundation
import SkipFuse
import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#else
import SkipFirebaseCore
#endif


/// A logger for the TeacherMinute module.
let logger: Logger = Logger(subsystem: "com.yaronj.tim", category: "TeacherMinute")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct TeacherMinuteRootView : View {
  @State  var router = AppRouter()
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  
  /* SKIP @bridge */public init() {
    TeacherMinuteAppDelegate.shared.onInit()
  }
  
      public var body: some View {
		@Bindable var router = router
		NavigationStack(path: $router.path) {
		  WelcomeView()
		.navigationDestination(for: AppRoute.self) { route in
		  switch route {
			case .createAccount:
			  CreateAccountView()
			case .login:
			  LoginView()
			case .chooseRole:
			  ChooseRoleView()
			case .teacherIdentityVerification:
			  TeacherIdentityVerificationView()
			case .teacherSubjects:
			  TeacherSubjectsView()
			case .completeProfile(let role):
			  CompleteProfileView(viewModel: CompleteProfileViewModel(role: role))
			case .mainTabs(let role):
			  MainTabView(userMode: AppUserMode(role: role))
			case .studentHome:
			  StudentHomeView()
			case .teacherDashboard:
			  TeacherDashboardView()
		  }
		}
			}
				.environment(\.appRouter, router)
            .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
            .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
            .id(languagePreference)
            .onAppear {
              LocalizationSupport.applyPlatformLayoutDirection(languagePreference: languagePreference)
            }
            .onChange(of: languagePreference) { _, newValue in
              LocalizationSupport.applyPlatformLayoutDirection(languagePreference: newValue)
            }
            .onOpenURL { url in
              PaymentReturnStore.shared.handle(url: url)
            }
				.task {
		  logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
		}
  }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class TeacherMinuteAppDelegate : Sendable {
  /* SKIP @bridge */public static let shared = TeacherMinuteAppDelegate()
  
  private init() {
  }
  /* SKIP @bridge */public func onInit() {
		logger.debug("onInit")
		if FirebaseApp.app() == nil {
		  FirebaseApp.configure()
		  logger.info("Firebase configured")
		}
	  }
  
  /* SKIP @bridge */public func onLaunch() {
	logger.debug("onLaunch")
  }
  
  /* SKIP @bridge */public func onResume() {
	logger.debug("onResume")
  }
  
  /* SKIP @bridge */public func onPause() {
	logger.debug("onPause")
  }
  
  /* SKIP @bridge */public func onStop() {
	logger.debug("onStop")
  }
  
  /* SKIP @bridge */public func onDestroy() {
	logger.debug("onDestroy")
  }
  
  /* SKIP @bridge */public func onLowMemory() {
	logger.debug("onLowMemory")
  }
}
