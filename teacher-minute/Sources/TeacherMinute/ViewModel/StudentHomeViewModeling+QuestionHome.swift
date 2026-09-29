//
//  StudentHomeViewModeling+QuestionHome.swift
//  teacher-minute
//
//  The student's home: the camera the question is photographed with, and the
//  panel it can be written on instead (`StudentQuestionHomeView`).
//

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

/// Which face of the home is showing.
enum QuestionHomeMode: Hashable {
  case photo
  case text
}

/// Where an attached photo came from, for analytics.
enum QuestionPhotoSource: String {
  case camera
  case library
}

extension StudentHomeViewModeling {

  // MARK: Question home — copy

  var photoModeLabel: String { LocalizationSupport.localized("Photo") }
  var textModeLabel: String { LocalizationSupport.localized("Text") }
  var attachPhotoLabel: String { LocalizationSupport.localized("Attach photo") }
  /// The character's first bubble on the camera. Broken into lines by hand:
  /// the bubble sets its lines closer than a paragraph would.
  var snapYourQuestionText: String { LocalizationSupport.localized("Snap your\nquestion") }
  /// The character's first bubble on the writing panel, and the hint on it.
  var typeYourQuestionText: String { LocalizationSupport.localized("Write your\nquestion") }
  /// The character's third bubble: two lines in English, one in Hebrew.
  var pricePerMinuteBubbleText: String { LocalizationSupport.localized("₪2\nper minute") }
  var noFixedLessonsText: String { LocalizationSupport.localized("₪2 per minute • no fixed lessons") }
  var chooseKeyboardTitle: String { LocalizationSupport.localized("Choose keyboard") }
  var deletePhotoLabel: String { LocalizationSupport.localized("Delete photo") }
  var findTeacherLabel: String { LocalizationSupport.localized("Find a Teacher") }
  var loadMinutesLabel: String { LocalizationSupport.localized("Load minutes") }
  var emptyQuestionTitle: String { LocalizationSupport.localized("Add your question") }
  var emptyQuestionMessage: String {
    LocalizationSupport.localized("Take a photo of it, or write at least 10 characters.")
  }
  var photoNotAttachedTitle: String { LocalizationSupport.localized("Photo not attached") }

  /// Teachers who could take a question now. One in a lesson is online but
  /// not available, so is not counted.
  var availableTeacherCount: Int {
    onlineTeachers.filter { !$0.isBusy }.count
  }

  /// The count in the character's second bubble; `teachersOnlineBubbleLabel`
  /// goes under it.
  var teachersOnlineBubbleCount: String { "\(availableTeacherCount)" }

  var teachersOnlineBubbleLabel: String {
    availableTeacherCount == 1
      ? LocalizationSupport.localized("teacher\nonline")
      : LocalizationSupport.localized("teachers\nonline")
  }

  // MARK: Question home — asking

  /// The home asks without a topic: any teacher online may take the question.
  var anyTopic: String { "any" }

  /// The session a question asks for, as chosen in Settings. An audio call
  /// when the student has not chosen.
  var defaultConversationType: String {
    UserDefaults.standard.string(forKey: SessionPreferences.defaultQuestionTypeKey)
      ?? ConversationType.audio.rawValue
  }

  // MARK: Question home — camera

  var questionCameraAccess: PermissionState {
    PermissionService.shared.captureStatus(for: .camera)
  }

  func requestQuestionCameraAccess() async -> PermissionState {
    await PermissionService.shared.requestCapturePermission(for: .camera)
  }

  func openCameraSettings() {
    PermissionService.shared.openAppSettings()
  }

  /// Photographs the question with the camera on screen.
  func takeQuestionPhoto() async throws -> Data {
    do {
      return try await QuestionCamera.capturePhoto()
    } catch {
      logQuestionPhotoFailure(error, source: .camera)
      throw error
    }
  }

#if os(iOS)
  /// A photo picked from the library, made ready to upload.
  func preparedLibraryPhoto(_ data: Data) throws -> Data {
    do {
      return try QuestionCamera.preparedForUpload(data)
    } catch {
      logQuestionPhotoFailure(error, source: .library)
      throw error
    }
  }
#endif

#if os(Android)
  /// A photo from the gallery, or nil when the student backed out of it.
  func pickQuestionPhotoFromLibrary() async throws -> Data? {
    do {
      let base64 = try await Task.detached(priority: .userInitiated) {
        try AndroidAskTeacherImagePickerBridge.pickImageBase64()
      }.value
      guard !base64.isEmpty else { return nil }
      guard let data = Data(base64Encoded: base64) else { throw QuestionCamera.CaptureError.unreadable }
      return data
    } catch {
      logQuestionPhotoFailure(error, source: .library)
      throw error
    }
  }
#endif

  /// Uploads a photo of the question, returning its URL.
  func uploadQuestionPhoto(_ data: Data, source: QuestionPhotoSource) async throws -> String {
    guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
      throw QuestionPhotoError.signedOut(message: signInToAttachPhotoError)
    }
    do {
      let url = try await StorageService.shared.uploadQuestionImage(data: data, uid: uid)
      AnalyticsService.shared.logEvent(AnalyticsEvent.questionPhotoAttached, parameters: [
        "source": source.rawValue,
        "bytes": data.count
      ])
      return url
    } catch {
      logQuestionPhotoFailure(error, source: source)
      throw error
    }
  }

  private func logQuestionPhotoFailure(_ error: Error, source: QuestionPhotoSource) {
    logger.error("[QuestionHome] photo from \(source.rawValue) failed: \(error.localizedDescription)")
    AnalyticsService.shared.logEvent(AnalyticsEvent.questionPhotoFailed, parameters: [
      "source": source.rawValue
    ])
    AnalyticsService.shared.recordError(error, context: "question_photo_\(source.rawValue)")
  }
}

enum QuestionPhotoError: LocalizedError {
  case signedOut(message: String)

  var errorDescription: String? {
    switch self {
    case .signedOut(let message): return message
    }
  }
}
