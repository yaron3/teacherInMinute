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
    private static let initialScrollID = "askTeacherInitialScroll"
    private static let questionScrollID = "askTeacherQuestionScroll"
    private static let keyboardScrollID = "askTeacherKeyboardScroll"

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
    /// Which keyboard writes the question. The same switch the chat composer
    /// offers, so a student who has used one recognises the other.
    @State  var keyboardMode: ChatComposerMode = .regular
    @State  var pendingFormulaLatex = ""
    /// Formulas the student has committed with the keyboard's `+`, kept as
    /// LaTeX and shown rendered. They join the question only as it is sent.
    @State  var attachedFormulas: [String] = []
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
    @Environment(\.dismiss) var dismiss
  private var canSubmit: Bool {
    composedQuestionText.count >= 10
      || !uploadedPhotoUrls.isEmpty
      || hasFormula
  }

  private var composedQuestionText: String {
    var parts: [String] = []
    let text = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { parts.append(text) }
    for latex in attachedFormulas {
      parts.append("$$\(latex)$$")
    }
    let pending = wrappedPendingFormula
    if !pending.isEmpty { parts.append(pending) }
    return parts.joined(separator: "\n")
  }

  private var wrappedPendingFormula: String {
    let trimmed = pendingFormulaLatex.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : "$$\(trimmed)$$"
  }

  /// A formula built with the algebra keyboard is a whole question on its own:
  /// `$$x^{2}$$` is nine characters and says everything the student is asking.
  /// So it clears the ten-character minimum the way a photo does, and the
  /// character counter steps aside for it too.
  private var hasFormula: Bool {
    !attachedFormulas.isEmpty || !pendingFormulaLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        ScrollViewReader { scrollProxy in
        ScrollView(.vertical, showsIndicators: false) {
				  LazyVStack(alignment: .leading, spacing: sheetSpacing) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.initialScrollID)

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
                    HStack(spacing: 8) {
                        Text(viewModel.yourQuestionSectionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(theme.primaryText)

                        Spacer(minLength: 0)

                        keyboardModePills(scrollProxy: scrollProxy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                    if !attachedFormulas.isEmpty {
                        attachedFormulaStrip
                    }

                    if keyboardMode == .algebra {
                        algebraKeyboard
                            .id(Self.keyboardScrollID)
                    }

                    // The primary "Find me a Teacher Now" button sits below the
                    // photo and info sections, off-screen while the keyboard is
                    // up. This second entry point rides alongside the character
                    // counter so the question can be sent without dismissing it.
                    HStack(spacing: 10) {
                        // A formula clears the minimum on its own, so the
                        // counter steps aside for it as it does for a photo.
                        if uploadedPhotoUrls.isEmpty, !hasFormula {
                            Text(viewModel.minimumCharactersText(count: composedQuestionText.count))
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
                .id(Self.questionScrollID)

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
        .onChange(of: keyboardMode) { _, mode in
            // Whichever route flipped the mode, the algebra pad is the keyboard
            // now and the system one has to leave the screen before the scroll
            // measures what is visible.
            if mode == .algebra {
                isQuestionFocused = false
                SoftKeyboard.dismiss()
            }
            scrollForKeyboardMode(mode, proxy: scrollProxy)
        }
        }
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
            await focusQuestionOnAppear()
        }
        .onChange(of: isQuestionFocused) { _, focused in
            // Tapping into the question field asks for the system keyboard, so
            // the algebra pad steps aside rather than stacking underneath it.
            if focused {
                keyboardMode = .regular
            }
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

    /// Puts the cursor in the question field when the sheet opens, and keeps the
    /// keyboard there.
    ///
    /// All of the Android trouble is one thing: this screen is pushed with
    /// `navigationDestination(isPresented:)`, and Skip re-runs that modifier on
    /// every recomposition — `if id.value == nil || !navigator.isViewPresented(…)`
    /// pushes again whenever the navigator no longer recognises the entry, which
    /// happens when `syncState()` rebuilds `backStackState` in a
    /// `LaunchedEffect { delay(1000) … }` about a second after the push. Every
    /// push runs `keyboardController?.hide()`, so roughly a second after the
    /// sheet opens the keyboard is taken away.
    ///
    /// That hide leaves Compose focus alone, which is why the focus state cannot
    /// fix it: `isQuestionFocused` still reads `true`, so setting it changes
    /// nothing and SkipUI's `requestFocus()` is a no-op on a field that already
    /// has focus — the student is left tapping a focused field to get the
    /// keyboard back. So the keyboard itself is what gets watched and re-raised,
    /// past the reconciliation that takes it.
    func focusQuestionOnAppear() async {
        isQuestionFocused = true
#if os(Android)
        // Long enough to cover the ~1s back-stack reconciliation and the hide
        // that rides along with it, checked often enough to put the keyboard
        // back before the student reaches for it.
        //
        // The cap on raises matters as much as the window. Asking whether the
        // keyboard is up is a best-effort answer — before Android 11 it is a
        // measurement, not a fact — so a wrong answer must cost a couple of
        // wasted calls, not a keyboard fighting the student for two seconds.
        // Only worth doing where the keyboard can be observed. On Android 10
        // and older the answer is a guess, and a wrong guess asks for a
        // keyboard that is already up — which is a flicker in the student's
        // face, worse than the problem being corrected.
        guard SoftKeyboard.isVisibilityObservable else { return }

        var checks = 0
        var raises = 0
        while checks < 8 && raises < 3 {
            checks += 1
            try? await Task.sleep(nanoseconds: 250_000_000)

            // Anything the student did themselves outranks this: they may have
            // switched to the algebra pad, started writing, or put the keyboard
            // away on purpose after typing.
            guard keyboardMode == .regular, questionText.isEmpty else { return }
            guard !SoftKeyboard.isVisible else { continue }

            raises += 1
            logger.info("[AskTeacher][Android] keyboard gone while the question field held focus; raising it again (\(raises))")

            if !isQuestionFocused {
                isQuestionFocused = true
            }
            SoftKeyboard.show()
        }
#endif
    }

    /// Brings the chosen keyboard into view.
    ///
    /// The question section is the Android target in both modes, because the
    /// algebra field and its keys now live inside it and Skip can only scroll
    /// to a direct child of the `LazyVStack` — it looks the id up in the lazy
    /// item collector, which does not see ids nested inside an item. Aligning
    /// that item's top with the top of the viewport is what shows the question
    /// field, the formula field under it and the keys under that; Skip ignores
    /// the anchor on Android, so top alignment is all there is.
    ///
    /// The scroll also runs twice on Android. Switching to the algebra pad
    /// drops focus, and the system keyboard takes a moment to slide away; a
    /// scroll issued while it is still up is clamped against the shrunken
    /// viewport and drifts once the space comes back. The second pass lands
    /// once the keyboard has gone (the delays add up), and is a no-op when the
    /// first pass already arrived.
    func scrollForKeyboardMode(_ mode: ChatComposerMode, proxy: ScrollViewProxy) {
#if os(Android)
        let target = Self.questionScrollID
        let anchor: UnitPoint = .top
        let firstDelay: UInt64 = 120_000_000
        let settleDelay: UInt64 = 300_000_000
#else
        let target = mode == .algebra ? Self.keyboardScrollID : Self.initialScrollID
        let anchor: UnitPoint = mode == .algebra ? .bottom : .top
        let firstDelay: UInt64 = 80_000_000
        let settleDelay: UInt64 = 0
#endif
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: firstDelay)
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: anchor)
            }
            guard settleDelay > 0 else { return }
            try? await Task.sleep(nanoseconds: settleDelay)
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
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
            text: composedQuestionText,
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
        PhotoSourceButton(viewModel: viewModel, onImageData: { data in
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
        PhotoSourceButton(viewModel: viewModel, onImageData: { data in
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

    /// Which keyboard writes the question, offered next to the question's own
    /// title so the switch sits with the field it types into.
    ///
    /// The old version of this was a strip of bare symbols that appended a
    /// character and dropped focus, so every symbol cost the student their
    /// keyboard. Now the two keyboards are alternatives the student picks
    /// between, and the algebra one stays up for as long as they are building
    /// the formula.
    func keyboardModePills(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            keyboardModePill(title: viewModel.regularKeyboardLabel, isSelected: keyboardMode == .regular) {
                keyboardMode = .regular
                pendingFormulaLatex = ""
                isQuestionFocused = true
                scrollForKeyboardMode(.regular, proxy: scrollProxy)
            }
            keyboardModePill(title: viewModel.algebraKeyboardLabel, isSelected: keyboardMode == .algebra) {
                keyboardMode = .algebra
                // The math keys are the keyboard in this mode, so the system
                // one gives up the space it was holding. Dropping the focus
                // state is only half of it — on Android that alone leaves
                // the IME up and the pad stacks on top of it — so the
                // keyboard is dismissed outright.
                isQuestionFocused = false
                SoftKeyboard.dismiss()
                scrollForKeyboardMode(.algebra, proxy: scrollProxy)
            }
        }
    }

    /// The algebra keys and the field they write into, sitting immediately
    /// below the question field.
    ///
    /// A formula cannot be typed into the question field itself: it is a
    /// `TextEditor` holding plain text, so the keys would have to write raw
    /// LaTeX into it — `\sqrt{}` and `\frac{}{}` where the student expects to
    /// see √ and a fraction — and SwiftUI offers no caret position to insert at
    /// anyway, on either platform. So the formula gets its own field, built to
    /// match the question field (same corner radius, same fill) and placed at
    /// the bottom of it, and its `+` files the finished formula into
    /// `attachedFormulas`, where it shows rendered until the question is sent.
    var algebraKeyboard: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            MathEquationEditorView(
                actionSystemImage: "plus",
                fieldCornerRadius: 12,
                onDraftChange: { latex in
                    pendingFormulaLatex = latex
                }
            ) { latex in
                appendFormula(latex)
            }
            .environment(\.layoutDirection, .leftToRight)

            Text(viewModel.addFormulaHint)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.secondaryText)
        }
    }

    func keyboardModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? theme.onDarkFill : theme.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(isSelected ? theme.accentStrong : theme.secondaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Keeps the finished equation as LaTeX and shows it rendered above the
    /// keys. Writing it into the question field instead would print the markup
    /// at the student — `$$5x^{\\frac{3}{2}}$$` where they just drew a
    /// fraction — and hand them a string they could break by editing it. The
    /// `$$` delimiters go on only as the question is sent, which is where they
    /// matter: they are what tells the teacher's incoming-question card and
    /// the chat bubbles to render a formula rather than print it.
    func appendFormula(_ latex: String) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingFormulaLatex = ""
        attachedFormulas.append(trimmed)
    }

    /// The committed formulas, rendered, each with the `×` that takes it back
    /// off the question.
    var attachedFormulaStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<attachedFormulas.count, id: \.self) { index in
                HStack(spacing: 8) {
                    MathFormulaView(latex: attachedFormulas[index], displayMode: false)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)

                    Button {
                        attachedFormulas.remove(at: index)
                    } label: {
                        Circle()
                            .fill(theme.primaryText.opacity(0.85))
                            .frame(width: 20, height: 20)
                            .overlay {
                                PlatformIcon(systemName: "xmark", size: 10, weight: .bold, color: theme.invertedText)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
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
