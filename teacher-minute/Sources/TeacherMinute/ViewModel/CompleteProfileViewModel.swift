//
//  CompleteProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@Observable
@MainActor
final class CompleteProfileViewModel {
  let role: AuthRole
  var selectedRole: AuthRole
  var fullName = ""
  var phoneNumber = ""
  /// Default start = 15 years ago
  var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -15, to: Date()) ?? Date()
  var grade = ""
  
  var isLoading = false
  var errorMessage: String?
  var onContinue: (() -> Void)?
  
  let grades: [String] = (1...12).map { "Grade \($0)" } + ["College", "Adult Learner"]
  
  var canContinue: Bool {
	!fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
	!phoneNumber.isEmpty &&
	!isLoading
  }
  
  init(role: AuthRole) {
	self.role = role
	self.selectedRole = role
  }
  
  func continueFlow() {
	guard canContinue else { return }
	isLoading = true
	
	Task {
	  do {
		guard let user = Auth.auth().currentUser else {
		  errorMessage = "No authenticated user found."
		  isLoading = false
		  return
		}
		
		let profile = UserProfile(
		  uid:         user.uid,
		  email:       user.email ?? "",
		  fullName:    fullName,
		  phoneNumber: phoneNumber,
		  dateOfBirth: dateOfBirth,
		  grade:       grade,
		  role:        role.rawValue,
		  createdAt:   Date()
		)
		
		try await UserService.shared.saveProfile(profile)
		isLoading = false
		onContinue?()
	  } catch {
		errorMessage = error.localizedDescription
		isLoading = false
	  }
	}
  }
}
