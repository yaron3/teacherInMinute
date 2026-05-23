//
//  AppleSignIn+iOS.swift
//  teacher-minute
//
//  Created by Codex on 16/05/2026.
//

#if canImport(UIKit)
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import UIKit

@MainActor
final class iOSAppleSignInProvider: NSObject, AppleSignInProvider {
    private static var activeProvider: iOSAppleSignInProvider?

    private var currentNonce: String?
    private var completion: ((FirebaseSignInResult) -> Void)?

    func signIn(completion: @escaping (FirebaseSignInResult) -> Void) {
        self.completion = completion
        Self.activeProvider = self

        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func finish(_ result: FirebaseSignInResult) {
        completion?(result)
        completion = nil
        currentNonce = nil
        Self.activeProvider = nil
    }
}

extension iOSAppleSignInProvider: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AppleSignInError.missingCredentials))
            return
        }

        guard let nonce = currentNonce else {
            finish(.failure(AppleSignInError.missingNonce))
            return
        }

        guard let tokenData = appleIDCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AppleSignInError.missingIdentityToken))
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        // Apple only returns the user's name on the FIRST sign-in for this
        // Apple ID + app. Capture it now so we can persist it on the Firebase
        // user — Firebase doesn't reliably copy the fullName from the
        // credential into `displayName`.
        let appleDisplayName: String = {
            guard let components = appleIDCredential.fullName else { return "" }
            let formatter = PersonNameComponentsFormatter()
            return formatter
                .string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            if let error {
                self?.finish(.failure(error))
                return
            }

            guard let authResult else {
                self?.finish(.failure(AppleSignInError.firebaseAuthFailed))
                return
            }

            let user = authResult.user
            let currentDisplayName = user.displayName ?? ""
            guard !appleDisplayName.isEmpty, currentDisplayName != appleDisplayName else {
                self?.finish(.success(authResult))
                return
            }

            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = appleDisplayName
            changeRequest.commitChanges { _ in
                self?.finish(.success(authResult))
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }
}

extension iOSAppleSignInProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.topMostViewController()?.view.window ?? ASPresentationAnchor()
    }
}

extension iOSAppleSignInProvider {
    enum AppleSignInError: LocalizedError {
        case missingCredentials
        case missingNonce
        case missingIdentityToken
        case firebaseAuthFailed

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Apple Sign-In completed without Apple ID credentials."
            case .missingNonce:
                return "Apple Sign-In could not verify the request nonce."
            case .missingIdentityToken:
                return "Apple Sign-In completed without an identity token."
            case .firebaseAuthFailed:
                return "Firebase Authentication failed after Apple Sign-In."
            }
        }
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }

            randomBytes.forEach { random in
                guard remainingLength > 0 else { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }
}
#endif
