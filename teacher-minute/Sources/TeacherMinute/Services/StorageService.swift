//
//  StorageService.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import Foundation

#if !os(Android)
import FirebaseStorage
#if os(iOS)
import UIKit
#endif
#else
import SkipFirebaseStorage
#endif

@MainActor
final class StorageService {
  static let shared = StorageService()
  private init() {}
  
  /// Uploads image data and returns the storage path (e.g. "documents/govId_abc123_front.jpg").
  /// Wraps the upload in a UIApplication background task so GTMSessionFetcher doesn't
  /// exceed the 30-second background-task limit and trigger the OS warning.
  func uploadDocument(
	data: Data,
	name: String,             // e.g. "frontSide"
	uid: String,              // user's Firebase UID — stored under users/{uid}/
	mimeType: String = "image/jpeg"
  ) async throws -> String {
	let path = "documents/\(uid)/\(name).jpg"
	
#if os(iOS)
	// beginBackgroundTask is synchronous — no await.
	// Use a reference-type box so the expiration handler and defer share the same ID.
	final class BGTaskBox { var id = UIBackgroundTaskIdentifier.invalid }
	let box = BGTaskBox()
	box.id = UIApplication.shared.beginBackgroundTask(withName: "upload-\(name)") {
	  UIApplication.shared.endBackgroundTask(box.id)
	  box.id = .invalid
	}
	defer {
	  if box.id != .invalid {
		UIApplication.shared.endBackgroundTask(box.id)
		box.id = .invalid
	  }
	}
#endif
	
	let ref = Storage.storage().reference().child(path)
	let metadata = StorageMetadata()
	metadata.contentType = mimeType
	_ = try await ref.putDataAsync(data, metadata: metadata)
    logger.info("Uploaded document: \(path)")
    return path
  }

  func uploadProfileImage(
    data: Data,
    uid: String,
    mimeType: String = "image/jpeg"
  ) async throws -> String {
    let path = "profileImages/\(uid)/profile.jpg"

#if os(iOS)
    final class BGTaskBox { var id = UIBackgroundTaskIdentifier.invalid }
    let box = BGTaskBox()
    box.id = UIApplication.shared.beginBackgroundTask(withName: "upload-profile-image") {
      UIApplication.shared.endBackgroundTask(box.id)
      box.id = .invalid
    }
    defer {
      if box.id != .invalid {
        UIApplication.shared.endBackgroundTask(box.id)
        box.id = .invalid
      }
    }
#endif

    let uploadData = Self.profileUploadData(from: data)
    let ref = Storage.storage().reference().child(path)
    let metadata = StorageMetadata()
    metadata.contentType = mimeType
    _ = try await ref.putDataAsync(uploadData, metadata: metadata)
    let downloadURL = try await ref.downloadURL()
    logger.info("Uploaded profile image: \(path)")
    return downloadURL.absoluteString
  }

  private static func profileUploadData(from data: Data) -> Data {
#if os(iOS)
    guard let image = UIImage(data: data),
          let resized = image.resizedJPEGData(maxPixelSize: 320, compressionQuality: 0.82) else {
      return data
    }
    return resized
#else
    return data
#endif
  }

#if !os(Android)
  func uploadBoardSnapshot(
    data: Data,
    questionId: String
  ) async throws -> String {
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let path = "boardSnapshots/\(questionId)/\(timestamp).jpg"
    let ref = Storage.storage().reference().child(path)
    let metadata = StorageMetadata()
    metadata.contentType = "image/jpeg"
    _ = try await ref.putDataAsync(data, metadata: metadata)
    let url = try await ref.downloadURL()
    logger.info("Uploaded board snapshot: \(path)")
    return url.absoluteString
  }
#endif

  func uploadQuestionImage(
    data: Data,
    uid: String,
    mimeType: String = "image/jpeg"
  ) async throws -> String {
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let path = "questionImages/\(uid)/\(timestamp).jpg"

#if os(iOS)
    final class BGTaskBox { var id = UIBackgroundTaskIdentifier.invalid }
    let box = BGTaskBox()
    box.id = UIApplication.shared.beginBackgroundTask(withName: "upload-question-image") {
      UIApplication.shared.endBackgroundTask(box.id)
      box.id = .invalid
    }
    defer {
      if box.id != .invalid {
        UIApplication.shared.endBackgroundTask(box.id)
        box.id = .invalid
      }
    }
#endif

    let ref = Storage.storage().reference().child(path)
    let metadata = StorageMetadata()
    metadata.contentType = mimeType
    _ = try await ref.putDataAsync(data, metadata: metadata)
    let downloadURL = try await ref.downloadURL()
    logger.info("Uploaded question image: \(path)")
    return downloadURL.absoluteString
  }
}
