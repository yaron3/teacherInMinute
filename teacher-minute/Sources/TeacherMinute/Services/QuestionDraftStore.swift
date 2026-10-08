//
//  QuestionDraftStore.swift
//  teacher-minute
//
//  Keeps the question a student was sending when they ran out of minutes, so
//  that registering or logging in to get minutes does not cost them what they
//  wrote. Sign-up swaps the whole app root, and the home screen holding the
//  question with it, so the draft has to live outside that screen — and on
//  disk, since checking mail mid-registration can see the app closed.
//

import Foundation

/// What the student had put together, as the home's composer holds it.
struct QuestionDraft: Codable, Equatable {
  var text: String
  var formulas: [String]
  var pendingFormula: String
  /// The uploaded photo's download URL. It lives in the folder of the account
  /// that took it, which after sign-up is no longer the student's — the
  /// backend refuses a photo from another account's folder — so the photo
  /// itself is kept too (`QuestionDraftStore.photoData`), to upload again.
  var photoURL: String?

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && formulas.isEmpty
      && pendingFormula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && photoURL == nil
  }
}

@MainActor
final class QuestionDraftStore {
  static let shared = QuestionDraftStore()

  private struct Stored: Codable {
    let draft: QuestionDraft
    let savedAt: Date
  }

  private let key = "pendingQuestionDraft"
  private var photoFile: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("pending-question-photo.jpg")
  }
  /// Long enough for any sign-up, short enough that a question from another
  /// day does not reappear unasked.
  private let maxAge: TimeInterval = 24 * 3600

  private init() {}

  /// Holds `draft`, and the bytes of its photo when there is one.
  func hold(_ draft: QuestionDraft, photoData: Data?) {
    discard()
    guard !draft.isEmpty,
          let data = try? JSONEncoder().encode(Stored(draft: draft, savedAt: Date())) else {
      return
    }
    UserDefaults.standard.set(data, forKey: key)
    if draft.photoURL != nil, let photoData {
      try? photoData.write(to: photoFile, options: [.atomic])
    }
  }

  /// The held draft and its photo's bytes, which are then no longer held.
  func take() -> (draft: QuestionDraft, photoData: Data?)? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    let photoData = try? Data(contentsOf: photoFile)
    discard()
    guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
          Date().timeIntervalSince(stored.savedAt) < maxAge else { return nil }
    return (stored.draft, photoData)
  }

  func discard() {
    UserDefaults.standard.removeObject(forKey: key)
    try? FileManager.default.removeItem(at: photoFile)
  }
}
