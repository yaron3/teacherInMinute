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
        Text(viewModel.introText)
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
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
    .navigationTitle(viewModel.screenTitle)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(viewModel.closeLabel) {
          dismiss()
        }
      }
    }
    .task {
      await viewModel.load()
    }
#if os(Android)
    .confirmationDialog(
      viewModel.addPhotoDialogTitle,
      isPresented: $showAndroidPhotoSourceDialog,
      titleVisibility: .visible
    ) {
      Button(viewModel.takePhotoLabel) {
        pickAndUploadAndroidImage(for: androidPickTarget, source: .camera)
      }
      Button(viewModel.chooseFromLibraryLabel) {
        pickAndUploadAndroidImage(for: androidPickTarget, source: .gallery)
      }
      Button(viewModel.cancelLabel, role: .cancel) {}
    }
#endif
  }

  func documentTile(_ document: TeacherDocument) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(document.title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(theme.primaryText)

      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(theme.cardBackground)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 320)
        .overlay {
          if document.url.isEmpty {
            VStack(spacing: 8) {
              PlatformIcon(systemName: "exclamationmark.triangle.fill", size: 22, color: theme.warning)
              Text(viewModel.documentLoadFailedText)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
            }
          } else {
            CachedRemoteImage(url: document.url, contentMode: .fit)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(theme.controlBorder, lineWidth: 1)
        }
    }
  }

  // MARK: - Missing documents

  @ViewBuilder
  var missingDocumentsSection: some View {
    if !viewModel.missingTargets.isEmpty {
      Text(viewModel.addMissingDocumentsTitle)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.primaryText)
        .padding(.top, 12)

      Text(viewModel.addMissingDocumentsHint)
        .font(.system(size: 12))
        .foregroundStyle(theme.secondaryText)
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
    return PhotoSourceButton(viewModel: viewModel, onImageData: { data in
      viewModel.handlePickedImage(data, for: target)
    }) {
      MissingDocumentRow(title: title,
                         isUploading: uploading,
                         statusLabel: uploading ? viewModel.uploadingLabel : viewModel.notUploadedYetLabel,
                         uploadLabel: viewModel.uploadLabel)
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
      MissingDocumentRow(title: title,
                         isUploading: uploading,
                         statusLabel: uploading ? viewModel.uploadingLabel : viewModel.notUploadedYetLabel,
                         uploadLabel: viewModel.uploadLabel)
    }
    .buttonStyle(.plain)
  }

  private func pickAndUploadAndroidImage(for target: UploadTarget, source: AndroidPhotoSource) {
    Task {
      do {
        if source == .camera {
          let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
          guard cameraState.isGranted else {
            viewModel.errorMessage = viewModel.cameraAccessRequiredMessage
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
        .tint(theme.accent)
      Text(viewModel.loadingText)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.secondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  func errorView(_ error: String) -> some View {
    VStack(spacing: 12) {
      Text(error)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.danger)
      Button {
        Task { await viewModel.load() }
      } label: {
        Text(viewModel.retryLabel)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.accent)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  var emptyView: some View {
    VStack(spacing: 12) {
      PlatformIcon(systemName: "doc.text", size: 28, color: theme.secondaryText)
      Text(viewModel.emptyStateText)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.secondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 200)
  }
}

// MARK: - MissingDocumentRow

struct MissingDocumentRow: View {
  let title: String
  let isUploading: Bool
  let statusLabel: String
  let uploadLabel: String

  nonisolated init(title: String, isUploading: Bool,
                   statusLabel: String, uploadLabel: String) {
    self.statusLabel = statusLabel
    self.uploadLabel = uploadLabel
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
        .fill(theme.accentBackground)
        .frame(width: 42, height: 42)
        .overlay {
          if isUploading {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(theme.accent)
          } else {
            PlatformIcon(systemName: "arrow.up.doc.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(theme.accent)
          }
        }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.primaryText)
        Text(statusLabel)
          .font(.system(size: 12))
          .foregroundStyle(theme.secondaryText)
      }

      Spacer()

      if !isUploading {
        Text(uploadLabel)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.onAccentText)
          .padding(.horizontal, 14)
          .frame(height: 32)
          .background(theme.accent)
          .clipShape(Capsule())
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity)
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        .foregroundStyle(theme.controlBorder)
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
