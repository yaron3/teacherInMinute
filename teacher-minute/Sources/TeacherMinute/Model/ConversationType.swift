//
//  ConversationType.swift
//  teacher-minute
//
//  Wire format for the student's chosen session medium. Raw strings are kept
//  identical to the values produced by the backend so the same vocabulary
//  flows through Firestore / RTDB invites without translation.
//

import Foundation

enum ConversationType: String, CaseIterable {
    case text
    case audio
    case video

    var requiresMic: Bool { self == .audio || self == .video }
    var requiresCamera: Bool { self == .video }
}
