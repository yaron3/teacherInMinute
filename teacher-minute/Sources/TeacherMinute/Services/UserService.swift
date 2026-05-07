//
//  UserService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

@MainActor
final class UserService {
    static let shared = UserService()
    private init() {}

    func saveProfile(_ profile: UserProfile) async throws {
        let db = Firestore.firestore()
        try await db.collection("users")
            .document(profile.uid)
            .setData(profile.firestoreData)
        logger.info("Saved profile for uid: \(profile.uid)")
    }
}
