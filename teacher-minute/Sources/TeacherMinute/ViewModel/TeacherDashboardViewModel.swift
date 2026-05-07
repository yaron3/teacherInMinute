//
//  TeacherDashboardViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI
import Observation
import Foundation

struct LiveStudentRequest: Identifiable {
    let id = UUID()
    let studentName: String
    let topic: String
    let waitingTime: String
    let isHighPriority: Bool
}

@Observable
final class TeacherDashboardViewModel {
    var teacherName = "Mr. Davis"
    var isOnline = false

    let liveRequests = [
        LiveStudentRequest(
            studentName: "Sarah M.",
            topic: "Calculus • Derivatives",
            waitingTime: "Waiting 2m",
            isHighPriority: true
        ),
        LiveStudentRequest(
            studentName: "Jason K.",
            topic: "Algebra II • Quadratics",
            waitingTime: "Waiting 1m",
            isHighPriority: false
        )
    ]

    var liveEarningsToday: String {
        isOnline ? "$14.50" : "$0.00"
    }

    func toggleOnline() {
        isOnline.toggle()
    }

    func accept(_ request: LiveStudentRequest) {
        // TODO: accept request
    }

    func reject(_ request: LiveStudentRequest) {
        // TODO: reject request
    }

    func editSubjects() {
        // TODO: navigate to subject edit screen
    }
}
