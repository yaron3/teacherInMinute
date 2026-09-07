//
//  AskTeacherSheet.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 17/05/2026.
//


// MARK: - Ask Teacher Sheet
import SwiftUI
#if !os(Android)
@preconcurrency import PhotosUI
import FirebaseAuth
#else
import SkipBridge
import SkipFirebaseAuth
#endif

struct AskTeacherSheet: View {
    let viewModel: any StudentHomeViewModeling

    static let topics = [("Algebra"), ("Geometry"), ("Trigonometry"), ("Calculus"), ("Statistics"), ("Arithmetic")]
    static let maxPhotoCount = 4
    static let mathSymbolsRow1 = ["≥", "≠", "÷", "×", "±", "π", "³", "²", "√"]
    static let mathSymbolsRow2 = ["xⁿ", "¾", "½", "¼", "Σ", "∞", "≤"]

    init(viewModel: any StudentHomeViewModeling) {
        self.viewModel = viewModel
        // The default session type is configurable in Settings and defaults to
        // an audio call when the student has not chosen otherwise.
        let stored = UserDefaults.standard.string(forKey: SessionPreferences.defaultQuestionTypeKey)
        _conversationType = State(initialValue: stored ?? ConversationType.audio.rawValue)
    }

    @State  var selectedTopic = ("Algebra")
    @State  var questionText = ""
    @State  var conversationType: String
    @State  var permissionAlertMessage: String? = nil
    @State  var isRequestingPermission = false
    @State  var uploadedPhotoUrls: [String] = []
    @State  var isUploadingPhoto = false
    @State  var photoUploadError: String? = nil
#if os(Android)
    @State  var showAndroidPhotoSourceDialog = false
#endif
    @FocusState var isQuestionFocused: Bool
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
    @Environment(\.dismiss) var dismiss
  private var canSubmit: Bool {
    questionText.trimmingCharacters(in: .whitespaces).count >= 10
      || !uploadedPhotoUrls.isEmpty
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  private var sheetSpacing: CGFloat {
#if os(Android)
    12
#else
    20
#endif
  }

  private var sectionSpacing: CGFloat {
#if os(Android)
    7
#else
    10
#endif
  }

  private var sheetPadding: CGFloat {
#if os(Android)
    8
#else
    10
#endif
  }

  private var editorMinHeight: CGFloat {
#if os(Android)
    120
#else
    120
#endif
  }

  private var findButtonHeight: CGFloat {
#if os(Android)
    46
#else
    52
#endif
  }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView(.vertical, showsIndicators: false) {
			  VStack(alignment: .leading, spacing: sheetSpacing) {
			VStack(alignment: .leading, spacing: sectionSpacing) {
                    Text(viewModel.sessionTypeSectionTitle)
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.primaryText)

                    HStack(spacing: 10) {
                        ConversationTypeChip(
                            title: viewModel.textSessionTypeLabel,
                            isSelected: conversationType == "text",
                            systemIcons: ["bubble.left.fill"],
                            accent: .teal
                        ) {
                            conversationType = "text"
                        }
                        ConversationTypeChip(
                            title: viewModel.audioSessionTypeLabel,
                            isSelected: conversationType == "audio",
                            systemIcons: ["mic.fill"],
                            accent: .teal
                        ) {
                            conversationType = "audio"
                        }
                        ConversationTypeChip(
                            title: viewModel.videoSessionTypeLabel,
                            isSelected: conversationType == "video",
                            systemIcons: ["video.fill"],
                            accent: .teal
                        ) {
                            conversationType = "video"
                        }
                    }
					.frame(maxWidth: .infinity, alignment: .leading)
                }

			VStack(alignment: .leading, spacing: sectionSpacing) {
                    Text(viewModel.topicSectionTitle)
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.primaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AskTeacherSheet.topics, id: \.self) { topic in
                                Button {
                                    selectedTopic = topic
                                } label: {
                                    Text(viewModel.localizedTopicName(topic))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selectedTopic == topic ? theme.onAccentText : theme.primaryText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedTopic == topic ? theme.accent : theme.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
						.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

			  VStack(alignment: .leading, spacing: sectionSpacing) {
                    Text(viewModel.yourQuestionSectionTitle)
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.primaryText)

                    TextEditor(text: $questionText)
                        .focused($isQuestionFocused)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(theme.primaryText)
                        .tint(theme.accent)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: editorMinHeight, alignment: .leading)
                        .background(theme.fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // The primary "Find me a Teacher Now" button sits below the
                    // photo and info sections, off-screen while the keyboard is
                    // up. This second entry point rides alongside the character
                    // counter so the question can be sent without dismissing it.
                    HStack(spacing: 10) {
                        if uploadedPhotoUrls.isEmpty {
                            Text(viewModel.minimumCharactersText(count: questionText.count))
                                .font(.system(size: 11))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(canSubmit ? theme.positive : theme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        let isSendDisabled = !canSubmit || isRequestingPermission
                        Button {
                            Task { await findTeacherTapped() }
                        } label: {
                            Text(viewModel.sendLabel)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isSendDisabled ? theme.secondaryText : theme.onAccentText)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(isSendDisabled ? theme.cardBackground : theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .opacity(isSendDisabled ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSendDisabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                mathSymbolsSection

                photoAttachmentSection

                infoCard

                let isFindDisabled = !canSubmit || isRequestingPermission
                Button {
                    Task { await findTeacherTapped() }
                } label: {
                    Text(viewModel.findTeacherNowLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isFindDisabled ? theme.secondaryText : theme.onAccentText)
                        .frame(maxWidth: .infinity)
                        .frame(height: findButtonHeight)
                        .background(isFindDisabled ? theme.cardBackground : theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(isFindDisabled ? 0.6 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isFindDisabled)

                footerText
            }
            .padding(sheetPadding)
        }
        .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle(viewModel.askATeacherSheetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.cancelLabel) { closeAskTeacher() }
            }
        }
        .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
        .id(languagePreference)
        .task {
            isQuestionFocused = true
        }
        .trackScreen(AnalyticsScreen.askTeacherSheet)
        .appDialog(
            viewModel.permissionRequiredTitle,
            isPresented: Binding(
                get: { permissionAlertMessage != nil },
                set: { if !$0 { permissionAlertMessage = nil } }
            ),
            message: permissionAlertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
    }

    func findTeacherTapped() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        if conversationType == "audio" || conversationType == "video" {
            let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
            if !micState.isGranted {
                permissionAlertMessage = conversationType == "video"
                    ? viewModel.videoPermissionRequiredMessage
                    : viewModel.audioPermissionRequiredMessage
                return
            }
        }

        if conversationType == "video" {
            let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
            if !cameraState.isGranted {
                permissionAlertMessage = viewModel.videoPermissionRequiredMessage
                return
            }
        }

        closeAskTeacher()
        await viewModel.askTeacher(
            topic: selectedTopic.lowercased(),
            text: questionText.trimmingCharacters(in: .whitespaces),
            photoUrls: uploadedPhotoUrls,
            conversationType: conversationType
        )
    }

    var photoAttachmentSection: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(viewModel.attachPhotoSectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.primaryText)

            if uploadedPhotoUrls.isEmpty {
                largeAddPhotoButton
            } else {
                HStack(spacing: 10) {
                    ForEach(uploadedPhotoUrls, id: \.self) { url in
                        photoThumbnail(url: url)
                    }

                    if uploadedPhotoUrls.count < AskTeacherSheet.maxPhotoCount {
                        addPhotoButton
                    }

                    Spacer(minLength: 0)
                }
            }

            if let photoUploadError {
                Text(photoUploadError)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    var addPhotoButton: some View {
#if !os(Android)
        PhotoSourceButton(onImageData: { data in
            uploadPhotoData(data)
        }) {
            addPhotoLabel
        }
        .disabled(isUploadingPhoto)
#else
        Button {
            showAndroidPhotoSourceDialog = true
        } label: {
            addPhotoLabel
        }
        .buttonStyle(.plain)
        .disabled(isUploadingPhoto)
        .confirmationDialog(
            viewModel.addPhotoDialogTitle,
            isPresented: $showAndroidPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button(viewModel.takePhotoLabel) {
                pickAndroidPhoto(source: .camera)
            }
            Button(viewModel.chooseFromLibraryLabel) {
                pickAndroidPhoto(source: .gallery)
            }
            Button(viewModel.cancelLabel, role: .cancel) {}
        }
#endif
    }

    @ViewBuilder
    var largeAddPhotoButton: some View {
#if !os(Android)
        PhotoSourceButton(onImageData: { data in
            uploadPhotoData(data)
        }) {
            largeAddPhotoLabel
        }
        .disabled(isUploadingPhoto)
#else
        Button {
            showAndroidPhotoSourceDialog = true
        } label: {
            largeAddPhotoLabel
        }
        .buttonStyle(.plain)
        .disabled(isUploadingPhoto)
        .confirmationDialog(
            viewModel.addPhotoDialogTitle,
            isPresented: $showAndroidPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button(viewModel.takePhotoLabel) {
                pickAndroidPhoto(source: .camera)
            }
            Button(viewModel.chooseFromLibraryLabel) {
                pickAndroidPhoto(source: .gallery)
            }
            Button(viewModel.cancelLabel, role: .cancel) {}
        }
#endif
    }

    var largeAddPhotoLabel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.controlBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(maxWidth: .infinity)
                .frame(height: 90)

            if isUploadingPhoto {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(theme.secondaryText)
            } else {
                VStack(spacing: 6) {
                    PlatformIcon(systemName: "camera.fill", size: 20, weight: .semibold, color: theme.secondaryText)
                    Text(viewModel.tapToUploadPhotoText)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    var addPhotoLabel: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.cardBackground)
            .frame(width: 64, height: 64)
            .overlay {
                if isUploadingPhoto {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.primaryText)
                } else {
                    PlatformIcon(systemName: "camera.fill", size: 20, weight: .semibold, color: theme.secondaryText)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.controlBorder, lineWidth: 1)
            }
    }

    func photoThumbnail(url: String) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardBackground)
                .frame(width: 64, height: 64)
                .overlay {
                    CachedRemoteImage(url: url, contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.controlBorder, lineWidth: 1)
                }

            Button {
                removePhoto(url: url)
            } label: {
                Circle()
                    .fill(theme.primaryText.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .overlay {
                        PlatformIcon(systemName: "xmark", size: 10, weight: .bold, color: theme.invertedText)
                    }
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    func removePhoto(url: String) {
        uploadedPhotoUrls.removeAll { $0 == url }
    }

#if !os(Android)
    func uploadPhotoData(_ data: Data) {
        Task {
            do {
                isUploadingPhoto = true
                photoUploadError = nil
                defer { isUploadingPhoto = false }
                guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
                    photoUploadError = viewModel.signInToAttachPhotoError
                    return
                }
                let url = try await StorageService.shared.uploadQuestionImage(data: data, uid: uid)
                uploadedPhotoUrls.append(url)
            } catch {
                logger.error("AskTeacherSheet photo upload failed: \(error.localizedDescription)")
                photoUploadError = error.localizedDescription
            }
        }
    }
#else
    enum AndroidPhotoSource {
        case camera
        case gallery
    }

    func pickAndroidPhoto(source: AndroidPhotoSource) {
        Task {
            if source == .camera {
                let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
                guard cameraState.isGranted else {
                    photoUploadError = viewModel.cameraRequiredForPhotoError
                    return
                }
            }
            do {
                isUploadingPhoto = true
                photoUploadError = nil
                defer { isUploadingPhoto = false }
                let base64 = try await Task.detached(priority: .userInitiated) {
                    switch source {
                    case .camera: return try AndroidAskTeacherImagePickerBridge.captureImageBase64()
                    case .gallery: return try AndroidAskTeacherImagePickerBridge.pickImageBase64()
                    }
                }.value
                guard !base64.isEmpty else { return }
                guard let data = Data(base64Encoded: base64) else {
                    photoUploadError = viewModel.couldNotReadImageError
                    return
                }
                guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
                    photoUploadError = viewModel.signInToAttachPhotoError
                    return
                }
                let url = try await StorageService.shared.uploadQuestionImage(data: data, uid: uid)
                uploadedPhotoUrls.append(url)
            } catch {
                logger.error("AskTeacherSheet photo upload failed: \(error.localizedDescription)")
                photoUploadError = error.localizedDescription
            }
        }
    }
#endif

    func closeAskTeacher() {
        dismiss()
    }

    var mathSymbolsSection: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            HStack {
                Text(viewModel.mathSymbolsSectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                PlatformIcon(systemName: "squareshape.split.3x3", size: 14, weight: .semibold, color: theme.secondaryText)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(AskTeacherSheet.mathSymbolsRow1, id: \.self) { symbol in
                        mathSymbolButton(symbol)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(AskTeacherSheet.mathSymbolsRow2, id: \.self) { symbol in
                        mathSymbolButton(symbol)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    func mathSymbolButton(_ symbol: String) -> some View {
        Button {
            questionText += symbol
            isQuestionFocused = false
        } label: {
            Text(symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(minWidth: 36, maxWidth: .infinity)
                .frame(height: 36)
                .background(theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var infoCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                // Both figures are live: the response time is the backend's
                // measured average, the count is who is actually online.
                if !viewModel.averageResponseText.isEmpty {
                    Text(viewModel.averageResponseText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
                Text(viewModel.onlineTeachersCountText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()

        }
        .padding(12)
        .background(theme.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    var footerText: some View {
        if viewModel.remainingMinutes > 0 {
            Text(viewModel.askTeacherFooterText)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

}

#if os(Android)
private enum AndroidAskTeacherImagePickerBridge {
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

#if os(iOS)
struct AskTeacherSheet_Previews: PreviewProvider {
  static var previews: some View {
    AskTeacherSheetLanguagePreview(language: .english)
      .previewDisplayName("English")

    AskTeacherSheetLanguagePreview(language: .hebrew)
      .previewDisplayName("Hebrew RTL")
  }
}

private struct AskTeacherSheetLanguagePreview: View {
  let language: SettingsLanguageChoice

    var body: some View {
    AskTeacherSheet(viewModel: MockStudentHomeViewModel())
    .environment(\.locale, LocalizationSupport.locale(languagePreference: language.rawValue))
    .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: language.rawValue))
    .onAppear {
      UserDefaults.standard.set(language.rawValue, forKey: LocalizationSupport.languagePreferenceKey)
    }
  }
}
#endif
