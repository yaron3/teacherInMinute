//
//  UserProfile.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import Foundation

struct UserProfile: Codable {
    let uid: String
    let email: String
    let fullName: String
    let phoneNumber: String
    let dateOfBirth: Date
    let grade: String
    let role: String   // "student" | "teacher"
    let createdAt: Date

    var firestoreData: [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "uid":         uid,
            "email":       email,
            "fullName":    fullName,
            "phoneNumber": phoneNumber,
            "dateOfBirth": iso.string(from: dateOfBirth),
            "grade":       grade,
            "role":        role,
            "createdAt":   iso.string(from: createdAt),
        ]
    }
}
