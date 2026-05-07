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
    let title: String
    let systemImage: String
}