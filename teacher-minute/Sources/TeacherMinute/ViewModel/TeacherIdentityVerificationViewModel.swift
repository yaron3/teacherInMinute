//
//  TeacherIdentityVerificationViewModel.swift
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

// MARK: - Image picker target

enum UploadTarget {
  case teachingCredentials
  case governmentIDFront
  case governmentIDBack
  case selfie
}

// MARK: - ViewModel

@Observable
@MainActor
final class TeacherIdentityVerificationViewModel {
  
  // MARK: Upload state
  var hasTeachingCredentials = false
  var hasGovernmentIDFront   = false
  var hasGovernmentIDBack    = false
  var hasSelfie              = false
  var acceptedTerms          = false
  
  // MARK: Picker presentation
  var activeUploadTarget: UploadTarget?
  var showImagePicker      = false
  var showCameraPicker     = false
  
  // MARK: Feedback
  var uploadingTarget: UploadTarget?          // which button is spinning
  var isCheckingCompletion = false
  var uploadError: String?
  
  // MARK: Stored paths (Firebase Storage)
  private var uploadedPaths: [String] = []
  
  var onSubmit: (() -> Void)?
  
  /// Only front side (+ terms) is required to submit; everything else is optional.
  var canSubmit: Bool {
	hasGovernmentIDFront &&
	acceptedTerms        &&
	uploadingTarget == nil
  }
  
  func isUploading(for target: UploadTarget) -> Bool {
	uploadingTarget == target
  }
  
  // MARK: - Check completion on appear
  
  func checkAndAutoAdvance() {
	isCheckingCompletion = true
	Task {
	  defer { isCheckingCompletion = false }
	  guard let uid = Auth.auth().currentUser?.uid else { return }
	  let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
	  let docs = data["uploadedDocuments"] as? [String] ?? []
	  // Auto-advance only when front side is uploaded (minimum requirement)
	  if docs.contains(where: { $0.contains("_front") }) {
		onSubmit?()
	  } else {
		hasTeachingCredentials = docs.contains(where: { $0.hasPrefix("credentials_") })
		hasGovernmentIDFront   = docs.contains(where: { $0.contains("_front") })
		hasGovernmentIDBack    = docs.contains(where: { $0.contains("_back") })
		hasSelfie              = docs.contains(where: { $0.hasPrefix("selfie_") })
	  }
	}
  }
  
  // MARK: - Trigger pickers
  
  func uploadTeachingCredentials() {
	activeUploadTarget = .teachingCredentials
	showImagePicker = true
  }
  
  func uploadGovernmentIDFront() {
	activeUploadTarget = .governmentIDFront
	showImagePicker = true
  }
  
  func uploadGovernmentIDBack() {
	activeUploadTarget = .governmentIDBack
	showImagePicker = true
  }
  
  func takeSelfie() {
	activeUploadTarget = .selfie
	showCameraPicker = true
  }
  
  // MARK: - Handle picked image
  
  func handlePickedImage(_ data: Data, for target: UploadTarget) {
	guard let uid = Auth.auth().currentUser?.uid else { return }
	
	let docName = documentName(for: target, uid: uid)
	
	uploadingTarget = target
	uploadError = nil
	
	Task {
	  do {
		_ = try await StorageService.shared.uploadDocument(
		  data: data,
		  name: docName,
		  uid: uid
		)
		uploadedPaths.append(docName)
		markDone(target: target)
		try await appendDocumentToUser(uid: uid, docName: docName)
		AnalyticsService.shared.logEvent(AnalyticsEvent.teacherIdentityUploaded, parameters: ["document_type": String(describing: target)])
		uploadingTarget = nil
	  } catch {
		AnalyticsService.shared.recordError(error, context: "uploadDocument")
		uploadError = error.localizedDescription
		uploadingTarget = nil
	  }
	}
  }

  // MARK: - Submit

  func submitForReview() {
	guard canSubmit else { return }
	AnalyticsService.shared.logEvent(AnalyticsEvent.teacherIdentityUploaded, parameters: ["action": "submit_for_review"])
	onSubmit?()
  }
  
  // MARK: - Helpers
  
  /// Firestore key (uid-based, human-readable). Storage uses the same value as the filename.
  private func documentName(for target: UploadTarget, uid: String) -> String {
	switch target {
	  case .teachingCredentials: return "credentials_\(uid)"
	  case .governmentIDFront:   return "govId_\(uid)_front"
	  case .governmentIDBack:    return "govId_\(uid)_back"
	  case .selfie:              return "selfie_\(uid)"
	}
  }
  
  private func markDone(target: UploadTarget) {
	switch target {
	  case .teachingCredentials: hasTeachingCredentials = true
	  case .governmentIDFront:   hasGovernmentIDFront   = true
	  case .governmentIDBack:    hasGovernmentIDBack    = true
	  case .selfie:              hasSelfie              = true
	}
  }
  
  private func appendDocumentToUser(uid: String, docName: String) async throws {
	let db = Firestore.firestore()
	try await db.collection("users").document(uid).setData([
	  "uploadedDocuments": FieldValue.arrayUnion([docName])
	], merge: true)
  }
}
