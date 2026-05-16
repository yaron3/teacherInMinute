//
//  ProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
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
final class ProfileViewModel {
  var name = "Profile"
  var role = "User"
  var isVerified = true
  var memberSince = "Member"
  var email = ""
  var phoneNumber = ""
  var grade = ""
  var subjects: [String] = []
  var roleType: AuthRole = .student
  var isLoading = false
  var isEditing: Bool = false
  var microphoneEnabled = true
  var notificationsEnabled = false
  var contactRows: [Parameter] = []
  var shouldShowTeachingDetails: Bool {
	roleType == .teacher
  }
  
  var gradeLevels: [String] {
	grade.isEmpty ? [] : [grade]
  }
  
  var subjectsOrPlaceholder: [String] {
	subjects.isEmpty ? ["No subjects added yet"] : subjects
  }
  init(name: String = "Profile", role: String = "User", isVerified: Bool = true, memberSince: String = "Member", email: String = "", phoneNumber: String = "", grade: String = "", subjects: [String], roleType: AuthRole, isLoading: Bool = false, isEditing: Bool, microphoneEnabled: Bool = true, notificationsEnabled: Bool = false, contactRows: [Parameter]) {
	self.name = name
	self.role = role
	self.isVerified = isVerified
	self.memberSince = memberSince
	self.email = email
	self.phoneNumber = phoneNumber
	self.grade = grade
	self.subjects = subjects
	self.roleType = roleType
	self.isLoading = isLoading
	self.isEditing = isEditing
	self.microphoneEnabled = microphoneEnabled
	self.notificationsEnabled = notificationsEnabled
	self.contactRows =  [
	  Parameter(description: "Email", value: email.isEmpty ? "Not provided" : email, image: "envelope.fill"),
	  Parameter(description: "Phone", value: phoneNumber.isEmpty ? "Not provided" : phoneNumber, image: "phone.fill")
	]
  }
  
  
  
  
  func loadProfile() async {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	isLoading = true
	defer { isLoading = false }
	
	do {
	  guard let profile = try await UserService.shared.fetchProfileSummary(uid: uid) else { return }
	  name = profile.displayName
	  role = profile.roleLabel
	  memberSince = profile.memberSinceText
	  email = profile.email
	  phoneNumber = profile.phoneNumber
	  grade = profile.grade
	  subjects = profile.subjects
	  roleType = profile.role
	  isVerified = profile.role == .teacher
	} catch {
	  logger.error("[Profile] failed loading profile: \(error.localizedDescription)")
	}
	self.contactRows =  [
	  Parameter(description: "Email", value: email.isEmpty ? "Not provided" : email, image: "envelope.fill"),
	  Parameter(description: "Phone", value: phoneNumber.isEmpty ? "Not provided" : phoneNumber, image: "phone.fill")
	]
  }
  
  func editProfile() {
	isEditing.toggle()
  }
  
  func changePhoto() {
	// TODO: image picker
  }
  
  func editGradeLevels() {
	// TODO
  }
  
  func editSubjects() {
	// TODO
  }
  
  func addGradeLevel() {
	// TODO
  }
  
  func manageNotifications() {
	// TODO
  }
  
  func logout() {
	// TODO
  }
}
