//
//  TeacherSubjectsViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

#if !os(Android)
import FirebaseAuth
import FirebaseFirestore
#else
import SkipFirebaseAuth
import SkipFirebaseFirestore
#endif

struct TeachingSubjectArea: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let subtopics: [SubjectOption]
}

@Observable
@MainActor
final class TeacherSubjectsViewModel {
  var searchText = ""
  var selectedAreaIDs: Set<String> = []
  var selectedSubtopicTitlesByArea: [String: Set<String>] = [:]
  var isCheckingCompletion = true
  var onContinue: (() -> Void)?
  
  var subjectAreas: [TeachingSubjectArea] = []
  
  private let fallbackSubjectAreas: [TeachingSubjectArea] = [
	TeachingSubjectArea(
	  id: "math",
	  title: "Math",
	  systemImage: "function",
	  subtopics: [
		SubjectOption(title: "General Math", systemImage: "function"),
		SubjectOption(title: "Algebra", systemImage: "x.squareroot"),
		SubjectOption(title: "Geometry", systemImage: "triangle"),
		SubjectOption(title: "Calculus", systemImage: "chart.xyaxis.line"),
		SubjectOption(title: "Statistics", systemImage: "chart.pie"),
		SubjectOption(title: "Trigonometry", systemImage: "angle")
	  ]
	),
	TeachingSubjectArea(
	  id: "physics",
	  title: "Physics",
	  systemImage: "atom",
	  subtopics: [
		SubjectOption(title: "Mechanics", systemImage: "gearshape.2"),
		SubjectOption(title: "Electricity", systemImage: "bolt.fill"),
		SubjectOption(title: "Waves", systemImage: "waveform.path.ecg")
	  ]
	),
	TeachingSubjectArea(
	  id: "computer_science",
	  title: "Computer Science",
	  systemImage: "desktopcomputer",
	  subtopics: [
		SubjectOption(title: "Programming", systemImage: "chevron.left.forwardslash.chevron.right")
	  ]
	)
  ]
  
  private let remoteConfigService: SettingsRemoteConfigService
  
  init(remoteConfigService: SettingsRemoteConfigService = .shared) {
	self.remoteConfigService = remoteConfigService
	self.subjectAreas = fallbackSubjectAreas
  }
  
  var visibleAreas: [TeachingSubjectArea] {
	let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !trimmedQuery.isEmpty else { return subjectAreas }
	return subjectAreas.filter { area in
	  area.title.localizedCaseInsensitiveContains(trimmedQuery)
	  || area.subtopics.contains { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
	}
  }
  
  var selectedAreas: [TeachingSubjectArea] {
	subjectAreas.filter { selectedAreaIDs.contains($0.id) }
  }
  
  func visibleSubtopics(for area: TeachingSubjectArea) -> [SubjectOption] {
	let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !trimmedQuery.isEmpty else { return area.subtopics }
	return area.subtopics.filter {
	  $0.title.localizedCaseInsensitiveContains(trimmedQuery)
	}
  }
  
  var canContinue: Bool {
	!selectedAreaIDs.isEmpty
	&& selectedAreas.allSatisfy { selectedSubtopicTitles(for: $0).isEmpty == false }
  }
  
  var selectedCountText: String {
	let areaCount = selectedAreaIDs.count
	let subtopicCount = selectedSubtopicTitlesByArea.values.reduce(0) { $0 + $1.count }
	guard areaCount > 0 else { return LocalizationSupport.localized("Choose subjects") }
	let subjectPart = areaCount == 1
	  ? LocalizationSupport.localized("1 subject")
	  : String(format: LocalizationSupport.localized("%lld subjects"), areaCount)
	let subtopicPart = subtopicCount == 1
	  ? LocalizationSupport.localized("1 subtopic")
	  : String(format: LocalizationSupport.localized("%lld subtopics"), subtopicCount)
	return "\(subjectPart), \(subtopicPart)"
  }
  
  var shouldShowSubtopicsPrompt: Bool {
	selectedAreaIDs.isEmpty
  }
  
  // MARK: - Auto-advance
  
  func checkAndAutoAdvance() {
	Task {
	  defer { isCheckingCompletion = false }
	  await loadSubjectCatalog()
	  await restoreExistingSelections()
	  if canContinue {
		onContinue?()
	  }
	}
  }

  func loadSelections() {
	Task {
	  defer { isCheckingCompletion = false }
	  await loadSubjectCatalog()
	  await restoreExistingSelections()
	}
  }

  private func restoreExistingSelections() async {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
	guard let selections = data["subjectSelections"] as? [String: [String]], !selections.isEmpty else { return }

	for area in subjectAreas {
	  let savedSubtopics = selections[area.title] ?? []
	  guard !savedSubtopics.isEmpty else { continue }
	  selectedAreaIDs.insert(area.id)
	  selectedSubtopicTitlesByArea[area.id] = Set(area.subtopics.map(\.title).filter { savedSubtopics.contains($0) })
	}
  }
  
  private func loadSubjectCatalog() async {
	do {
	  let remoteSubjects = try await remoteConfigService.fetchTeachingSubjects()
	  let areas = remoteSubjects
		.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
		.map { remoteSubject in
		  TeachingSubjectArea(
			id: subjectID(for: remoteSubject.title),
			title: remoteSubject.title,
			systemImage: systemImage(for: remoteSubject.title),
			subtopics: remoteSubject.subtopics.map {
			  SubjectOption(title: $0, systemImage: systemImage(for: $0))
			}
		  )
		}
		.filter { !$0.subtopics.isEmpty }
	  
	  if !areas.isEmpty {
		subjectAreas = areas
	  }
	} catch {
	  logger.error("[TeacherSubjects] failed loading remote subject catalog: \(error.localizedDescription)")
	  AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherSubjects.loadRemoteCatalog")
	}
  }
  
  // MARK: - Actions
  
  func toggleArea(_ area: TeachingSubjectArea) {
	if selectedAreaIDs.contains(area.id) {
	  selectedAreaIDs.remove(area.id)
	  selectedSubtopicTitlesByArea[area.id] = nil
	  return
	}
	
	selectedAreaIDs.insert(area.id)
	
	if area.subtopics.count == 1, let onlySubtopic = area.subtopics.first {
	  selectedSubtopicTitlesByArea[area.id] = [onlySubtopic.title]
	}
  }
  
  func toggleSubtopic(_ subtopic: SubjectOption, in area: TeachingSubjectArea) {
	var selectedTitles = selectedSubtopicTitlesByArea[area.id] ?? []
	if selectedTitles.contains(subtopic.title) {
	  selectedTitles.remove(subtopic.title)
	} else {
	  selectedTitles.insert(subtopic.title)
	}
	selectedSubtopicTitlesByArea[area.id] = selectedTitles
  }
  
  func isAreaSelected(_ area: TeachingSubjectArea) -> Bool {
	selectedAreaIDs.contains(area.id)
  }
  
  func isSubtopicSelected(_ subtopic: SubjectOption, in area: TeachingSubjectArea) -> Bool {
	selectedSubtopicTitlesByArea[area.id]?.contains(subtopic.title) == true
  }
  
  func selectedSubtopicTitles(for area: TeachingSubjectArea) -> Set<String> {
	selectedSubtopicTitlesByArea[area.id] ?? []
  }
  
  func continueOnboarding() {
	guard canContinue else { return }
	Task {
	  guard let uid = Auth.auth().currentUser?.uid else { onContinue?(); return }
	  let db = Firestore.firestore()
	  let selectedAreas = selectedAreas
	  let selectedAreaIDs = selectedAreas.map(\.id)
	  let selectedAreaTitles = selectedAreas.map(\.title)
	  let subjectSelections = Dictionary(
		uniqueKeysWithValues: selectedAreas.map { area in
		  (area.title, Array(selectedSubtopicTitles(for: area)).sorted())
		}
	  )
	  try? await db.collection("users").document(uid).setData([
		"subjectAreaIDs": selectedAreaIDs,
		"subjectAreas": selectedAreaTitles,
		"subjectSelections": subjectSelections
	  ], merge: true)
	  AnalyticsService.shared.logEvent(AnalyticsEvent.teacherSubjectsSaved, parameters: [
		"area_count": selectedAreaIDs.count,
		"subtopic_count": subjectSelections.values.reduce(0) { $0 + $1.count },
		"areas": selectedAreaTitles.joined(separator: ",")
	  ])
	  onContinue?()
	}
  }
  
  private func subjectID(for title: String) -> String {
	title
	  .lowercased()
	  .filter { $0.isLetter || $0.isNumber }
  }
  
  private func systemImage(for title: String) -> String {
	let lowercasedTitle = title.lowercased()
	if lowercasedTitle.contains("math") { return "function" }
	if lowercasedTitle.contains("physics") { return "atom" }
	if lowercasedTitle.contains("chem") { return "testtube.2" }
	if lowercasedTitle.contains("algebra") { return "x.squareroot" }
	if lowercasedTitle.contains("geometry") { return "triangle" }
	if lowercasedTitle.contains("trigon") { return "angle" }
	if lowercasedTitle.contains("calculus") { return "chart.xyaxis.line" }
	if lowercasedTitle.contains("stat") { return "chart.pie" }
	return "book.closed.fill"
  }
}
