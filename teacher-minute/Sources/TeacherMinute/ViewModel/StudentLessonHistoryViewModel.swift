//
//  StudentLessonHistoryViewModel.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import Foundation
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

struct StudentLessonHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let teacher: String
    let completedAt: String
    let duration: String
    let price: String
    let summary: String
    let transcriptPreview: String
    let hasAudio: Bool
}

@Observable
@MainActor
final class StudentLessonHistoryViewModel {
    var studentName = "Student"
    var query = ""
    var selectedLesson: StudentLessonHistoryItem?
    var playingLessonID: StudentLessonHistoryItem.ID?
    
    let lessons = [
        StudentLessonHistoryItem(
            title: "Calculus Help",
            teacher: "Mr. Davis",
            completedAt: "Today, 2:30 PM",
            duration: "14 min",
            price: "$16.80",
            summary: "Reviewed derivative rules and solved three chain-rule problems.",
            transcriptPreview: "We started by identifying the outer function, then multiplied by the derivative of the inside expression.",
            hasAudio: true
        ),
        StudentLessonHistoryItem(
            title: "Algebra II",
            teacher: "Ms. Chen",
            completedAt: "Yesterday",
            duration: "22 min",
            price: "$11.00",
            summary: "Factored quadratic expressions and checked answers by expanding.",
            transcriptPreview: "When the leading coefficient is one, look for two numbers that multiply to c and add to b.",
            hasAudio: true
        ),
        StudentLessonHistoryItem(
            title: "Geometry Proofs",
            teacher: "Dr. Patel",
            completedAt: "May 7",
            duration: "18 min",
            price: "$21.60",
            summary: "Built a two-column proof using congruent triangles and parallel-line angle rules.",
            transcriptPreview: "Mark the given angles first, then use alternate interior angles to connect the parallel lines.",
            hasAudio: false
        )
    ]
    
    var filteredLessons: [StudentLessonHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return lessons }
        return lessons.filter { lesson in
            lesson.title.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.teacher.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.summary.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var completedCountText: String {
        "\(lessons.count) completed"
    }
    
    var totalSpendText: String {
        let total = lessons.reduce(0.0) { partialResult, lesson in
            partialResult + (Double(lesson.price.replacingOccurrences(of: "$", with: "")) ?? 0)
        }
        return total.formatted(.currency(code: "USD"))
    }
    
    func view(_ lesson: StudentLessonHistoryItem) {
        selectedLesson = lesson
    }
    
    func toggleAudio(for lesson: StudentLessonHistoryItem) {
        guard lesson.hasAudio else { return }
        playingLessonID = playingLessonID == lesson.id ? nil : lesson.id
    }
    
    func isPlaying(_ lesson: StudentLessonHistoryItem) -> Bool {
        playingLessonID == lesson.id
    }
    
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else { return }
            studentName = profile.displayName
        } catch {
            logger.error("[StudentLessons] failed loading profile: \(error.localizedDescription)")
        }
    }
}
