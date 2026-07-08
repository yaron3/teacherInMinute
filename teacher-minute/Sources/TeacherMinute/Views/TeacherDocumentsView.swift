//
//  TeacherDocumentsView.swift
//  teacher-minute
//

import SwiftUI
#if !os(Android)
@preconcurrency import PhotosUI
#else
import SkipBridge
#endif

@MainActor
struct TeacherDocumentsView: View {
  @State var viewModel = TeacherDocumentsViewModel()
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var colorScheme
#if os(Android)
  // Camera-vs-gallery chooser state for the Android upload flow.
  @State var showAndroidPhotoSourceDialog = false
  @State var androidPickTarget: UploadTarget = .governmentIDFront
#endif
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 16) {
        Text(LocalizationSupport.localized("These are the verification documents you uploaded."))
          .font(.system(size: 13))
          .foregroundStyle(theme.appSecondaryText)
          .lineSpacing(4)
          .padding(.top, 8)

        if viewModel.isLoading {
          loadingView
        } else if let error = viewModel.errorMessage {
          errorView(error)
        } else {
          if viewModel.hasDocuments {
            ForEach(viewModel.documents) { document in
              documentTile(document)
            }
          } else {
            emptyView
          }

          missingDocumentsSection
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(.systemBackground))
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle(LocalizationSupport.localized("Documents Uploaded"))
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(LocalizationSupport.localized("Close")) {
          dismiss()
        }
      }
    }
    .task {
      await viewModel.load()
    }
#if os(Android)
    .confirmationDialog(
      LocalizationSupport.localized("Add a photo"),
      isPresented: $showAndroidPhotoSourceDialog,
      titleVisibility: .visible
    ) {
      Button(LocalizationSupport.localized("Take Photo")) {
        pickAndUploadAndroidImage(for: androidPickTarget, source: .camera)
      }
      Button(LocalizationSupport.localized("Choose from Library")) {
        pickAndUploadAndroidImage(for: androidPickTarget, source: .gallery)
      }
      Button(LocalizationSupport.localized("Cancel"), role: .cancel) {}
    }
#endif
  }

  func documentTile(_ document: TeacherDocument) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(document.title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(theme.appPrimaryText)

      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(theme.appGrayBackground)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 320)
        .overlay {
          if document.url.isEmpty {
            VStack(spacing: 8) {
              PlatformIcon(systemName: "exclamationmark.triangle.fill", size: 22, color: theme.appOrange)
              Text(LocalizationSupport.localized("Could not load this document."))
                .font(.system(size: 12))
                .foregroundStyle(theme.appSecondaryText)
            }
          } else {
            CachedRemoteImage(url: document.url, contentMode: .fit)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(theme.appBorder, lineWidth: 1)
        }
    }
  }

  // MARK: - Missing documents

  @ViewBuilder
  var missingDocumentsSection: some View {
    if !viewModel.missingTargets.isEmpty {
      Text(LocalizationSupport.localized("Add missing documents"))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.appPrimaryText)
        .padding(.top, 12)

      Text(LocalizationSupport.localized("Uploading the remaining documents helps us verify you as a teacher faster."))
        .font(.system(size: 12))
        .foregroundStyle(theme.appSecondaryText)
        .lineSpacing(4)

#if !os(Android)
      if viewModel.isMissing(.governmentIDFront) { uploadPicker(.governmentIDFront) }
      if viewModel.isMissing(.governmentIDBack)  { uploadPicker(.governmentIDBack) }
      if viewModel.isMissing(.teachingCredentials) { uploadPicker(.teachingCredentials) }
      if viewModel.isMissing(.selfie)            { uploadPicker(.selfie) }
#else
      if viewModel.isMissing(.governmentIDFront) { uploadButton(.governmentIDFront) }
      if viewModel.isMissing(.governmentIDBack)  { uploadButton(.governmentIDBack) }
      if viewModel.isMissing(.teachingCredentials) { uploadButton(.teachingCredentials) }
      if viewModel.isMissing(.selfie)            { uploadButton(.selfie) }
#endif
    }
  }

#if !os(Android)
  func uploadPicker(_ target: UploadTarget) -> some View {
    let title = viewModel.title(for: target)
    let uploading = viewModel.isUploading(target)
    return PhotoSourceButton(onImageData: { data in
      viewModel.handlePickedImage(data, for: target)
    }) {
      MissingDocumentRow(title: title, isUploading: uploading)
    }
  }
#else
  enum AndroidPhotoSource {
    case camera
    case gallery
  }

  func uploadButton(_ target: UploadTarget) -> some View {
    let title = viewModel.title(for: target)
    let uploading = viewModel.isUploading(target)
    return Button {
      androidPickTarget = target
      showAndroidPhotoSourceDialog = true
    } label: {
      MissingDocumentRow(title: title, isUploading: uploading)
    }
    .buttonStyle(.plain)
  }

  private func pickAndUploadAndroidImage(for target: UploadTarget, source: AndroidPhotoSource) {
    Task {
      do {
        if source == .camera {
          let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
          guard cameraState.isGranted else {
            viewModel.errorMessage = LocalizationSupport.localized("Camera access is required to take a photo.")
            return
          }
        }
        let base64 = try await Task.detached(priority: .userInitiated) {
          switch source {
          case .camera:  return try AndroidDocumentImagePickerBridge.captureImageBase64()
          case .gallery: return try AndroidDocumentImagePickerBridge.pickImageBase64()
          }
        }.value
        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return }
        viewModel.handlePickedImage(data, for: target)
      } catch {
        viewModel.errorMessage = error.localizedDescription
      }
    }
  }
#endif

  // MARK: - States

  var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(theme.appPink)
      Text(LocalizationSupport.localized("Loading documents..."))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.appSecondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  func errorView(_ error: String) -> some View {
    VStack(spacing: 12) {
      Text(error)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.red)
      Button {
        Task { await viewModel.load() }
      } label: {
        Text(LocalizationSupport.localized("Retry"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.appPink)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  var emptyView: some View {
    VStack(spacing: 12) {
      PlatformIcon(systemName: "doc.text", size: 28, color: theme.appSecondaryText)
      Text(LocalizationSupport.localized("No documents uploaded yet."))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.appSecondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 200)
  }
}

// MARK: - MissingDocumentRow

struct MissingDocumentRow: View {
  let title: String
  let isUploading: Bool

  nonisolated init(title: String, isUploading: Bool) {
    self.title = title
    self.isUploading = isUploading
  }

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 14) {
      Circle()
        .fill(theme.appPinkSoft)
        .frame(width: 42, height: 42)
        .overlay {
          if isUploading {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(theme.appPink)
          } else {
            PlatformIcon(systemName: "arrow.up.doc.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(theme.appPink)
          }
        }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)
        Text(isUploading
             ? LocalizationSupport.localized("Uploading…")
             : LocalizationSupport.localized("Not uploaded yet"))
          .font(.system(size: 12))
          .foregroundStyle(theme.appSecondaryText)
      }

      Spacer()

      if !isUploading {
        Text(LocalizationSupport.localized("Upload"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.white)
          .padding(.horizontal, 14)
          .frame(height: 32)
          .background(theme.appPink)
          .clipShape(Capsule())
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity)
    .background(theme.appCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        .foregroundStyle(theme.appBorder)
    }
  }
}

#if os(Android)
private enum AndroidDocumentImagePickerBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidImagePickerManager")
  private static let pickImageBase64Method = managerClass.getStaticMethodID(
    name: "pickImageBase64",
    sig: "()Ljava/lang/String;"
  )!
  private static let captureImageBase64Method = managerClass.getStaticMethodID(
    name: "captureImageBase64",
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

  static func captureImageBase64() throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: captureImageBase64Method,
        options: [.kotlincompat],
        args: []
      )
    }
  }
}
#endif
