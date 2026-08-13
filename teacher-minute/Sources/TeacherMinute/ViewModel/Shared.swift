//
//  AuthRole.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import Foundation

enum AuthRole: String, CaseIterable, Identifiable {
    case student
    case teacher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: "Student"
        case .teacher: "Teacher"
        }
    }
}

struct SubjectOption: Identifiable, Hashable {
    let id = UUID()
    let key: String      // English, e.g. "Algebra" — used for Firestore storage and RTDB key derivation
    let title: String    // Localized for display
    let systemImage: String

    init(title: String, systemImage: String, key: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        // If no explicit key is given, derive from the raw title (works when title is already English,
        // e.g. subtopics loaded from remote config). Fallback subjects must always pass an explicit key
        // since their title is a localized string.
        self.key = key ?? title.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}