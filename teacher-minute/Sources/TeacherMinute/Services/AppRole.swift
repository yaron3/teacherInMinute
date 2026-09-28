//
//  AppRole.swift
//  teacher-minute
//
//  Which of the two apps this build is.
//

import Foundation
#if os(Android)
import SkipBridge
#endif

extension AuthRole {
  /// The role this app is built for: `.student` in Instant Teacher, `.teacher`
  /// in Pro Teacher.
  ///
  /// Both apps are built from these same sources, so the build says which one
  /// it is. On iOS each app target sets `TIM_APP_ROLE`, which Info.plist
  /// carries as `TIMAppRole`; on Android each product flavor sets
  /// `BuildConfig.APP_ROLE`, read over JNI below.
  ///
  /// Nobody picks a role at sign-up any more. A new account starts the
  /// onboarding for this role, and an account of the other role is pointed to
  /// the other app (see `UserService.resumeRoute` and `WelcomeViewModel`).
  static let appRole: AuthRole = {
    let setting = appRoleSetting()
    guard let role = AuthRole(rawValue: setting) else {
      logger.error("[AppRole] the build names no app role (got '\(setting)'); running as the student app")
      return .student
    }
    logger.info("[AppRole] running as the \(setting) app")
    return role
  }()

  /// The name of the app built for this role, as it appears under its icon.
  /// Not translated: it is the app's name in both stores and on the home
  /// screen, whatever the language.
  var appName: String {
    switch self {
    case .student: "Instant Teacher"
    case .teacher: "Pro Teacher"
    }
  }
}

private func appRoleSetting() -> String {
  #if os(Android)
  return AndroidAppRoleBridge.appRole()
  #else
  return Bundle.main.object(forInfoDictionaryKey: "TIMAppRole") as? String ?? ""
  #endif
}

#if os(Android)
private enum AndroidAppRoleBridge {
  private static let providerClass = try! JClass(name: "teacher/minute/AndroidAppRole")
  private static let appRoleMethod = providerClass.getStaticMethodID(
    name: "appRole",
    sig: "()Ljava/lang/String;"
  )!

  static func appRole() -> String {
    do {
      return try jniContext {
        try providerClass.callStatic(
          method: appRoleMethod,
          options: [.kotlincompat],
          args: []
        )
      }
    } catch {
      logger.error("[AppRole][Android] failed to read the app role: \(error)")
      return ""
    }
  }
}
#endif
