//
//  TeacherDocumentsViewModel.swift
//  teacher-minute
//

import Foundation
import Observation

#if !os(Android)
import FirebaseAuth
import FirebaseFirestore
#else
import SkipFirebaseAuth
import SkipFirebaseFirestore
#endif

/// A single uploaded verification document, resolved to a displayable URL.
struct TeacherDocument: Identifiable {
  let id: String        // the stored document name (unique per user)
  let title: String     // human-readable label
  let url: String       // download URL (empty until resolved)
}

@Observable
@MainActor
final class TeacherDocumentsViewModel {

  var documents: [TeacherDocument] = []
  var isLoading = false
  var errorMessage: String?
  var uploadingTarget: UploadTarget?

  /// All document types a teacher can provide, in display order.
  static let allTargets: [UploadTarget] = [.governmentIDFront, .governmentIDBack, .teachingCredentials, .selfie]

  private var uploadedNames: Set<String> = []

  var hasDocuments: Bool { !documents.isEmpty }

  /// Targets the teacher has not uploaded yet.
  var missingTargets: [UploadTarget] {
    Self.allTargets.filter { !hasTarget($0) }
  }

  func isMissing(_ target: UploadTarget) -> Bool {
    !hasTarget(target)
  }

  func isUploading(_ target: UploadTarget) -> Bool {
    uploadingTarget == target
  }

  func title(for target: UploadTarget) -> String {
    Self.title(for: target)
  }

  func load() async {
    guard let uid = Auth.auth().currentUser?.uid else {
      errorMessage = LocalizationSupport.localized("Could not load documents.")
      return
    }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
    let names = (data["uploadedDocuments"] as? [String]) ?? []
    uploadedNames = Set(names)
    let ordered = names.sorted { Self.rank(for: $0) < Self.rank(for: $1) }

    var resolved: [TeacherDocument] = []
    for name in ordered {
      let title = Self.title(for: name)
      let url = (try? await StorageService.shared.documentDownloadURL(name: name, uid: uid)) ?? ""
      resolved.append(TeacherDocument(id: name, title: title, url: url))
    }
    documents = resolved
  }

  /// Uploads a newly picked image for a missing document, then refreshes the list.
  func handlePickedImage(_ data: Data, for target: UploadTarget) {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    let docName = Self.documentName(for: target, uid: uid)
    uploadingTarget = target
    errorMessage = nil

    Task {
      do {
        _ = try await StorageService.shared.uploadDocument(data: data, name: docName, uid: uid)
        try await appendDocumentToUser(uid: uid, docName: docName)
        AnalyticsService.shared.logEvent(
          AnalyticsEvent.teacherIdentityUploaded,
          parameters: ["document_type": String(describing: target), "source": "profile_documents"]
        )
        uploadingTarget = nil
        await load()
      } catch {
        errorMessage = error.localizedDescription
        uploadingTarget = nil
      }
    }
  }

  // MARK: - Helpers

  private func hasTarget(_ target: UploadTarget) -> Bool {
    switch target {
    case .teachingCredentials: return uploadedNames.contains { $0.hasPrefix("credentials_") }
    case .governmentIDFront:   return uploadedNames.contains { $0.contains("_front") }
    case .governmentIDBack:    return uploadedNames.contains { $0.contains("_back") }
    case .selfie:              return uploadedNames.contains { $0.hasPrefix("selfie_") }
    }
  }

  private func appendDocumentToUser(uid: String, docName: String) async throws {
    let db = Firestore.firestore()
    try await db.collection("users").document(uid).setData([
      "uploadedDocuments": FieldValue.arrayUnion([docName])
    ], merge: true)
  }

  private static func documentName(for target: UploadTarget, uid: String) -> String {
    switch target {
    case .teachingCredentials: return "credentials_\(uid)"
    case .governmentIDFront:   return "govId_\(uid)_front"
    case .governmentIDBack:    return "govId_\(uid)_back"
    case .selfie:              return "selfie_\(uid)"
    }
  }

  private static func rank(for name: String) -> Int {
    if name.contains("_front") { return 0 }
    if name.contains("_back") { return 1 }
    if name.hasPrefix("credentials_") { return 2 }
    if name.hasPrefix("selfie_") { return 3 }
    return 4
  }

  private static func title(for name: String) -> String {
    if name.contains("_front") { return LocalizationSupport.localized("Government ID – Front") }
    if name.contains("_back") { return LocalizationSupport.localized("Government ID – Back") }
    if name.hasPrefix("credentials_") { return LocalizationSupport.localized("Teaching Credentials") }
    if name.hasPrefix("selfie_") { return LocalizationSupport.localized("Selfie Verification") }
    return name
  }

  private static func title(for target: UploadTarget) -> String {
    switch target {
    case .teachingCredentials: return LocalizationSupport.localized("Teaching Credentials")
    case .governmentIDFront:   return LocalizationSupport.localized("Government ID – Front")
    case .governmentIDBack:    return LocalizationSupport.localized("Government ID – Back")
    case .selfie:              return LocalizationSupport.localized("Selfie Verification")
    }
  }
}
