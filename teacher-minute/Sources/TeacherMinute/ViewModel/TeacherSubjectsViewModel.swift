//
//  TeacherSubjectsViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class TeacherSubjectsViewModel {
    var searchText = ""
    var selectedSubjects: Set<SubjectOption> = []

    var onContinue: (() -> Void)?

    let popularSubjects: [SubjectOption] = [
        SubjectOption(title: "General Math",  systemImage: "function"),
        SubjectOption(title: "Algebra",       systemImage: "x.squareroot"),
        SubjectOption(title: "Geometry",      systemImage: "triangle"),
        SubjectOption(title: "Calculus",      systemImage: "chart.xyaxis.line"),
        SubjectOption(title: "Statistics",    systemImage: "chart.pie"),
        SubjectOption(title: "Trigonometry",  systemImage: "angle"),
        SubjectOption(title: "Physics Math",  systemImage: "waveform.path.ecg"),
    ]

    let advancedSubjects: [SubjectOption] = [
        SubjectOption(title: "Linear Algebra", systemImage: "square.grid.3x3"),
        SubjectOption(title: "Discrete Math",  systemImage: "point.3.connected.trianglepath.dotted"),
        SubjectOption(title: "Number Theory",  systemImage: "number"),
    ]

    var canContinue: Bool { !selectedSubjects.isEmpty }

    var selectedCountText: String {
        selectedSubjects.isEmpty ? "None selected" : "\(selectedSubjects.count) selected"
    }

    func toggle(_ subject: SubjectOption) {
        if selectedSubjects.contains(subject) {
            selectedSubjects.remove(subject)
        } else {
            selectedSubjects.insert(subject)
        }
    }

    func continueOnboarding() {
        guard canContinue else { return }
        onContinue?()
    }

    func skip() {
        onContinue?()
    }
}
