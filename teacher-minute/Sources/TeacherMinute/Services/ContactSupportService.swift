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
  
  var firestoreData: [String: Any] {
	let iso = ISO8601DateFormatter()
	return [
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
  }
  
  var previewRows: [(String, String)] {
	[
	  (LocalizationSupport.localized("Title"), title),
	  (LocalizationSupport.localized("Description"), description),
	  (LocalizationSupport.localized("Name"), userName),
	  (LocalizationSupport.localized("User ID"), userID),
	  (LocalizationSupport.localized("Time Sent"), Self.previewDateFormatter.string(from: sentAt)),
	  (LocalizationSupport.localized("Device Type"), deviceType),
	  (LocalizationSupport.localized("OS Version"), osVersion),
	  (LocalizationSupport.localized("Locale"), locale)
	]
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
	role: AppUserMode
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
	  role: role == .teacher ? "teacher" : "student"
	)
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
	return "Android \(v.majorVersion).\(v.minorVersion)"
#elseif os(iOS)
	return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#else
	return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#endif
  }
}
