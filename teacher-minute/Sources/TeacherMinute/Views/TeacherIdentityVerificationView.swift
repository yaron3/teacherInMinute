//
//  TeacherIdentityVerificationView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
#if !os(Android)
@preconcurrency import PhotosUI
#else
import SkipBridge
#endif

@MainActor
struct TeacherIdentityVerificationView: View {
  @State var viewModel = TeacherIdentityVerificationViewModel()
  @Environment(\.appRouter) var router
  
#if !os(Android)
  // Separate state per slot — fixes back-side onChange not firing when same item reused
  @State private var credentialsItem: PhotosPickerItem?
  @State private var idFrontItem:     PhotosPickerItem?
  @State private var idBackItem:      PhotosPickerItem?
  @State private var selfieItem:      PhotosPickerItem?
#endif
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  ScrollView {
		VStack(alignment: .leading, spacing: 0) {
		  Text(LocalizationSupport.localized("Step 1 of 2"))
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(theme.authSecondaryText)
			.frame(maxWidth: .infinity)
		  
		  Text(LocalizationSupport.localized("Verify Your Identity"))
			.font(.system(size: 26, weight: .bold))
			.foregroundStyle(theme.authPrimaryText)
			.padding(.top, 20)
		  
		  Text(LocalizationSupport.localized("To maintain a high-quality learning environment,\nwe need to verify your teaching credentials and\nidentity."))
			.font(.system(size: 13))
			.foregroundStyle(theme.authSecondaryText)
			.lineSpacing(5)
			.padding(.top, 8)
		  
		  verificationStatus
			.padding(.top, 20)
		  
		  sectionTitle(LocalizationSupport.localized("Teaching Credentials"))
			.padding(.top, 22)
		  
		  Text(LocalizationSupport.localized("Upload your degree, teaching license, or relevant\ncertifications."))
			.font(.system(size: 11))
			.foregroundStyle(theme.authSecondaryText)
			.lineSpacing(4)
			.padding(.top, 8)
		  
#if !os(Android)
		  let hasCredentials      = viewModel.hasTeachingCredentials
		  let credentialsSpinning = viewModel.isUploading(for: .teachingCredentials)
		  PhotosPicker(selection: $credentialsItem,
					   matching: .any(of: [.images, .livePhotos])) {
			UploadLargeBox(
			  title: LocalizationSupport.localized("Tap to upload document"),
			  subtitle: LocalizationSupport.localized("PDF, JPG or PNG (Max 5MB)"),
			  icon: "icloud.and.arrow.up.fill",
			  isCompleted: hasCredentials,
			  isUploading: credentialsSpinning,
			  action: {}
			)
		  }
					   .onChange(of: credentialsItem) { _, item in
						 MainActor.assumeIsolated {
						   loadAndUpload(item, for: .teachingCredentials)
						 }
					   }
					   .padding(.top, 12)
#else
			  Button {
				pickAndUploadAndroidImage(for: .teachingCredentials)
			  } label: {
				credentialsPickerLabel
			  }
			  .buttonStyle(.plain)
#endif
		  
		  sectionTitle(LocalizationSupport.localized("Government ID"))
			.padding(.top, 22)
		  
		  Text(LocalizationSupport.localized("Upload a clear photo of your passport, driver's license,\nor national ID."))
			.font(.system(size: 11))
			.foregroundStyle(theme.authSecondaryText)
			.lineSpacing(4)
			.padding(.top, 8)
		  
		  HStack(spacing: 12) {
#if !os(Android)
			let hasFront      = viewModel.hasGovernmentIDFront
			let frontSpinning = viewModel.isUploading(for: .governmentIDFront)
			let hasBack       = viewModel.hasGovernmentIDBack
			let backSpinning  = viewModel.isUploading(for: .governmentIDBack)
			PhotosPicker(selection: $idFrontItem, matching: .images) {
			  IDUploadBox(
				title: LocalizationSupport.localized("Front Side"),
				isCompleted: hasFront,
				isUploading: frontSpinning,
				isMandatory: true,
				action: {}
			  )
			}
			.onChange(of: idFrontItem) { _, item in
			  MainActor.assumeIsolated { loadAndUpload(item, for: .governmentIDFront) }
			}
			
			PhotosPicker(selection: $idBackItem, matching: .images) {
			  IDUploadBox(
				title: LocalizationSupport.localized("Back Side"),
				isCompleted: hasBack,
				isUploading: backSpinning,
				isMandatory: false,
				action: {}
			  )
			}
			.onChange(of: idBackItem) { _, item in
			  MainActor.assumeIsolated { loadAndUpload(item, for: .governmentIDBack) }
			}
#else
				Button {
				  pickAndUploadAndroidImage(for: .governmentIDFront)
				} label: {
				  idFrontPickerLabel
				}
				.buttonStyle(.plain)
				
				Button {
				  pickAndUploadAndroidImage(for: .governmentIDBack)
				} label: {
				  idBackPickerLabel
				}
				.buttonStyle(.plain)
#endif
		  }
		  .padding(.top, 12)
		  
		  sectionTitle(LocalizationSupport.localized("Selfie Verification"))
			.padding(.top, 22)
		  
		  Text(LocalizationSupport.localized("Take a clear selfie to match with your Government ID."))
			.font(.system(size: 11))
			.foregroundStyle(theme.authSecondaryText)
			.padding(.top, 8)
		  
#if !os(Android)
		  let hasSelfie      = viewModel.hasSelfie
		  let selfieSpinning = viewModel.isUploading(for: .selfie)
		  PhotosPicker(selection: $selfieItem, matching: .images) {
			SelfieRow(
			  isCompleted: hasSelfie,
			  isUploading: selfieSpinning,
			  action: {}
			)
		  }
		  .onChange(of: selfieItem) { _, item in
			MainActor.assumeIsolated {
			  loadAndUpload(item, for: .selfie)
			}
		  }
		  .padding(.top, 12)
#else
			  Button {
				pickAndUploadAndroidImage(for: .selfie)
			  } label: {
				selfiePickerLabel
			  }
			  .buttonStyle(.plain)
#endif
		  
		  privacyBox
			.padding(.top, 24)
		  
		  termsCheckbox
			.padding(.top, 22)
		  
		  if let err = viewModel.uploadError {
			Text(err)
			  .font(.system(size: 12))
			  .foregroundStyle(.red)
			  .padding(.top, 8)
		  }
		  
		  // Hint when terms not accepted or front side missing
		  if !viewModel.canSubmit && viewModel.uploadingTarget == nil {
			Text(viewModel.hasGovernmentIDFront
				 ? LocalizationSupport.localized("Accept the terms to continue")
				 : LocalizationSupport.localized("Upload the front side of your ID to continue"))
			.font(.system(size: 11))
			.foregroundStyle(theme.authOrange)
			.padding(.top, 8)
		  }
		  
		  AuthPrimaryButton(
			title: LocalizationSupport.localized("Submit for Review"),
			systemImage: "arrow.right",
			isEnabled: viewModel.canSubmit
		  ) {
			Task { @MainActor in
			  viewModel.submitForReview()
			}
		  }
		  .padding(.top, 24)
		  .padding(.bottom, 24)
		}
		.padding(.horizontal, 18)
	  }
	  .background(Color(.systemBackground))
	  
	  // Full-screen spinner while checking Firestore on appear
	  if viewModel.isCheckingCompletion {
		theme.appPrimaryText.opacity(0.25).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(theme.appPrimaryText)
		  Text(LocalizationSupport.localized("Checking…"))
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(theme.appPrimaryText)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	.onAppear {
	  viewModel.onSubmit = { router.push(.teacherSubjects) }
	  viewModel.checkAndAutoAdvance()
	}
  }
  
  // MARK: - Picker label helpers (Android / preview)
  var credentialsPickerLabel: some View {
	UploadLargeBox(
	  title: LocalizationSupport.localized("Tap to upload document"),
	  subtitle: LocalizationSupport.localized("PDF, JPG or PNG (Max 5MB)"),
	  icon: "icloud.and.arrow.up.fill",
	  isCompleted: viewModel.hasTeachingCredentials,
	  isUploading: viewModel.isUploading(for: .teachingCredentials),
	  action: {}
	)
  }
  
  var idFrontPickerLabel: some View {
	IDUploadBox(title: LocalizationSupport.localized("Front Side"), isCompleted: viewModel.hasGovernmentIDFront,
				isUploading: viewModel.isUploading(for: .governmentIDFront),
				isMandatory: true, action: {})
  }
  
  var idBackPickerLabel: some View {
	IDUploadBox(title: LocalizationSupport.localized("Back Side"), isCompleted: viewModel.hasGovernmentIDBack,
				isUploading: viewModel.isUploading(for: .governmentIDBack),
				isMandatory: false, action: {})
  }
  
  var selfiePickerLabel: some View {
	SelfieRow(isCompleted: viewModel.hasSelfie,
			  isUploading: viewModel.isUploading(for: .selfie), action: {})
  }
  
  // MARK: - Load PhotosPickerItem → Data → upload
#if !os(Android)
  private func loadAndUpload(_ item: PhotosPickerItem?, for target: UploadTarget) {
	guard let item else { return }
	Task {
	  if let data = try? await item.loadTransferable(type: Data.self) {
		viewModel.handlePickedImage(data, for: target)
	  }
	}
  }
#else
  private func pickAndUploadAndroidImage(for target: UploadTarget) {
	Task {
	  do {
		print("TeacherMinute Android image pick requested target=\(target)")
		let base64 = try await Task.detached(priority: .userInitiated) {
		  try AndroidImagePickerBridge.pickImageBase64()
		}.value
		print("TeacherMinute Android image pick returned target=\(target) base64Length=\(base64.count)")
		guard !base64.isEmpty else {
		  print("TeacherMinute Android image pick cancelled target=\(target)")
		  return
		}
		guard let data = Data(base64Encoded: base64) else {
		  viewModel.uploadError = LocalizationSupport.localized("Could not read selected image")
		  return
		}
		print("TeacherMinute Android image decoded target=\(target) bytes=\(data.count)")
		viewModel.handlePickedImage(data, for: target)
	  } catch {
		print("TeacherMinute Android image pick failed target=\(target) error=\(error)")
		viewModel.uploadError = error.localizedDescription
	  }
	}
  }
#endif
  
  // MARK: - Sub-views
  var verificationStatus: some View {
	VStack(alignment: .leading, spacing: 14) {
	  HStack {
		Text(LocalizationSupport.localized("VERIFICATION STATUS"))
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.authPrimaryText)
		Spacer()
		Text(viewModel.canSubmit ? LocalizationSupport.localized("Ready") : LocalizationSupport.localized("Incomplete"))
		  .font(.system(size: 11, weight: .medium))
		  .foregroundStyle(viewModel.canSubmit ? theme.authGreen : theme.authOrange)
		  .padding(.horizontal, 10)
		  .frame(height: 22)
		  .background((viewModel.canSubmit ? theme.authGreen : theme.authOrange).opacity(0.12))
		  .clipShape(Capsule())
	  }
	  StatusRow(title: LocalizationSupport.localized("Teaching Credentials"), isDone: viewModel.hasTeachingCredentials, isMandatory: false)
	  StatusRow(title: LocalizationSupport.localized("Government ID – Front"), isDone: viewModel.hasGovernmentIDFront, isMandatory: true)
	  StatusRow(title: LocalizationSupport.localized("Government ID – Back"),  isDone: viewModel.hasGovernmentIDBack,  isMandatory: false)
	  StatusRow(title: LocalizationSupport.localized("Selfie Verification"),   isDone: viewModel.hasSelfie,            isMandatory: false)
	}
	.padding(16)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	.shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
  }
  
  var privacyBox: some View {
	HStack(alignment: .top, spacing: 12) {
	  PlatformIcon(
		systemName: "shield.lefthalf.filled",
		size: 18,
		weight: .semibold,
		color: theme.authPurple
	  )
	  VStack(alignment: .leading, spacing: 6) {
		Text(LocalizationSupport.localized("Your Privacy Matters"))
		  .font(.system(size: 13, weight: .bold))
		  .foregroundStyle(theme.authPrimaryText)
		Text(LocalizationSupport.localized("Your documents are securely encrypted and\nonly used for verification purposes. They will\nnot be shared publicly on your profile."))
		  .font(.system(size: 11))
		  .foregroundStyle(theme.authSecondaryText)
		  .lineSpacing(4)
	  }
	  Spacer()
	}
	.padding(16)
	.background(theme.authPurpleSoft.opacity(0.45))
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
  
  var termsCheckbox: some View {
	Button {
	  viewModel.acceptedTerms.toggle()
	} label: {
	  HStack(alignment: .top, spacing: 10) {
		PlatformIcon(systemName: viewModel.acceptedTerms ? "checkmark.square.fill" : "square")
		  .font(.system(size: 18))
		  .foregroundStyle(viewModel.acceptedTerms ? theme.authPink : theme.authIcon)
		Text(LocalizationSupport.localized("I confirm that the uploaded documents are\nauthentic and belong to me. I agree to the\nVerification Terms."))
		  .font(.system(size: 11))
		  .foregroundStyle(theme.authSecondaryText)
		  .lineSpacing(4)
		  .multilineTextAlignment(.leading)
		Spacer()
	  }
	}
	.buttonStyle(.plain)
  }
  
  func sectionTitle(_ title: String) -> some View {
	Text(title)
	  .font(.system(size: 15, weight: .bold))
	  .foregroundStyle(theme.authPrimaryText)
  }
}

// MARK: - StatusRow

struct StatusRow: View {
  let title: String
  let isDone: Bool
  let isMandatory: Bool
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	HStack(spacing: 12) {
	  Circle()
		.fill(theme.authFieldBorder)
		.frame(width: 18, height: 18)
		.overlay {
		  PlatformIcon(systemName: isDone ? "checkmark" : "circle.fill")
			.font(.system(size: 8, weight: .bold))
			.foregroundStyle(isDone ? theme.authGreen : theme.authIcon)
		}
	  
	  Text(title)
		.font(.system(size: 12))
		.foregroundStyle(theme.authSecondaryText)
	  
	  if isMandatory && !isDone {
		Text(LocalizationSupport.localized("required"))
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(theme.authOrange)
		  .padding(.horizontal, 6)
		  .padding(.vertical, 2)
		  .background(theme.authOrange.opacity(0.12))
		  .clipShape(Capsule())
	  }
	  
	  Spacer()
	  
	  Circle()
		.fill(isDone ? theme.authGreen : theme.authOrange)
		.frame(width: 10, height: 10)
		.overlay {
		  if !isDone {
			Text("!")
			  .font(.system(size: 7, weight: .bold))
			  .foregroundStyle(theme.appPrimaryText)
		  }
		}
	}
  }
}

// MARK: - UploadLargeBox

struct UploadLargeBox: View {
  let title: String
  let subtitle: String
  let icon: String
  let isCompleted: Bool
  let isUploading: Bool
  
  nonisolated init(title: String, subtitle: String, icon: String,
				   isCompleted: Bool, isUploading: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.title = title
	self.subtitle = subtitle
	self.icon = icon
	self.isCompleted = isCompleted
	self.isUploading = isUploading
	
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	VStack(spacing: 10) {
	  Circle()
		.fill(theme.authPinkSoft)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.authPink)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : icon)
			  .font(.system(size: 16, weight: .bold))
			  .foregroundStyle(isCompleted ? theme.authGreen : theme.authPink)
		  }
		}
	  
	  Text(isUploading ? LocalizationSupport.localized("Uploading…") : title)
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(theme.authPrimaryText)
	  
	  Text(subtitle)
		.font(.system(size: 10))
		.foregroundStyle(theme.authSecondaryText)
	}
	.frame(maxWidth: .infinity)
	.frame(height: 116)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(theme.authFieldBorder)
	}
  }
}

// MARK: - IDUploadBox

struct IDUploadBox: View {
  let title: String
  let isCompleted: Bool
  let isUploading: Bool
  let isMandatory: Bool
  
  nonisolated init(title: String, isCompleted: Bool,
				   isUploading: Bool = false, isMandatory: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.title = title
	self.isCompleted = isCompleted
	self.isUploading = isUploading
	self.isMandatory = isMandatory
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	VStack(spacing: 8) {
	  Circle()
		.fill(theme.authPurpleSoft)
		.frame(width: 36, height: 36)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.authPurple)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : "person.text.rectangle")
			  .font(.system(size: 14, weight: .semibold))
			  .foregroundStyle(isCompleted ? theme.authGreen : theme.authPurple)
		  }
		}
	  
	  Text(isUploading ? LocalizationSupport.localized("Uploading…") : title)
		.font(.system(size: 12, weight: .medium))
		.foregroundStyle(theme.authPrimaryText)
	  
	  if isMandatory && !isCompleted && !isUploading {
		Text(LocalizationSupport.localized("required"))
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(theme.authOrange)
		  .padding(.horizontal, 5)
		  .padding(.vertical, 2)
		  .background(theme.authOrange.opacity(0.12))
		  .clipShape(Capsule())
	  }
	}
	.frame(maxWidth: .infinity)
	.frame(height: 90)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(isMandatory && !isCompleted ? theme.authOrange.opacity(0.5) : theme.authFieldBorder)
	}
  }
}

// MARK: - SelfieRow

struct SelfieRow: View {
  let isCompleted: Bool
  let isUploading: Bool
  
  nonisolated init(isCompleted: Bool, isUploading: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.isCompleted = isCompleted
	self.isUploading = isUploading
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	HStack(spacing: 14) {
	  RoundedRectangle(cornerRadius: 12, style: .continuous)
		.fill(theme.authFieldBackground)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.authPrimaryText)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : "camera.fill")
			  .foregroundStyle(isCompleted ? theme.authGreen : theme.authPrimaryText)
		  }
		}
	  
	  VStack(alignment: .leading, spacing: 4) {
		Text(isUploading ? LocalizationSupport.localized("Uploading selfie…") : LocalizationSupport.localized("Take Selfie"))
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(theme.authPrimaryText)
		
		Text(LocalizationSupport.localized("Ensure good lighting"))
		  .font(.system(size: 11))
		  .foregroundStyle(theme.authSecondaryText)
	  }
	  
	  Spacer()
	  
	  PlatformIcon(
		systemName: "chevron.right",
		size: 12,
		weight: .semibold,
		color: theme.authIcon
	  )
	}
	.padding(14)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 16, style: .continuous)
		.stroke(theme.authFieldBorder, lineWidth: 1)
	}
  }
}

#if os(Android)
private enum AndroidImagePickerBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidImagePickerManager")
  private static let pickImageBase64Method = managerClass.getStaticMethodID(
	name: "pickImageBase64",
	sig: "()Ljava/lang/String;"
  )!

  static func pickImageBase64() throws -> String {
	try jniContext {
	  try managerClass.callStatic(
		method: pickImageBase64Method,
		options: [.kotlincompat],
		args: []
	  )
	}
  }
}
#endif


#if os(ios)
#Preview {
  termsCheckbox()
}
#endif
