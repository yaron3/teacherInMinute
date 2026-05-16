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

    let ref = Storage.storage().reference().child(path)
    let metadata = StorageMetadata()
    metadata.contentType = mimeType
    _ = try await ref.putDataAsync(data, metadata: metadata)
    let downloadURL = try await ref.downloadURL()
    logger.info("Uploaded profile image: \(path)")
    return downloadURL.absoluteString
  }
}
