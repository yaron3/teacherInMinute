//
//  PayoutMethodPreferenceStore.swift
//  teacher-minute
//
// Where a teacher said they would like to be paid, picked during profile
// completion before they had any details to type. Local only, and deliberately
// so: it is a preference, not account data. The account's real payout method is
// whatever `updateTeacherPayoutMethod` has stored (see TeacherPayoutMethod);
// this only decides which tab the payout form opens on until one exists.

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@MainActor
enum PayoutMethodPreferenceStore {
    private static let keyPrefix = "preferredPayoutMethodType"

    /// The type chosen at onboarding — `nil` when the teacher skipped the
    /// question, or picked a type this build no longer offers.
    static func preferredTypeForCurrentUser() -> PayoutMethodType? {
        guard let uid = Auth.auth().currentUser?.uid,
              let raw = UserDefaults.standard.string(forKey: key(for: uid))
        else { return nil }
        return PayoutMethodType(rawValue: raw)
    }

    /// `nil` clears the stored choice, so "none of these right now" is recorded
    /// as the answer rather than leaving an earlier pick behind.
    static func setPreferredTypeForCurrentUser(_ type: PayoutMethodType?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let type {
            UserDefaults.standard.set(type.rawValue, forKey: key(for: uid))
        } else {
            UserDefaults.standard.removeObject(forKey: key(for: uid))
        }
    }

    private static func key(for uid: String) -> String {
        "\(keyPrefix).\(uid)"
    }
}
