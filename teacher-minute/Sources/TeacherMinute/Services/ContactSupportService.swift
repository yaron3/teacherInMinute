//
//  ContactSupportService.swift
//  teacher-minute
//

import Foundation

#if os(Android)
import SkipFirebaseFirestore
#else
import FirebaseFirestore
#endif

struct ContactSupportRequest: Identifiable {
  let id: String
  let title: String
  let description: String
  let userID: String
  let userName: String
  let userEmail: String
  let sentAt: Date
  let deviceType: String
  let osVersion: String
  let locale: String
  let role: String
  /// How many images go with the request. They are uploaded to
  /// `contactAttachments/{userId}/{id}/{index}.jpg` before the request is
  /// written, and the backend reads them back by index.
  var attachmentCount = 0
  
  var firestoreData: [String: Any] {
	let iso = ISO8601DateFormatter()
	var data: [String: Any] = [
	  "id": id,
	  "title": title,
	  "description": description,
	  "userId": userID,
	  "userName": userName,
	  "userEmail": userEmail,
	  "sentAt": iso.string(from: sentAt),
	  "deviceType": deviceType,
	  "osVersion": osVersion,
	  "locale": locale,
	  "role": role
	]
	// Only when there are images: a request without any then still passes
	// firestore.rules as they were before attachments (IT-32), whichever of
	// the app and the rules reaches users first.
	if attachmentCount > 0 {
	  data["attachmentCount"] = attachmentCount
	}
	return data
  }
  
  var previewRows: [(String, String)] {
	var rows = [
	  (LocalizationSupport.localized("Title"), title),
	  (LocalizationSupport.localized("Description"), description),
	  (LocalizationSupport.localized("Name"), userName),
	  (LocalizationSupport.localized("User ID"), userID),
	  (LocalizationSupport.localized("Time Sent"), Self.previewDateFormatter.string(from: sentAt)),
	  (LocalizationSupport.localized("Device Type"), deviceType),
	  (LocalizationSupport.localized("OS Version"), osVersion),
	  (LocalizationSupport.localized("Locale"), locale)
	]
	if attachmentCount > 0 {
	  rows.insert((LocalizationSupport.localized("Attachments"), "\(attachmentCount)"), at: 2)
	}
	return rows
  }
  
  private static var previewDateFormatter: DateFormatter {
	let formatter = DateFormatter()
	formatter.dateStyle = .medium
	formatter.timeStyle = .short
	formatter.locale = LocalizationSupport.currentLocale
	return formatter
  }
}

@MainActor
final class ContactSupportService {
  static let shared = ContactSupportService()
  
  private init() {}
  
  func makeRequest(
	title: String,
	description: String,
	userID: String,
	userName: String,
	userEmail: String,
	role: AppUserMode,
	attachmentCount: Int = 0
  ) -> ContactSupportRequest {
	ContactSupportRequest(
	  id: UUID().uuidString,
	  title: title,
	  description: description,
	  userID: userID,
	  userName: userName,
	  userEmail: userEmail,
	  sentAt: Date(),
	  deviceType: Self.deviceType,
	  osVersion: Self.osVersion,
	  locale: LocalizationSupport.currentLocale.identifier,
	  role: role == .teacher ? "teacher" : "student",
	  attachmentCount: attachmentCount
	)
  }

  /// The most images one request can carry; firestore.rules and
  /// storage.rules allow no more.
  static let maxAttachments = 3

  /// The longer side an attached image is scaled to: enough to read a
  /// full-height phone screenshot.
  static let attachmentMaxDimension: CGFloat = 2400

  /// Android only: where the form's thumbnails are written for the image
  /// loader (see `LocalPhotoThumbnail`).
  static let attachmentPreviewDirectory = "ContactAttachmentPreview"

  /// Uploads the request's images, then writes the request that counts them,
  /// so the backend finds every image when the request arrives.
  func send(_ request: ContactSupportRequest, attachments: [Data]) async throws {
	for (index, data) in attachments.prefix(Self.maxAttachments).enumerated() {
	  try await StorageService.shared.uploadContactAttachment(
		data: data,
		uid: request.userID,
		requestID: request.id,
		index: index
	  )
	}
	try await save(request)
  }
  
  func save(_ request: ContactSupportRequest) async throws {
	try await Firestore.firestore()
	  .collection("contactRequests")
	  .document(request.id)
	  .setData(request.firestoreData, merge: false)
  }
  
  private static var deviceType: String {
#if os(Android)
	return "Android"
#elseif os(iOS)
	return "iPhone"
#else
	return "Mac"
#endif
  }
  
  private static var osVersion: String {
	let v = ProcessInfo.processInfo.operatingSystemVersion
#if os(Android)
	// ProcessInfo reports the Linux kernel version on Android.
	return "Android \(AndroidDeviceInfoBridge.osVersion() ?? "\(v.majorVersion).\(v.minorVersion)")"
#elseif os(iOS)
	return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#else
	return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#endif
  }
}
