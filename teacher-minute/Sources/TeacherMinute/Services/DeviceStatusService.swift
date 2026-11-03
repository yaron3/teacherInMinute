//
//  DeviceStatusService.swift
//  teacher-minute
//

import Foundation

#if !os(Android)
import UIKit
import FirebaseFirestore
import FirebaseAuth
#else
import SkipFirebaseFirestore
import SkipFirebaseAuth
#endif

/// Records on `users/{uid}.deviceStatus` the app version and permission states
/// of the device the user last opened the app on, for the admin dashboard's
/// user details. Rewritten each time the app comes to the front, since
/// permissions can change in system Settings while it is in the background.
@MainActor
final class DeviceStatusService {
  static let shared = DeviceStatusService()

  private init() {}

  func report() async {
	guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
	let permissions = PermissionService.shared
	let info = Bundle.main.infoDictionary
	let appVersion = info?["CFBundleShortVersionString"] as? String ?? ""
	let appBuild = info?["CFBundleVersion"] as? String ?? ""
	let microphone = permissions.captureStatus(for: .microphone).rawValue
	let camera = permissions.captureStatus(for: .camera).rawValue
	let notifications = await permissions.notificationStatus().rawValue
	let platform = Self.platform
	let deviceType = Self.deviceType
	let osVersion = Self.osVersion
	let deviceLanguage = LocalizationSupport.deviceLanguageTag
	let appLanguage = LocalizationSupport.currentLanguageCode
	let appLanguageSetting = LocalizationSupport.languagePreference
	// Built inside the closure: `[String: Any]` is not Sendable, so it can't be captured.
	await attempt {
	  let status: [String: Any] = [
		"platform": platform,
		"deviceType": deviceType,
		"osVersion": osVersion,
		"appVersion": appVersion,
		"appBuild": appBuild,
		"deviceLanguage": deviceLanguage,
		"appLanguage": appLanguage,
		"appLanguageSetting": appLanguageSetting,
		"microphone": microphone,
		"camera": camera,
		"notifications": notifications,
		"updatedAt": FieldValue.serverTimestamp(),
	  ]
	  try await Firestore.firestore().collection("users").document(uid)
		.setData(["deviceStatus": status], merge: true)
	}
	logger.info("[DeviceStatus] reported uid=\(uid) version=\(appVersion)")
  }

  private static var platform: String {
#if os(Android)
	"android"
#else
	"ios"
#endif
  }

  /// "iPhone", "iPad" or "Android" — the hardware family, finer than `platform`.
  private static var deviceType: String {
#if os(Android)
	"Android"
#else
	switch UIDevice.current.userInterfaceIdiom {
	case .pad: return "iPad"
	case .phone: return "iPhone"
	case .mac: return "Mac"
	case .vision: return "Apple Vision"
	case .tv: return "Apple TV"
	default: return "iOS"
	}
#endif
  }

  private static var osVersion: String {
	let v = ProcessInfo.processInfo.operatingSystemVersion
	return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
  }
}
