//
//  StudentHomeViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

struct PricingOption: Identifiable {
    let id = UUID()
    let name: String
    let price: String
    let description: String
    let isHighlighted: Bool
}

struct RecentLesson: Identifiable {
    let id = UUID()
    let title: String
    let teacher: String
    let time: String
    let duration: String
}

@Observable
@MainActor
final class StudentHomeViewModel {
    var name = "Student"
    var showAskTeacherSheet = false
    var teachingSubjects: [RemoteTeachingSubject] = []
    var selectedField = ""
    var selectedSubfield = ""
    var question = ""
    var isFindingTeachers = false
    var alertTitle = "Ask a Teacher"
    var alertMessage: String?
    var showAlert = false
    
    private let remoteConfigService: SettingsRemoteConfigService
    private let teacherSearchRepository: TeacherSearchRepository
    
    init(
        remoteConfigService: SettingsRemoteConfigService = .shared,
        teacherSearchRepository: TeacherSearchRepository = CloudFunctionTeacherSearchRepository()
    ) {
        self.remoteConfigService = remoteConfigService
        self.teacherSearchRepository = teacherSearchRepository
    }

    let pricingOptions = [
        PricingOption(
            name: "Standard",
            price: "$0.50",
            description: "Verified tutors for algebra, geometry, and basic calculus.",
            isHighlighted: false
        ),
        PricingOption(
            name: "Expert",
            price: "$1.20",
            description: "Advanced degree tutors for college-level help.",
            isHighlighted: true
        )
    ]

    let recentLessons = [
        RecentLesson(
            title: "Calculus Help",
            teacher: "with Mr. Davis",
            time: "Today, 2:30 PM",
            duration: "14 mins"
        ),
        RecentLesson(
            title: "Algebra II",
            teacher: "with Ms. Chen",
            time: "Yesterday",
            duration: "22 mins"
        )
    ]
    
    var availableFields: [String] {
        teachingSubjects.map(\.title)
    }
    
    var availableSubfields: [String] {
        teachingSubjects.first(where: { $0.title == selectedField })?.subtopics ?? []
    }
    
    var canFindTeachers: Bool {
        !selectedField.isEmpty
        && !selectedSubfield.isEmpty
        && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isFindingTeachers
    }

    func askTeacher() {
        showAskTeacherSheet = true
    }

    func selectTier(_ option: PricingOption) {
        // TODO: select pricing tier
    }

    func viewAllLessons() {
        // TODO: navigate to lessons
    }
    
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else { return }
            name = profile.displayName
        } catch {
            logger.error("[StudentHome] failed loading profile: \(error.localizedDescription)")
        }
    }
    
    func loadTeachingSubjects() async {
        do {
            let subjects = try await remoteConfigService.fetchTeachingSubjects()
            teachingSubjects = subjects
            applyDefaultSubjectSelectionIfNeeded()
        } catch {
            logger.error("[StudentHome] failed loading teaching subjects: \(error.localizedDescription)")
        }
    }
    
    func selectField(_ field: String) {
        selectedField = field
        selectedSubfield = ""
        applyDefaultSubfieldIfNeeded()
    }
    
    func findTeachers() async {
        guard canFindTeachers else { return }
        isFindingTeachers = true
        defer { isFindingTeachers = false }
        
        do {
            let result = try await teacherSearchRepository.findTeachers(
                field: selectedField,
                subfield: selectedSubfield,
                question: question.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            alertTitle = "Teachers Found"
            alertMessage = result.responseText.isEmpty ? "Your request was sent." : result.responseText
            showAlert = true
            showAskTeacherSheet = false
        } catch {
            alertTitle = "Teacher Search Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    
    private func applyDefaultSubjectSelectionIfNeeded() {
        guard selectedField.isEmpty, let firstSubject = teachingSubjects.first else { return }
        selectedField = firstSubject.title
        applyDefaultSubfieldIfNeeded()
    }
    
    private func applyDefaultSubfieldIfNeeded() {
        let subfields = availableSubfields
        if subfields.count == 1, let onlySubfield = subfields.first {
            selectedSubfield = onlySubfield
        }
    }
}
