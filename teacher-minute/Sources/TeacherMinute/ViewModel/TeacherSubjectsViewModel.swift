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

@Observable
@MainActor
final class TeacherSubjectsViewModel {
  var searchText = ""
  var selectedSubjects: Set<SubjectOption> = []
  var isCheckingCompletion = true
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
  
  // MARK: - Auto-advance
  
  func checkAndAutoAdvance() {
	Task {
	  defer { isCheckingCompletion = false }
	  guard let uid = Auth.auth().currentUser?.uid else { return }
	  let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
	  let subjects = data["subjects"] as? [String] ?? []
	  if !subjects.isEmpty {
		// Pre-select saved subjects
		let allSubjects = popularSubjects + advancedSubjects
		for saved in subjects {
		  if let match = allSubjects.first(where: { $0.title == saved }) {
			selectedSubjects.insert(match)
		  }
		}
		onContinue?()
	  }
	}
  }
  
  // MARK: - Actions
  
  func toggle(_ subject: SubjectOption) {
	if selectedSubjects.contains(subject) {
	  selectedSubjects.remove(subject)
	} else {
	  selectedSubjects.insert(subject)
	}
  }
  
  func continueOnboarding() {
	guard canContinue else { return }
	Task {
	  guard let uid = Auth.auth().currentUser?.uid else { onContinue?(); return }
	  let db = Firestore.firestore()
	  let subjectTitles = selectedSubjects.map { $0.title }
	  try? await db.collection("users").document(uid).setData([
		"subjects": subjectTitles
	  ], merge: true)
	  onContinue?()
	}
  }
  
  func skip() {
	onContinue?()
  }
}
