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

protocol GoogleSignInProvider: AuthProvider {}
protocol AppleSignInProvider: AuthProvider {}
#endif
