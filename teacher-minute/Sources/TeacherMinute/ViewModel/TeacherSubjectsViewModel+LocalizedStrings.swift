//
//  TeacherSubjectsViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the subject-selection step.
//

import Foundation

extension TeacherSubjectsViewModel {

    // MARK: Screen chrome
    var onboardingTitle: String { LocalizationSupport.localized("What can you teach?") }
    var editingTitle: String { LocalizationSupport.localized("Edit Subjects") }
    var stepIndicatorText: String { LocalizationSupport.localized("Step 2 of 2") }
    var introText: String {
        LocalizationSupport.localized("Choose a subject area, then select at least\none subtopic students can request.")
    }
    var checkingText: String { LocalizationSupport.localized("Checking your subjects…") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }

    /// The screen is both an onboarding step and a standalone editor, and the
    /// navigation title says which one the teacher is looking at.
    func navigationTitle(isEditing: Bool) -> String {
        isEditing ? editingTitle : ""
    }

    // MARK: Subject areas
    var subjectAreaSectionTitle: String { LocalizationSupport.localized("Subject Area") }
    var noAreasSelectedText: String {
        LocalizationSupport.localized("Choose one or more subjects to see subtopics.")
    }
    var searchPlaceholder: String { LocalizationSupport.localized("Search subjects or subtopics") }

    /// Display name of a subject area, which is stored in English.
    func areaTitle(_ area: TeachingSubjectArea) -> String {
        LocalizationSupport.localized(area.title)
    }

    /// Display name of a subtopic, which is stored in English.
    func subtopicTitle(_ subtopic: SubjectOption) -> String {
        LocalizationSupport.localized(subtopic.title)
    }

    func subtopicsSectionTitle(for area: TeachingSubjectArea) -> String {
        String(format: LocalizationSupport.localized("%@ subtopics"), areaTitle(area))
    }

    // MARK: Subtopic badge
    var requiredBadgeLabel: String { LocalizationSupport.localized("Required") }

    /// How many subtopics an area has selected, or that it still needs one.
    func subtopicBadgeLabel(for area: TeachingSubjectArea) -> String {
        let count = selectedSubtopicTitles(for: area).count
        guard count > 0 else { return requiredBadgeLabel }
        return String(format: LocalizationSupport.localized("%d selected"), count)
    }

    // MARK: Continue
    var saveChangesLabel: String { LocalizationSupport.localized("Save Changes") }
    var continueToOnboardingLabel: String {
        LocalizationSupport.localized("Continue to Onboarding")
    }

    func continueButtonLabel(isEditing: Bool) -> String {
        isEditing ? saveChangesLabel : continueToOnboardingLabel
    }
}
