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

#if os(iOS)
import GoogleSignInSwift
#endif

@MainActor
final class AuthService {
  
  var user: User?
  
  var currentUserID: String? {
    Auth.auth().currentUser?.uid
  }
  
  func signIn(email: String, password: String)  async throws -> Bool{
    let result = try await Auth.auth().signIn(withEmail: email, password: password)
    print("got result: \(result)")
    return true
  }
  
  
//  func signInWithGoogle()  async throws -> Bool{
//    // Get the client ID from your Firebase configuration.
//    guard let clientID = FirebaseApp.app()?.options.clientID else {
//        // Handle error: clientID not found
//        print("Error: Google Client ID not found in FirebaseApp.options.")
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
//            print("Google Sign-In error: \(error?.localizedDescription ?? "Unknown error")")
//            return false
//        }
//
//        guard let user = result?.user,
//              let idToken = user.idToken?.tokenString,
//              let accessToken = user.accessToken.tokenString
//        else {
//            // Handle missing user, ID token, or access token
//            print("Error: Missing Google user, ID token, or access token.")
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
//                print("Firebase Authentication error: \(firebaseAuthError?.localizedDescription ?? "Unknown error")")
//                return false
//            }
//
//            // User is successfully signed in to Firebase with Google!
//            print("Successfully signed in to Firebase with Google! User: \(firebaseAuthResult?.user.uid ?? "N/A")")
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
      print("got result: \(result)")
    return true
    }
  
  func signOut() throws {
    try Auth.auth().signOut()
  }
  
  func deleteCurrentUser() async throws {
    guard let user = Auth.auth().currentUser else {
      throw SettingsError.missingUser
    }
    try await user.delete()
  }
}
