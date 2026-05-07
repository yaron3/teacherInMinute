//
//  StudentHomeViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import Foundation

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
final class StudentHomeViewModel {
    var name = "Sarah Jenkins"

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

    func askTeacher() {
        // TODO: start request flow
    }

    func selectTier(_ option: PricingOption) {
        // TODO: select pricing tier
    }

    func viewAllLessons() {
        // TODO: navigate to lessons
    }
}
