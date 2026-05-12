//
//  GoogleSignIn+iOS.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

#if canImport(UIKit)
import UIKit
import FirebaseCore
import GoogleSignIn
import FirebaseAuth

// Assuming you have the UIApplication.topMostViewController() extension defined as well.

class iOSGoogleSignInProvider: GoogleSignInProvider {
    func signIn(completion: @escaping (FirebaseSignInResult) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(.failure(GoogleSignInError.configurationMissing("Google Client ID not found.")))
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let presentingViewController = UIApplication.topMostViewController() else {
            completion(.failure(GoogleSignInError.noPresentingViewController))
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString
            else {
                completion(.failure(GoogleSignInError.missingCredentials))
                return
            }
          let accessToken = user.accessToken.tokenString

            let firebaseCredential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Auth.auth().signIn(with: firebaseCredential) { firebaseAuthResult, firebaseAuthError in
                if let firebaseAuthError = firebaseAuthError {
                    completion(.failure(firebaseAuthError))
                    return
                }
                guard let authResult = firebaseAuthResult else {
                    completion(.failure(GoogleSignInError.firebaseAuthFailed("Unknown Firebase Auth result.")))
                    return
                }
                completion(.success(authResult))
            }
        }
    }

    enum GoogleSignInError: LocalizedError {
        case configurationMissing(String)
        case noPresentingViewController
        case missingCredentials
        case firebaseAuthFailed(String)

        var errorDescription: String? {
            switch self {
            case .configurationMissing(let message): return "Google Sign-In configuration error: \(message)"
            case .noPresentingViewController: return "Cannot find a view controller to present Google Sign-In."
            case .missingCredentials: return "Google Sign-In completed, but missing ID token or access token."
            case .firebaseAuthFailed(let message): return "Firebase Authentication failed: \(message)"
            }
        }
    }
}
#endif
