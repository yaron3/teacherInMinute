//
//  FirebaseEmulator.swift
//  teacher-minute
//
//  Debug builds only: launched with `-firebaseEmulatorHost <host>`, the app
//  talks to the local Firebase emulators instead of the live backend.
//
//  Debug builds otherwise use production (staging was never set up), so this
//  is what lets a UI test run a real accept race without sending a question to
//  a real teacher. Start the emulators with
//
//      npm --prefix backend/Firebase/functions run emulators:app
//
//  The app is configured for the emulators' demo project rather than the one
//  in GoogleService-Info.plist:
//
//  - the emulators then refuse to reach any real Firebase service, so nothing a
//    function does while the app is on them can touch production;
//  - the API key is a stand-in too, which gives the emulator session its own
//    keychain entry: a production sign-in on the same simulator survives.
//
//  Analytics and Crashlytics are off for the whole run. Remote Config cannot be
//  emulated, so its fetch fails and the app runs on its in-app defaults.
//
//  iOS only for now; on Android the switch is read but ignored.
//

import Foundation
#if !os(Android)
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase
import FirebaseStorage
import FirebaseAnalytics
import FirebaseCrashlytics
#endif

enum FirebaseEmulator {
  /// The emulators' project. A `demo-` id is one Firebase never resolves.
  static let projectID = "demo-teacher-in-a-moment"
  static let region = "us-central1"

  /// The ports `backend/Firebase/firebase.json` pins.
  static let authPort = 9099
  static let firestorePort = 8085
  static let databasePort = 9000
  static let functionsPort = 5001
  static let storagePort = 9199

  /// Shaped like a real key, since the SDK checks the shape; the Auth emulator
  /// accepts any.
  private static let apiKey = "AIzaSyDemoEmulatorKeyForLocalTestsOnly0"

  /// The emulators' host, from `-firebaseEmulatorHost`. Always nil in a
  /// release build, whatever the launch arguments say.
  static var host: String? {
#if DEBUG
    let value = UserDefaults.standard.string(forKey: "firebaseEmulatorHost")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
#else
    return nil
#endif
  }

  /// Where callables are served, in place of the production
  /// `https://us-central1-….cloudfunctions.net`.
  static var functionsBaseURL: String? {
#if DEBUG && !os(Android)
    guard let host else { return nil }
    return "http://\(host):\(functionsPort)/\(projectID)/\(region)"
#else
    return nil
#endif
  }

  /// Configures Firebase for the emulators when the launch asked for them.
  /// Returns false, having done nothing, otherwise: the caller then configures
  /// Firebase as usual.
  ///
  /// Must run before anything touches Auth, Firestore or the Realtime
  /// Database, since none of them can be redirected after first use.
  @MainActor
  static func configureIfRequested() -> Bool {
#if DEBUG && !os(Android)
    guard let host, let defaults = FirebaseOptions.defaultOptions() else { return false }

    let options = FirebaseOptions(googleAppID: defaults.googleAppID, gcmSenderID: defaults.gcmSenderID)
    options.apiKey = apiKey
    options.projectID = projectID
    options.bundleID = defaults.bundleID
    // The namespace the Functions emulator gives the project's database: for
    // a demo project it is the bare project id, not `<id>-default-rtdb`. Any
    // other name and the app and the backend would each see their own copy.
    options.databaseURL = "https://\(projectID).firebaseio.com"
    options.storageBucket = "\(projectID).appspot.com"
    FirebaseApp.configure(options: options)

    Analytics.setAnalyticsCollectionEnabled(false)
    Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)

    Auth.auth().useEmulator(withHost: host, port: authPort)
    // `-firebaseEmulatorSignOut YES` starts from the welcome screen, so each
    // UI test signs in as its own account whatever the last one left behind.
    if UserDefaults.standard.bool(forKey: "firebaseEmulatorSignOut") {
      do {
        try Auth.auth().signOut()
      } catch {
        logger.info("[Firebase] emulator sign-out at launch failed: \(error.localizedDescription)")
      }
    }

    let settings = Firestore.firestore().settings
    settings.host = "\(host):\(firestorePort)"
    settings.isSSLEnabled = false
    settings.cacheSettings = MemoryCacheSettings()
    Firestore.firestore().settings = settings

    Database.database().useEmulator(withHost: host, port: databasePort)
    // Question photos and profile images: without this an upload would go to
    // the real Storage API, under a bucket name nothing owns.
    Storage.storage().useEmulator(withHost: host, port: storagePort)

    logger.info("[Firebase] using the local emulators at \(host), project \(projectID)")
    return true
#else
    return false
#endif
  }
}
