//
//  AuthProvider.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

#if canImport(UIKit)
import FirebaseAuth

typealias FirebaseSignInResult = Result<AuthDataResult, Error>

@MainActor
protocol AuthProvider {
    func signIn(completion: @escaping (FirebaseSignInResult) -> Void)
}

/// Signs in with a provider's credential. A student who started anonymously
/// has it linked to that account instead, so a new Google or Apple account
/// keeps the anonymous uid and everything on it. If the credential already
/// belongs to an account, they are signed in to that one, and the caller
/// deletes the anonymous account (`AuthService.finishReplacingAnonymousSession`).
func signInLinkingAnonymousAccount(
    with credential: AuthCredential,
    completion: @escaping (AuthDataResult?, Error?) -> Void
) {
    guard let anonymousUser = Auth.auth().currentUser, anonymousUser.isAnonymous else {
        Auth.auth().signIn(with: credential, completion: completion)
        return
    }
    anonymousUser.link(with: credential) { result, error in
        // credentialAlreadyInUse, emailAlreadyInUse, accountExistsWithDifferentCredential
        guard let error = error as NSError?, [17025, 17007, 17012].contains(error.code) else {
            completion(result, error)
            return
        }
        // An Apple credential's nonce is spent by the failed link; Firebase
        // hands back a fresh credential to sign in with.
        let existingAccountCredential =
            error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
        Auth.auth().signIn(with: existingAccountCredential, completion: completion)
    }
}

protocol GoogleSignInProvider: AuthProvider {}
protocol AppleSignInProvider: AuthProvider {}
#endif
