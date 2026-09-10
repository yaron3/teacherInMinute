//
//  AuthService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//


import Foundation

//#if os(Android)
//#define SKIP
//#endif

#if !os(Android)
import FirebaseCore
import FirebaseAuth
#else
import SkipFirebaseCore
import SkipFirebaseAuth
#endif

@MainActor
final class AuthService {
  
  var user: User? = Auth.auth().currentUser
#if canImport(FirebaseAuth)
  private var handle: AuthStateDidChangeListenerHandle?
#else
  // On platforms without FirebaseAuth (e.g., Android via Skip), the listener handle type isn't available.
  // We omit the handle entirely.
#endif
  
  init() {
#if canImport(FirebaseAuth)
    handle = Auth.auth().addStateDidChangeListener { auth, user in
      if let user = user {
        logger.info("[AuthState] User signed in: \(user.uid), email: \(user.email ?? "No Email")")
      } else {
        logger.info("[AuthState] User signed out.")
      }
    }
#else
    // No-op on platforms without FirebaseAuth
#endif
  }
  
  @MainActor
  deinit {
#if canImport(FirebaseAuth)
    if let handle = handle {
      Auth.auth().removeStateDidChangeListener(handle)
    }
#else
    // No-op
#endif
  }
  var currentUserID: String? {
    Auth.auth().currentUser?.uid
  }

  var currentUserEmail: String? {
    Auth.auth().currentUser?.email
  }
  
  func signIn(email: String, password: String)  async throws -> Bool{
    let result = try await Auth.auth().signIn(withEmail: email, password: password)
    logger.info("got result: \(result)")
    return true
  }

  func sendPasswordReset(email: String) async throws {
    try await Auth.auth().sendPasswordReset(withEmail: email)
  }
  
  
//  func signInWithGoogle()  async throws -> Bool{
//    // Get the client ID from your Firebase configuration.
//    guard let clientID = FirebaseApp.app()?.options.clientID else {
//        // Handle error: clientID not found
//        logger.info("Error: Google Client ID not found in FirebaseApp.options.")
//        return false
//    }
//#if os(iOS)
//    // Create Google Sign In configuration object.
//    let config = GIDConfiguration(clientID: clientID)
//    GIDSignIn.sharedInstance.configuration = config
//
//    // Start the sign-in flow!
//    // 'self' here refers to the presenting view controller.
//    GIDSignIn.sharedInstance.signIn(withPresenting: self) { [unowned self] result, error in
//        guard error == nil else {
//            // Handle the error if Google Sign-In fails (e.g., user cancels)
//            logger.info("Google Sign-In error: \(error?.localizedDescription ?? "Unknown error")")
//            return false
//        }
//
//        guard let user = result?.user,
//              let idToken = user.idToken?.tokenString,
//              let accessToken = user.accessToken.tokenString
//        else {
//            // Handle missing user, ID token, or access token
//            logger.info("Error: Missing Google user, ID token, or access token.")
//            return false
//        }
//
//        // Now you have the Google ID Token and Access Token.
//        // Use them to create a Firebase credential.
//        let firebaseCredential = GoogleAuthProvider.credential(withIDToken: idToken,
//                                                             accessToken: accessToken)
//
//        // Sign in to Firebase with the Google credential.
//        Auth.auth().signIn(with: firebaseCredential) { firebaseAuthResult, firebaseAuthError in
//            guard firebaseAuthError == nil else {
//                // Handle Firebase Authentication error
//                logger.info("Firebase Authentication error: \(firebaseAuthError?.localizedDescription ?? "Unknown error")")
//                return false
//            }
//
//            // User is successfully signed in to Firebase with Google!
//            logger.info("Successfully signed in to Firebase with Google! User: \(firebaseAuthResult?.user.uid ?? "N/A")")
//          return true
//            // Proceed with your app's logic, e.g., navigate to your main content.
//        }
//    }
//
//    
//#endif
//    return true
//    
//  }
  
  
  func createUser(email: String, password: String) async throws -> Bool{
      let result = try await Auth.auth().createUser(withEmail: email, password: password)
      logger.info("got result: \(result)")
    return true
    }
  
  /// Clears teacher presence before dropping the auth session.
  ///
  /// `onDisconnect` is registered on both platforms and covers a killed app or
  /// a lost network, but it only fires when the RTDB socket actually closes.
  /// Signing out leaves the process — and the socket — alive, so the dead man's
  /// switch never ran and `teachers/{uid}/status` stayed "online" for as long
  /// as the account was signed out. The public `onlineTeachers` projection is
  /// rebuilt from that status (functions/src/presence.ts), so students kept
  /// seeing a signed-out teacher and dispatch kept inviting them.
  ///
  /// The write has to happen first: afterwards `currentUser` is nil and the
  /// presence writer has no uid to write for.
  func signOut() throws {
    logger.info("[Auth] signOut requested")
    clearPresenceBeforeSignOut()
    try Auth.auth().signOut()
  }

  /// Written for every account, not just teachers. A student has no
  /// `teachers/{uid}` record and the write simply creates a dormant offline
  /// one, which is cheaper than threading the current role down to here and
  /// leaves no way for a role misread to strand a teacher online.
  private func clearPresenceBeforeSignOut() {
    guard Auth.auth().currentUser != nil else { return }
#if os(Android)
    AndroidTeacherPresenceWriter.setCurrentTeacherStatus("offline")
#else
    guard let uid = Auth.auth().currentUser?.uid else { return }
    TeacherPresenceService(teacherUID: uid).goOffline()
#endif
    logger.info("[Auth] cleared teacher presence ahead of sign out")
  }
  
  func deleteCurrentUser() async throws {
    guard let user = Auth.auth().currentUser else {
      throw SettingsError.missingUser
    }
    try await user.delete()
  }

  /// The sign-in provider backing the current user (e.g. "password", "google.com", "apple.com").
  var currentUserProviderID: String? {
#if os(Android)
    Auth.auth().currentUser?.providerID
#else
    Auth.auth().currentUser?.providerData.first?.providerID
#endif
  }

  /// True when the current user signed in with email/password and therefore must
  /// supply their password to re-authenticate before a sensitive action.
  var requiresPasswordForReauth: Bool {
    currentUserProviderID == "password"
  }

  /// Whether the given error is Firebase's "requires recent login" error, which is
  /// raised for sensitive actions (like account deletion) when the session is stale.
  func isRecentLoginRequired(_ error: Error) -> Bool {
    // AuthErrorCode.requiresRecentLogin == 17014
    (error as NSError).code == 17014
  }

  /// Re-authenticates the current user so sensitive actions are allowed again after
  /// the session has gone stale. For social providers this re-runs the sign-in flow;
  /// for email/password it uses the supplied password.
  func reauthenticate(password: String? = nil) async throws {
    guard let user = Auth.auth().currentUser else {
      throw SettingsError.missingUser
    }

    switch currentUserProviderID {
    case "password":
      guard let email = user.email, let password, !password.isEmpty else {
        throw AuthReauthError.passwordRequired
      }
      let credential = EmailAuthProvider.credential(withEmail: email, password: password)
      try await user.reauthenticate(with: credential)
    case "google.com":
      try await reauthenticateWithSocialProvider(.google)
    case "apple.com":
      try await reauthenticateWithSocialProvider(.apple)
    default:
      throw AuthReauthError.unsupportedProvider
    }
  }

  private enum SocialReauthProvider {
    case google
    case apple
  }

  private func reauthenticateWithSocialProvider(_ provider: SocialReauthProvider) async throws {
#if os(iOS)
    let signInProvider: AuthProvider = provider == .google
      ? iOSGoogleSignInProvider()
      : iOSAppleSignInProvider()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      signInProvider.signIn { result in
        switch result {
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
#elseif os(Android)
    switch provider {
    case .google: _ = try await AndroidGoogleAuth().signIn()
    case .apple: _ = try await AndroidAppleAuth().signIn()
    }
#endif
  }
}

#if os(Android)
/// Recovers a user-visible reason from an Android Firebase Auth failure.
///
/// The numeric codes below exist only on iOS. Android's SDK reports failures
/// as Kotlin exceptions and skip-firebase forwards them untouched for the
/// email/password calls, so by the time one reaches Swift it is a
/// `SwiftJNI.ThrowableError` whose `NSError` code is always 1 — which is why
/// every Android auth failure used to fall through to the generic message.
///
/// What does survive is the throwable's `toString()`, which leads with the
/// exception's fully-qualified class name:
///
///     com.google.firebase.auth.FirebaseAuthUserCollisionException: The email
///     address is already in use by another account.
///
/// The class name is what gets matched. The sentence after it is English text
/// straight from the SDK and is free to change between releases.
private func androidAuthErrorMessage(_ error: Error) -> String? {
    let throwable = String(describing: error)
    func raised(_ exceptionName: String) -> Bool {
        throwable.contains("com.google.firebase.auth.\(exceptionName)")
            || throwable.contains("com.google.firebase.\(exceptionName)")
    }

    // A weak password arrives as a subclass of the invalid-credentials
    // exception, so it has to be recognised before its parent.
    if raised("FirebaseAuthWeakPasswordException") {
        return LocalizationSupport.localized("Password must be at least 6 characters.")
    }
    // Covers both a taken address on sign-up and an account that already
    // exists under a different provider; Firebase does not separate them here.
    if raised("FirebaseAuthUserCollisionException") {
        return LocalizationSupport.localized("This email address is already in use.")
    }
    // Android folds a malformed address and a wrong password into one
    // exception, so this says what is true of both.
    if raised("FirebaseAuthInvalidCredentialsException") || raised("FirebaseAuthInvalidUserException") {
        return LocalizationSupport.localized("Incorrect email or password.")
    }
    if raised("FirebaseTooManyRequestsException") {
        return LocalizationSupport.localized("Too many failed attempts. Please try again later.")
    }
    if raised("FirebaseNetworkException") {
        return LocalizationSupport.localized("A network error occurred. Please try again.")
    }
    return nil
}
#endif

/// Maps a Firebase Auth error code to a localized, user-visible message.
/// Firebase's `localizedDescription` always returns English strings from the SDK;
/// this function translates the numeric code into a key that LocalizationSupport can look up.
func localizedAuthErrorMessage(_ error: Error) -> String {
#if os(Android)
    if let message = androidAuthErrorMessage(error) {
        return message
    }
#endif
    switch (error as NSError).code {
    case 17007: return LocalizationSupport.localized("This email address is already in use.")
    case 17008: return LocalizationSupport.localized("Please enter a valid email address.")
    case 17009, 17011: return LocalizationSupport.localized("Incorrect email or password.")
    case 17010: return LocalizationSupport.localized("Too many failed attempts. Please try again later.")
    case 17020: return LocalizationSupport.localized("A network error occurred. Please try again.")
    default:    return LocalizationSupport.localized("An unexpected error occurred. Please try again.")
    }
}

enum AuthReauthError: LocalizedError {
  /// The user signed in with email/password and must supply it to re-authenticate.
  case passwordRequired
  /// The user's sign-in provider does not support in-app re-authentication.
  case unsupportedProvider

  var errorDescription: String? {
    switch self {
    case .passwordRequired:
      return LocalizationSupport.localized("Enter your password to confirm account deletion.")
    case .unsupportedProvider:
      return LocalizationSupport.localized("Please sign out and sign in again before deleting your account.")
    }
  }
}

