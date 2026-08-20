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

/// Question composer.
///
/// One scrolling column of labelled blocks — session type, topic, question,
/// photos — over a pinned action bar. The labels are quiet (secondary, 13pt)
/// so the controls, not the headings, carry the page; every control shares the
/// same geometry (filled `fieldBackground`, hairline border, accent fill when
/// selected) so a selection reads the same wherever it appears.
struct AskTeacherSheet: View {
    let viewModel: any StudentHomeViewModeling

    /// Topics are laid out as two fixed rows rather than a horizontal scroller:
    /// the scroller clipped the last chip and gave no hint that it scrolled.
    static let topicsRowOne = [("Algebra"), ("Geometry"), ("Trigonometry")]
    static let topicsRowTwo = [("Calculus"), ("Statistics"), ("Arithmetic")]
    static let maxPhotoCount = 4

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
    @State  var composerMode: ChatComposerMode = .regular
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
      || composerMode == .algebra
      || !uploadedPhotoUrls.isEmpty
  }
  var isFindDisabled: Bool {
    !canSubmit || isRequestingPermission
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  // MARK: - Metrics

  /// Outer gutter shared by the scrolling column and the action bar, so the
  /// button lines up with the fields above it.
  private var horizontalPadding: CGFloat {
#if os(Android)
    14
#else
    16
#endif
  }

  /// Space between two labelled blocks.
  private var blockSpacing: CGFloat {
#if os(Android)
    16
#else
    20
#endif
  }

  /// Space between a block's label and its control.
  private var labelSpacing: CGFloat {
#if os(Android)
    8
#else
    10
#endif
  }

  private var editorMinHeight: CGFloat {
#if os(Android)
    124
#else
    140
#endif
  }

  private var findButtonHeight: CGFloat {
#if os(Android)
    48
#else
    54
#endif
  }

  private var fieldRadius: CGFloat {
    14
  }

  // MARK: - Layout

    var body: some View {
        sheetLayout
        .background(theme.screenBackground)
        .navigationTitle(LocalizationSupport.localized("Ask a Teacher"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(LocalizationSupport.localized("Cancel")) { closeAskTeacher() }
            }
        }
        .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
        .id(languagePreference)
        .task {
            isQuestionFocused = true
        }
        .trackScreen(AnalyticsScreen.askTeacherSheet)
        .appDialog(
            LocalizationSupport.localized("Permission required"),
            isPresented: Binding(
                get: { permissionAlertMessage != nil },
                set: { if !$0 { permissionAlertMessage = nil } }
            ),
            message: permissionAlertMessage ?? "",
            actions: [
                AppDialogAction(LocalizationSupport.localized("Open Settings")) {
                    PermissionService.shared.openAppSettings()
                },
                AppDialogAction(LocalizationSupport.localized("Not now"), kind: .cancel)
            ]
        )
    }

    /// The action bar rides above the keyboard through `safeAreaInset` on iOS;
    /// SkipUI has no equivalent, so on Android it is the last row of the stack.
    var sheetLayout: some View {
        VStack(spacing: 0) {
            formScroll

            if composerMode == .algebra {
                VStack(spacing: 0) {
                    // The panel sits directly under the scrolling form, so it
                    // needs its own top edge to read as a keyboard rather than
                    // as more of the form.
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: flatHairline)
                        .frame(maxWidth: .infinity)

                    MathEquationEditorView { latex in
                        appendEquation(latex)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 8)
                }
                .background(theme.cardBackground)
            }

#if os(Android)
            submitBar
#endif
        }
#if !os(Android)
        .safeAreaInset(edge: .bottom) {
            submitBar
        }
#endif
    }

    var formScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: blockSpacing) {
                Text(LocalizationSupport.localized("Tell us what you're stuck on. A teacher usually joins within a minute."))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.secondaryText)

                sessionTypeBlock
                topicBlock
                questionBlock
                photoAttachmentSection
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Quiet block heading. Secondary and small on purpose — the filled
    /// controls below it are what the eye should land on.
    func sectionLabel(_ key: String) -> some View {
        Text(LocalizationSupport.localized(key))
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.secondaryText)
    }

    // MARK: - Session type

    var sessionTypeBlock: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            sectionLabel("Session type")

            HStack(spacing: 8) {
                sessionTypeSegment(value: "text", icon: "bubble.left.fill", title: "Text")
                sessionTypeSegment(value: "audio", icon: "mic.fill", title: "Audio")
                sessionTypeSegment(value: "video", icon: "video.fill", title: "Video")
            }
        }
    }

    /// Equal-width segment: the three session types are one choice, so they get
    /// one row of identical targets instead of three differently sized chips.
    func sessionTypeSegment(value: String, icon: String, title: String) -> some View {
        let isSelected = conversationType == value
        return Button {
            conversationType = value
        } label: {
            VStack(spacing: 5) {
                PlatformIcon(
                    systemName: icon,
                    size: 16,
                    weight: .semibold,
                    color: isSelected ? theme.onAccentText : theme.secondaryText
                )
                Text(LocalizationSupport.localized(title))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? theme.accent : theme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: fieldRadius, style: .continuous))
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                        .stroke(theme.controlBorder, lineWidth: flatHairline)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Topic

    var topicBlock: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            sectionLabel("Topic")

            VStack(spacing: 8) {
                topicRow(AskTeacherSheet.topicsRowOne)
                topicRow(AskTeacherSheet.topicsRowTwo)
            }
        }
    }

    func topicRow(_ topics: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(topics, id: \.self) { topic in
                topicChip(topic)
            }
        }
    }

    func topicChip(_ topic: String) -> some View {
        let isSelected = selectedTopic == topic
        return Button {
            selectedTopic = topic
        } label: {
            Text(LocalizationSupport.localized(topic))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isSelected ? theme.accent : theme.fieldBackground)
                .clipShape(Capsule())
                .overlay {
                    if !isSelected {
                        Capsule()
                            .stroke(theme.controlBorder, lineWidth: flatHairline)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question

    var questionBlock: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            HStack(spacing: 8) {
                sectionLabel("Your question")
                composerModeToggle
            }

            questionEditor

            if composerMode == .regular {
                questionHint
            }
        }
    }

    @ViewBuilder
    var questionEditor: some View {
        ZStack(alignment: .topLeading) {
            // The placeholder sits under the editor rather than over it, so it
            // never intercepts a tap — `TextEditor` draws no background of its
            // own once `scrollContentBackground` is hidden.
            if composerMode == .regular && questionText.isEmpty {
                Text(LocalizationSupport.localized("For example: I got stuck on question 3 right after opening the parentheses."))
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 16)
            }

            if composerMode == .regular {
                TextEditor(text: $questionText)
                    .focused($isQuestionFocused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(theme.primaryText)
                    .tint(theme.accent)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                Text(questionText.isEmpty
                     ? LocalizationSupport.localized("Tap math keys, then send to add to your question.")
                     : questionText)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(questionText.isEmpty ? theme.secondaryText : theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: editorMinHeight, alignment: .topLeading)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: fieldRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                .stroke(isQuestionFocused ? theme.accent : theme.controlBorder, lineWidth: flatHairline)
        }
    }

    /// Below the field: how far off the minimum the student is, replaced by a
    /// positive confirmation the moment the question is long enough to send.
    @ViewBuilder
    var questionHint: some View {
        if canSubmit {
            Text(LocalizationSupport.localized("Ready to send"))
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.positive)
        } else {
            Text(String(format: LocalizationSupport.localized("%d / 10 minimum characters"), questionText.count))
                .font(.system(size: 12))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Action bar

    var submitBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: flatHairline)
                .frame(maxWidth: .infinity)

            Button {
                Task { await findTeacherTapped() }
            } label: {
                Text(LocalizationSupport.localized("Find a Teacher"))
                    .font(.system(size: 17, weight: .bold))
                    // Enabled, this sits on `accent`, so the label needs the
                    // on-accent token; `primaryText` is black in light mode.
                    // Disabled it sits on `cardBackground`, where secondary
                    // text is the readable choice.
                    .foregroundStyle(isFindDisabled ? theme.secondaryText : theme.onAccentText)
                    .frame(maxWidth: .infinity)
                    .frame(height: findButtonHeight)
                    .background(isFindDisabled ? theme.cardBackground : theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isFindDisabled)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(theme.screenBackground)
    }

    func findTeacherTapped() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        if conversationType == "audio" || conversationType == "video" {
            let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
            if !micState.isGranted {
                permissionAlertMessage = conversationType == "video"
                    ? LocalizationSupport.localized("Microphone and camera access are required for a video session.")
                    : LocalizationSupport.localized("Microphone access is required for an audio session.")
                return
            }
        }

        if conversationType == "video" {
            let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
            if !cameraState.isGranted {
                permissionAlertMessage = LocalizationSupport.localized("Microphone and camera access are required for a video session.")
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

    // MARK: - Photos

    var photoAttachmentSection: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            sectionLabel("Attach a photo (optional)")

            HStack(spacing: 10) {
                ForEach(uploadedPhotoUrls, id: \.self) { url in
                    photoThumbnail(url: url)
                }

                if uploadedPhotoUrls.count < AskTeacherSheet.maxPhotoCount {
                    addPhotoButton
                }

                Spacer(minLength: 0)
            }

            if let photoUploadError {
                Text(photoUploadError)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.danger)
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
            LocalizationSupport.localized("Add a photo"),
            isPresented: $showAndroidPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button(LocalizationSupport.localized("Take Photo")) {
                pickAndroidPhoto(source: .camera)
            }
            Button(LocalizationSupport.localized("Choose from Library")) {
                pickAndroidPhoto(source: .gallery)
            }
            Button(LocalizationSupport.localized("Cancel"), role: .cancel) {}
        }
#endif
    }

    /// Dashed outline — the same "empty slot, drop something here" treatment
    /// the document uploads use, so the tile reads as an invitation rather than
    /// as a control that is already holding something.
    var addPhotoLabel: some View {
        RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
            .fill(theme.fieldBackground)
            .frame(width: 72, height: 72)
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
                RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(theme.controlBorder)
            }
    }

    func photoThumbnail(url: String) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                .fill(theme.fieldBackground)
                .frame(width: 72, height: 72)
                .overlay {
                    CachedRemoteImage(url: url, contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: fieldRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                        .stroke(theme.controlBorder, lineWidth: flatHairline)
                }

            Button {
                removePhoto(url: url)
            } label: {
                Circle()
                    .fill(theme.primaryText.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .overlay {
                        PlatformIcon(systemName: "xmark", size: 10, weight: .bold, color: theme.invertedText)
                    }
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
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
                    photoUploadError = LocalizationSupport.localized("You need to be signed in to attach a photo.")
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
                    photoUploadError = LocalizationSupport.localized("Camera access is required to take a photo.")
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
                    photoUploadError = LocalizationSupport.localized("Could not read selected image")
                    return
                }
                guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
                    photoUploadError = LocalizationSupport.localized("You need to be signed in to attach a photo.")
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

    /// Sits on the `Your question` label line: it switches how you type, so it
    /// belongs with the field's heading, not below the field where it read as
    /// a second topic picker.
    var composerModeToggle: some View {
        HStack(spacing: 4) {
            composerModePill(title: "Regular", isSelected: composerMode == .regular) {
                composerMode = .regular
                isQuestionFocused = true
            }
            composerModePill(title: "Math keyboard", isSelected: composerMode == .algebra) {
                composerMode = .algebra
                isQuestionFocused = false
            }
        }
        .padding(3)
        .background(theme.fieldBackground)
        .clipShape(Capsule())
    }

    func composerModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(LocalizationSupport.localized(title))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? theme.onAccentText : theme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(isSelected ? theme.accent : theme.fieldBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func appendEquation(_ latex: String) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !questionText.isEmpty && !questionText.hasSuffix(" ") && !questionText.hasSuffix("\n") {
            questionText += " "
        }
        questionText += trimmed
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
    NavigationStack {
      AskTeacherSheet(viewModel: MockStudentHomeViewModel())
    }
    .environment(\.locale, LocalizationSupport.locale(languagePreference: language.rawValue))
    .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: language.rawValue))
    .onAppear {
      UserDefaults.standard.set(language.rawValue, forKey: LocalizationSupport.languagePreferenceKey)
    }
  }
}
#endif
