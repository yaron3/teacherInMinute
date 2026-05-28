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
  
  func signOut() throws {
    logger.info("[Auth] signOut requested")
    try Auth.auth().signOut()
  }
  
  func deleteCurrentUser() async throws {
    guard let user = Auth.auth().currentUser else {
      throw SettingsError.missingUser
    }
    try await user.delete()
  }
}

