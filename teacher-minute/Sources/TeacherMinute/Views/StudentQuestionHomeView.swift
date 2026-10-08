import SwiftUI
#if os(iOS)
@preconcurrency import PhotosUI
#endif

/// The student's home. The question is photographed with the camera that
/// fills the screen, or written on the panel behind the other tab, and goes to
/// any teacher who is online.
///
/// Asking and buying run on the home's own flows, which `StudentHomeView`
/// owns: `mayAskTeacher` raises the balance alerts, and `onLoadMinutes` opens
/// the packages.
struct StudentQuestionHomeView: View {
  let viewModel: any StudentHomeViewModeling
  /// Whether a question may go out now. Raises the alert that says why not.
  let mayAskTeacher: () -> Bool
  let onLoadMinutes: () -> Void
  /// A screen stands over the home, and the camera is not what the student
  /// is looking at.
  var isCovered = false

  @State var mode: QuestionHomeMode = .photo
  @State var hasCamera = true
  @State var cameraAccess: PermissionState = .notDetermined
  @State var isOnScreen = false
  @State var questionText = ""
  @FocusState var isQuestionFocused: Bool
  @State var keyboardMode: ChatComposerMode = .regular
  @State var pendingFormulaLatex = ""
  /// Formulas committed with the algebra keyboard's `+`, kept as LaTeX. They
  /// join the question only as it is sent, as on the ask sheet.
  @State var attachedFormulas: [String] = []
  @State var photoURL: String?
  /// The attached photo's bytes, kept with a question held through sign-up so
  /// it can be uploaded again under the new account.
  @State var photoData: Data?
  @State var isTakingPhoto = false
  @State var isUploadingPhoto = false
  @State var isSubmitting = false
  @State var photoErrorMessage: String?
  @State var submitErrorMessage: String?
  @State var showsEmptyQuestionAlert = false
  @State var showsCameraDisabledAlert = false
  /// The screen's height, and the bottom of its safe area, with no keyboard
  /// up: the largest either has been. Zero until measured.
  @State var restingHeight: CGFloat = 0
  @State var restingSafeAreaBottom: CGFloat = 0
  /// Until when the system keyboard may still be on its way up or down, and
  /// the sizes Android reports are passing ones — a moment into a close it
  /// reports the full window with the navigation bar still inset below it.
  @State var keyboardSettlesAt = Date.distantPast
  @State var algebraKeyboardHeight: CGFloat = 0
#if os(iOS)
  @State var showsLibraryPicker = false
  @State var libraryItem: PhotosPickerItem?
#endif
  @Environment(\.scenePhase) var scenePhase
  /// The language's direction. The screen is laid out by coordinates, left to
  /// right in either language, and what reads in the language's direction
  /// sets this back.
  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.sideMenuAction) var sideMenuAction
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    screen
    // The home is dark in both schemes, like the other brand screens, so the
    // controls it borrows — the text field, the algebra keys — are drawn for a
    // dark ground too.
    .environment(\.colorScheme, .dark)
    // Light status icons over the camera and the panel alike; the navigation
    // bar's go dark over the camera's cyan fade.
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: mode == .photo)
    .onAppear {
      isOnScreen = true
      hasCamera = QuestionCamera.isAvailable
      cameraAccess = viewModel.questionCameraAccess
      requestCameraIfNeeded()
      restoreHeldQuestion()
    }
    .onDisappear {
      isOnScreen = false
    }
    .onChange(of: scenePhase) { _, phase in
      // Back from Settings, the camera may have been allowed there.
      guard phase == .active else { return }
      cameraAccess = viewModel.questionCameraAccess
    }
    .onChange(of: isQuestionFocused) { _, focused in
      keyboardSettlesAt = Date().addingTimeInterval(1)
      // The system keyboard is the keyboard now; the algebra keys step aside.
      if focused {
        keyboardMode = .regular
      }
    }
    .onChange(of: viewModel.isInLiveSession) { _, isInSession in
      // The question has found its teacher; the next one starts afresh.
      if isInSession {
        clearQuestion()
      }
    }
    .modifier(dialogs)
#if os(iOS)
    .photosPicker(isPresented: $showsLibraryPicker, selection: $libraryItem, matching: .images)
    .onChange(of: libraryItem) { _, item in
      guard let item else { return }
      libraryItem = nil
      Task { await attachLibraryItem(item) }
    }
#endif
  }

  /// The reader keeps to the safe area, so it says how large the unsafe
  /// edges are, and gives way to the system keyboard on both platforms: on
  /// iOS the keyboard is part of the safe area, and Android resizes the whole
  /// window for it.
  ///
  /// The screen is drawn out over the unsafe edges, to its own edges, and laid
  /// out for its height at rest, so the camera, the character and the
  /// background run on under a keyboard. Only the panel and its buttons move,
  /// to stay above it.
  var screen: some View {
    GeometryReader { proxy in
      let insets = proxy.safeAreaInsets
      let available = CGSize(
        width: proxy.size.width + insets.leading + insets.trailing,
        height: proxy.size.height + insets.top + insets.bottom
      )
      let safeAreaBottom = insets.top + proxy.size.height
      let height = restingHeight > 0 ? restingHeight : available.height
      let layout = QuestionHomeLayout(
        size: CGSize(width: available.width, height: height),
        safeTop: insets.top,
        safeBottom: height - max(restingSafeAreaBottom, safeAreaBottom),
        availableHeight: available.height,
        keyboardTop: keyboardTop(safeAreaBottom: safeAreaBottom, screenHeight: height)
      )
      ZStack(alignment: .topLeading) {
        background
        scene(layout)
        modeContent(layout)
        topBar(layout)
        algebraKeyboard(layout)
      }
      // The space there is, keyboard or not: Compose centres a view larger
      // than its slot rather than hanging it from the top. What sits lower
      // is placed by offset, and runs on under the keyboard.
      .frame(width: available.width, height: available.height, alignment: .topLeading)
      .environment(\.layoutDirection, .leftToRight)
      // Out over the unsafe edges.
      .ignoresSafeArea()
      .animation(.easeOut(duration: 0.2), value: layout.keyboardTop)
      .onAppear {
        rememberRestingSize(height: available.height, safeAreaBottom: safeAreaBottom)
      }
      .onChange(of: available.height) { _, newHeight in
        rememberRestingSize(height: newHeight, safeAreaBottom: insets.top + proxy.size.height)
      }
    }
  }

  /// Taken only while no system keyboard can be up or moving. The largest
  /// wins, over the smaller sizes the screen passes through as it first
  /// appears.
  func rememberRestingSize(height: CGFloat, safeAreaBottom: CGFloat) {
    guard !isQuestionFocused, Date() >= keyboardSettlesAt else { return }
    restingHeight = max(restingHeight, height)
    restingSafeAreaBottom = max(restingSafeAreaBottom, safeAreaBottom)
  }

  /// Where a keyboard begins, in screen coordinates, when one is up on the
  /// panel: the system's — wherever the safe area now ends short of where it
  /// ends at rest — or the algebra keys.
  func keyboardTop(safeAreaBottom: CGFloat, screenHeight: CGFloat) -> CGFloat? {
    guard mode == .text else { return nil }
    var top: CGFloat?
    if keyboardMode == .algebra, algebraKeyboardHeight > 0 {
      top = screenHeight - algebraKeyboardHeight
    }
    if restingSafeAreaBottom > 0, safeAreaBottom < restingSafeAreaBottom - 1 {
      top = min(top ?? safeAreaBottom, safeAreaBottom)
    }
    return top
  }

  // MARK: - Layers

  /// The camera behind the photo tab, fading into cyan at the bottom where
  /// the character stands; the brand background behind the writing panel.
  @ViewBuilder
  var background: some View {
    if mode == .photo {
      ZStack {
        Color.black
        if showsCamera {
          QuestionCameraPreview()
        }
        LinearGradient(
          stops: [
            Gradient.Stop(color: theme.brandActionBackground.opacity(0), location: 0.75),
            Gradient.Stop(color: theme.brandActionBackground, location: 0.91835),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
      .tappableFrame()
      .onTapGesture { dismissKeyboard() }
    } else {
      ZStack {
        LinearGradient(
          colors: [theme.brandBackgroundTop, theme.brandBackgroundBottom],
          startPoint: .top,
          endPoint: .bottom
        )
        BrandStreaks()
      }
      .tappableFrame()
      .onTapGesture { dismissKeyboard() }
    }
  }

  func scene(_ layout: QuestionHomeLayout) -> some View {
    QuestionHomeScene(
      mode: mode,
      firstBubbleText: mode == .photo ? viewModel.snapYourQuestionText : viewModel.typeYourQuestionText,
      teacherCount: viewModel.teachersOnlineBubbleCount,
      teacherLabel: viewModel.teachersOnlineBubbleLabel,
      priceText: viewModel.pricePerMinuteBubbleText,
      footnote: viewModel.noFixedLessonsText,
      footnoteColor: mode == .photo ? theme.onBrandAction : theme.brandMutedText,
      textColor: theme.onBrandAction,
      textDirection: layoutDirection
    )
    .scaleEffect(layout.sceneScale, anchor: .bottomLeading)
    .offset(y: layout.size.height - QuestionHomeLayout.sceneHeight)
  }

  @ViewBuilder
  func modeContent(_ layout: QuestionHomeLayout) -> some View {
    if mode == .photo {
      captureButton
        .frame(width: layout.size.width, height: layout.availableHeight)
        .offset(x: 0.5, y: layout.captureCenterY - layout.availableHeight / 2)
    } else {
      writingPanel(layout)
        .offset(x: layout.panelLeading, y: layout.panelTop)
      writingHint(layout)
      actionButtons(layout)
        .offset(x: layout.panelLeading + 8, y: layout.buttonsTop)
    }
  }

  func topBar(_ layout: QuestionHomeLayout) -> some View {
    ZStack(alignment: .topLeading) {
      menuButton
        .offset(x: 24, y: layout.menuTop)
      modeToggle(width: layout.toggleWidth)
        .offset(x: layout.size.width - 24 - layout.toggleWidth, y: layout.toggleTop)
    }
  }

  // MARK: - Top bar

  @ViewBuilder
  var menuButton: some View {
    if let sideMenuAction {
      Button {
        dismissKeyboard()
        sideMenuAction.open()
      } label: {
        ZStack(alignment: .topTrailing) {
          menuFace
          if sideMenuAction.showsBadge {
            Circle()
              .fill(theme.accent)
              .frame(width: 9, height: 9)
              .padding(3)
          }
        }
      }
      .buttonStyle(.plain)
#if !os(Android)
      // SkipUI has no string `accessibilityLabel`.
      .accessibilityLabel(sideMenuAction.accessibilityLabel)
#endif
      .accessibilityIdentifier("side_menu_button")
    }
  }

  /// A solid cyan square over the camera; a quiet outlined one on the panel.
  @ViewBuilder
  var menuFace: some View {
    if mode == .photo {
      icon("home-menu", size: 22, color: theme.brandBackgroundTop)
        .frame(width: 52, height: 52)
        .background(theme.brandActionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
      icon("home-menu", size: 22, color: theme.brandActionBackground)
        .frame(width: 44, height: 44)
        .background(theme.brandActionBackground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }
    }
  }

  /// Photo on the left and text on the right in both languages, as designed.
  func modeToggle(width: CGFloat) -> some View {
    let toggleWidth = max(0, width)
    let segmentWidth = max(0, (toggleWidth - 12) / 2)
    return HStack(spacing: 4) {
      modeSegment(.photo, icon: "home-camera", iconSize: 25, label: viewModel.photoModeLabel, width: segmentWidth)
      modeSegment(.text, icon: "home-message", iconSize: 24, label: viewModel.textModeLabel, width: segmentWidth)
    }
    .padding(4)
    .frame(width: toggleWidth, height: QuestionHomeLayout.toggleHeight)
    .background(theme.brandBackgroundTop)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  func modeSegment(_ segment: QuestionHomeMode, icon name: String, iconSize: CGFloat, label: String, width: CGFloat) -> some View {
    let isSelected = mode == segment
    let color = isSelected ? theme.onBrandAction : theme.onDarkFill
    return Button {
      select(segment)
    } label: {
      HStack(spacing: 9) {
        icon(name, size: iconSize, color: color)
        Text(label)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(color)
          .lineLimit(1)
          .environment(\.layoutDirection, layoutDirection)
      }
      .frame(width: width, height: 52)
      .background(isSelected ? theme.brandActionBackground : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .tappableFrame()
    }
    .buttonStyle(.plain)
  }

  // MARK: - Photo tab

  var captureButton: some View {
    Button {
      captureTapped()
    } label: {
      VStack(spacing: 0) {
        ZStack {
          RoundedRectangle(cornerRadius: 10)
            .fill(theme.brandActionBackground)
          if isTakingPhoto {
            ProgressView()
              .tint(theme.onBrandAction)
          } else {
            icon("home-capture", size: 52.778, color: theme.onBrandAction)
          }
        }
        .frame(width: 95, height: 91.481)

        Text(viewModel.attachPhotoLabel)
          .font(.system(size: 26.39, weight: .medium))
          .foregroundStyle(captureLabelColor)
          .multilineTextAlignment(.center)
          .designLineHeight(fontSize: 26.39)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 95)
          .environment(\.layoutDirection, layoutDirection)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .disabled(isTakingPhoto)
    .accessibilityIdentifier("capture_question_photo")
  }

  /// Black over the camera, as designed. With no picture behind it — no
  /// camera, or none allowed — the ground is black, and so is not the label.
  var captureLabelColor: Color {
    showsCamera ? theme.onBrandAction : theme.onDarkFill
  }

  // MARK: - Text tab

  func writingPanel(_ layout: QuestionHomeLayout) -> some View {
    HStack(spacing: 0) {
      writingArea
      Rectangle()
        .fill(theme.brandControlBorder)
        .frame(width: 1)
      toolsColumn(panelHeight: layout.panelHeight, isCompact: layout.isPanelCompact)
        .frame(width: 119)
    }
    .frame(width: layout.panelWidth, height: layout.panelHeight)
    .background(theme.brandPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
    .readingDirection(layoutDirection)
  }

  var writingArea: some View {
    ZStack(alignment: .topLeading) {
      DotGrid(origin: CGPoint(x: 6, y: 7))
        .fill(theme.brandPanelDot)
        .environment(\.layoutDirection, .leftToRight)

      VStack(spacing: 8) {
        TextEditor(text: $questionText)
          .focused($isQuestionFocused)
          .textInputAutocapitalization(.sentences)
          .autocorrectionDisabled(true)
          .font(.system(size: 16))
          .multilineTextAlignment(.leading)
          .foregroundStyle(theme.onDarkFill)
          .tint(theme.brandActionBackground)
          .scrollContentBackground(.hidden)
          .accessibilityIdentifier("question_text")

        if !attachedFormulas.isEmpty {
          attachedFormulaList
        }
      }
      .padding(10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// A panel shortened for a keyboard keeps only the keyboard choice: the
  /// photo is a tap away again once the keyboard is down.
  ///
  /// Its gaps are the design's 19pt where the panel has the design's height,
  /// and close up on a shorter screen before the photo would run off it.
  func toolsColumn(panelHeight: CGFloat, isCompact: Bool) -> some View {
    VStack(spacing: max(8, min(19, (panelHeight - 258) / 2))) {
      keyboardChoice
      if !isCompact {
        Rectangle()
          .fill(theme.brandControlBorder)
          .frame(height: 1)
        photoSlot
      }
    }
    .frame(maxHeight: .infinity)
  }

  var keyboardChoice: some View {
    VStack(spacing: 8) {
      Text(viewModel.chooseKeyboardTitle)
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      keyboardOption(.regular, icon: "home-keyboard", iconSize: 28)
        .accessibilityIdentifier("keyboard_mode_regular")
      keyboardOption(.algebra, icon: "home-math", iconSize: 23.917)
        .accessibilityIdentifier("keyboard_mode_algebra")
    }
    .padding(8)
    .frame(height: 152)
  }

  /// The choice mark, then the keyboard's icon, in that order in both
  /// languages as designed.
  func keyboardOption(_ option: ChatComposerMode, icon name: String, iconSize: CGFloat) -> some View {
    let isSelected = keyboardMode == option
    return Button {
      chooseKeyboard(option)
    } label: {
      HStack(spacing: 10) {
        Image(decorative: isSelected ? "home-choice-on" : "home-choice-off", bundle: .module)
          .resizable()
          .frame(width: 24, height: 24)
        icon(name, size: iconSize, color: isSelected ? theme.brandActionBackground : theme.brandSecondaryText)
          .frame(width: 28, height: 28)
      }
      .frame(width: 84, height: 52)
      .tappableFrame()
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: 1)
      }
      .environment(\.layoutDirection, .leftToRight)
    }
    .buttonStyle(.plain)
  }

  var photoSlot: some View {
    VStack(spacing: 14) {
      Text(photoURL == nil ? viewModel.attachPhotoLabel : viewModel.deletePhotoLabel)
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: 15)
      photoThumbnail
        .frame(width: 67, height: 60)
    }
    .frame(width: 84, height: 85)
  }

  /// The attached photo, which a tap takes off the question; while there is
  /// none, a way back to the camera.
  @ViewBuilder
  var photoThumbnail: some View {
    if isUploadingPhoto {
      RoundedRectangle(cornerRadius: 4)
        .fill(theme.brandBackgroundTop)
        .overlay {
          ProgressView()
            .tint(theme.brandActionBackground)
        }
    } else if let photoURL {
      Button {
        self.photoURL = nil
        photoData = nil
      } label: {
        CachedRemoteImage(url: photoURL, contentMode: .fill)
          .frame(width: 67, height: 60)
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .overlay {
            icon("home-delete-photo", size: 24, color: theme.onBrandAction)
          }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("delete_question_photo")
    } else {
      Button {
        select(.photo)
      } label: {
        RoundedRectangle(cornerRadius: 4)
          .stroke(theme.brandControlBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .overlay {
            icon("home-camera", size: 25, color: theme.brandSecondaryText)
          }
          .tappableFrame()
      }
      .buttonStyle(.plain)
    }
  }

  /// The committed formulas, rendered, each with the `×` that takes it back
  /// off the question.
  var attachedFormulaList: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(0..<attachedFormulas.count, id: \.self) { index in
        HStack(spacing: 8) {
          MathFormulaView(latex: attachedFormulas[index], displayMode: false)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)

          Button {
            attachedFormulas.remove(at: index)
          } label: {
            Circle()
              .fill(theme.onDarkFill.opacity(0.85))
              .frame(width: 20, height: 20)
              .overlay {
                PlatformIcon(systemName: "xmark", size: 10, weight: .bold, color: theme.brandPanelBackground)
              }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// The hint over the empty writing area, at its leading end: over the
  /// right edge in Hebrew, as designed, where it runs off the panel, and
  /// mirrored to the left edge in English.
  @ViewBuilder
  func writingHint(_ layout: QuestionHomeLayout) -> some View {
    if questionText.isEmpty, attachedFormulas.isEmpty, !isQuestionFocused, keyboardMode == .regular {
      let rightToLeftX = layout.panelLeading + layout.panelWidth - 83.5
      SpeechBubble(
        lines: viewModel.typeYourQuestionText.components(separatedBy: "\n"),
        textCenterX: 53.5,
        textTop: 36.5,
        textWidth: 92,
        textColor: theme.onBrandAction,
        textDirection: layoutDirection
      )
      .offset(
        x: layoutDirection == .rightToLeft
          ? rightToLeftX
          : layout.size.width - rightToLeftX - SpeechBubble.size.width,
        y: layout.panelTop + 149.5
      )
      .allowsHitTesting(false)
    }
  }

  func actionButtons(_ layout: QuestionHomeLayout) -> some View {
    let width = (layout.buttonsWidth - 8) / 2
    return HStack(spacing: 8) {
      loadMinutesButton(width: width)
      findTeacherButton(width: width)
    }
    .readingDirection(layoutDirection)
  }

  func findTeacherButton(width: CGFloat) -> some View {
    let isBusy = isSubmitting || isUploadingPhoto
    return Button {
      findTeacherTapped()
    } label: {
      ZStack {
        buttonLabel(viewModel.findTeacherLabel, color: theme.onBrandAction)
          .opacity(isBusy ? 0 : 1)
        if isBusy {
          ProgressView()
            .tint(theme.onBrandAction)
        }
      }
      .frame(width: width, height: QuestionHomeLayout.buttonHeight)
      .background(theme.brandActionBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(theme.onBrandAction, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(isBusy)
    .accessibilityIdentifier("find_teacher")
  }

  func loadMinutesButton(width: CGFloat) -> some View {
    Button {
      dismissKeyboard()
      onLoadMinutes()
    } label: {
      buttonLabel(viewModel.loadMinutesLabel, color: theme.brandActionBackground)
        .frame(width: width, height: QuestionHomeLayout.buttonHeight)
        .tappableFrame()
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandActionBackground, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("load_minutes")
  }

  /// 25pt as designed, and smaller only when a translation would not fit on
  /// one line at that size.
  func buttonLabel(_ text: String, color: Color) -> some View {
    ViewThatFits(in: .horizontal) {
      buttonText(text, size: 25, color: color)
      buttonText(text, size: 21, color: color)
      buttonText(text, size: 17, color: color)
    }
    .padding(.horizontal, 8)
  }

  func buttonText(_ text: String, size: CGFloat, color: Color) -> some View {
    Text(text)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(color)
      .lineLimit(1)
      .fixedSize()
  }

  /// The algebra keys, over the bottom of the screen while they are the
  /// keyboard.
  @ViewBuilder
  func algebraKeyboard(_ layout: QuestionHomeLayout) -> some View {
    if mode == .text, keyboardMode == .algebra {
      VStack(spacing: 0) {
        Rectangle()
          .fill(theme.brandControlBorder)
          .frame(height: 1)
        MathEquationEditorView(
          actionSystemImage: "plus",
          fieldCornerRadius: 12,
          onDraftChange: { latex in
            pendingFormulaLatex = latex
          }
        ) { latex in
          appendFormula(latex)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, max(12, layout.safeBottom))
      }
      .frame(width: layout.size.width)
      .background(theme.brandPanelBackground)
      .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
        algebraKeyboardHeight = height
      }
      .frame(width: layout.size.width, height: layout.availableHeight, alignment: .bottom)
    }
  }

  // MARK: - Pieces

  func icon(_ name: String, size: CGFloat, color: Color) -> some View {
    Image(name, bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  var dialogs: QuestionHomeDialogs {
    QuestionHomeDialogs(
      viewModel: viewModel,
      showsEmptyQuestionAlert: $showsEmptyQuestionAlert,
      showsCameraDisabledAlert: $showsCameraDisabledAlert,
      photoErrorMessage: $photoErrorMessage,
      submitErrorMessage: $submitErrorMessage,
      onChooseFromLibrary: { pickFromLibrary() }
    )
  }

  // MARK: - State

  /// The camera runs only while it is what the student is looking at: not
  /// under the writing panel, a search, a lesson, the purchase screen or
  /// another section.
  var showsCamera: Bool {
    guard mode == .photo, isOnScreen, !isCovered, hasCamera, cameraAccess.isGranted else { return false }
    if case .idle = viewModel.searchState {
      return true
    }
    return false
  }

  var composedQuestionText: String {
    var parts: [String] = []
    let text = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { parts.append(text) }
    for latex in attachedFormulas {
      parts.append("$$\(latex)$$")
    }
    let pending = pendingFormulaLatex.trimmingCharacters(in: .whitespacesAndNewlines)
    if !pending.isEmpty { parts.append("$$\(pending)$$") }
    return parts.joined(separator: "\n")
  }

  /// A photo or a formula is a question on its own; words need ten letters,
  /// as on the ask sheet.
  var canSubmit: Bool {
    photoURL != nil
      || !attachedFormulas.isEmpty
      || !pendingFormulaLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || composedQuestionText.count >= 10
  }

  // MARK: - Actions

  func select(_ newMode: QuestionHomeMode) {
    guard mode != newMode else { return }
    dismissKeyboard()
    mode = newMode
    requestCameraIfNeeded()
  }

  func requestCameraIfNeeded() {
    guard mode == .photo, hasCamera, cameraAccess == .notDetermined else { return }
    Task {
      cameraAccess = await viewModel.requestQuestionCameraAccess()
    }
  }

  func captureTapped() {
    guard !isTakingPhoto, !isUploadingPhoto else { return }
    guard hasCamera else {
      pickFromLibrary()
      return
    }
    switch cameraAccess {
    case .granted:
      Task { await takePhoto() }
    case .notDetermined:
      Task { cameraAccess = await viewModel.requestQuestionCameraAccess() }
    case .denied:
      showsCameraDisabledAlert = true
    }
  }

  /// Takes the photo, then turns to the panel — where the student can add
  /// words and send it — while the photo uploads.
  func takePhoto() async {
    isTakingPhoto = true
    let data: Data
    do {
      data = try await viewModel.takeQuestionPhoto()
    } catch {
      isTakingPhoto = false
      photoErrorMessage = error.localizedDescription
      return
    }
    isTakingPhoto = false
    select(.text)
    await attachPhoto(data, source: .camera)
  }

  func attachPhoto(_ data: Data, source: QuestionPhotoSource) async {
    isUploadingPhoto = true
    do {
      photoURL = try await viewModel.uploadQuestionPhoto(data, source: source)
      photoData = data
    } catch {
      photoErrorMessage = error.localizedDescription
    }
    isUploadingPhoto = false
  }

  func pickFromLibrary() {
#if os(iOS)
    showsLibraryPicker = true
#elseif os(Android)
    Task {
      do {
        guard let data = try await viewModel.pickQuestionPhotoFromLibrary() else { return }
        select(.text)
        await attachPhoto(data, source: .library)
      } catch {
        photoErrorMessage = error.localizedDescription
      }
    }
#endif
  }

#if os(iOS)
  func attachLibraryItem(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      let photo = try viewModel.preparedLibraryPhoto(data)
      select(.text)
      await attachPhoto(photo, source: .library)
    } catch {
      photoErrorMessage = error.localizedDescription
    }
  }
#endif

  func chooseKeyboard(_ option: ChatComposerMode) {
    keyboardMode = option
    if option == .algebra {
      // The algebra keys are the keyboard now, and the system one gives up
      // its space: dropping focus alone leaves it up on Android.
      isQuestionFocused = false
      SoftKeyboard.dismiss()
    } else {
      pendingFormulaLatex = ""
      isQuestionFocused = true
    }
  }

  func appendFormula(_ latex: String) {
    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    pendingFormulaLatex = ""
    attachedFormulas.append(trimmed)
  }

  func findTeacherTapped() {
    guard !isSubmitting, !isUploadingPhoto else { return }
    dismissKeyboard()
    guard canSubmit else {
      showsEmptyQuestionAlert = true
      return
    }
    guard mayAskTeacher() else {
      // Out of minutes: the student may now register or log in for some,
      // which replaces this screen. Keep the question for when they are back.
      viewModel.holdQuestionDraft(currentDraft, photoData: photoData)
      return
    }
    isSubmitting = true
    Task {
      let error = await viewModel.submitQuestionWithPermissions(
        topic: viewModel.anyTopic,
        text: composedQuestionText,
        photoUrls: photoURL.map { [$0] } ?? [],
        conversationType: viewModel.defaultConversationType
      )
      isSubmitting = false
      submitErrorMessage = error
    }
  }

  var currentDraft: QuestionDraft {
    QuestionDraft(
      text: questionText,
      formulas: attachedFormulas,
      pendingFormula: pendingFormulaLatex,
      photoURL: photoURL
    )
  }

  /// Puts back the question the student was sending before they registered
  /// or logged in for minutes, so it need not be asked again.
  func restoreHeldQuestion() {
    guard let held = viewModel.takeQuestionDraft() else { return }
    questionText = held.draft.text
    attachedFormulas = held.draft.formulas
    pendingFormulaLatex = held.draft.pendingFormula
    select(.text)
    guard let url = held.draft.photoURL else { return }
    isUploadingPhoto = true
    Task {
      photoURL = await viewModel.questionPhotoForCurrentAccount(url: url, photoData: held.photoData)
      photoData = photoURL == nil ? nil : held.photoData
      if photoURL == nil {
        photoErrorMessage = viewModel.heldPhotoLostMessage
      }
      isUploadingPhoto = false
    }
  }

  func clearQuestion() {
    viewModel.discardQuestionDraft()
    questionText = ""
    attachedFormulas = []
    pendingFormulaLatex = ""
    photoURL = nil
    photoData = nil
    keyboardMode = .regular
    mode = .photo
  }

  func dismissKeyboard() {
    guard isQuestionFocused else { return }
    isQuestionFocused = false
    SoftKeyboard.dismiss()
  }
}

/// The home's dialogs, apart from the body they would otherwise make too long
/// for the type checker.
struct QuestionHomeDialogs: ViewModifier {
  let viewModel: any StudentHomeViewModeling
  @Binding var showsEmptyQuestionAlert: Bool
  @Binding var showsCameraDisabledAlert: Bool
  @Binding var photoErrorMessage: String?
  @Binding var submitErrorMessage: String?
  let onChooseFromLibrary: () -> Void

  func body(content: Content) -> some View {
    content
      .appDialog(
        viewModel.emptyQuestionTitle,
        isPresented: $showsEmptyQuestionAlert,
        message: viewModel.emptyQuestionMessage,
        actions: [AppDialogAction(viewModel.okLabel)]
      )
      .appDialog(
        viewModel.cameraDisabledTitle,
        isPresented: $showsCameraDisabledAlert,
        message: viewModel.cameraDisabledMessage,
        actions: [
          AppDialogAction(viewModel.openSettingsLabel) {
            viewModel.openCameraSettings()
          },
          AppDialogAction(viewModel.photoSourceLibraryLabel) {
            onChooseFromLibrary()
          },
          AppDialogAction(viewModel.cancelLabel, kind: .cancel),
        ]
      )
      .appDialog(
        viewModel.photoNotAttachedTitle,
        isPresented: Binding(
          get: { photoErrorMessage != nil },
          set: { if !$0 { photoErrorMessage = nil } }
        ),
        message: photoErrorMessage,
        actions: [AppDialogAction(viewModel.okLabel)]
      )
      .appDialog(
        viewModel.permissionRequiredTitle,
        isPresented: Binding(
          get: { submitErrorMessage != nil },
          set: { if !$0 { submitErrorMessage = nil } }
        ),
        message: submitErrorMessage,
        actions: [AppDialogAction(viewModel.okLabel)]
      )
  }
}

extension View {
  /// The whole frame answers taps, its transparent parts included. Compose
  /// makes a button's whole frame tappable by itself, and SkipUI has no
  /// `contentShape`.
  func tappableFrame() -> some View {
#if os(Android)
    self
#else
    contentShape(Rectangle())
#endif
  }

  /// Lines as far apart as the design's Noto Sans Hebrew sets them. iOS sets
  /// the text in SF, whose lines are shorter by about a sixth of the type
  /// size; Android's Hebrew face is Noto itself.
  func designLineHeight(fontSize: CGFloat) -> some View {
#if os(Android)
    self
#else
    let extra = fontSize * 0.169
    return self
      .lineSpacing(extra)
      .padding(.vertical, extra / 2)
#endif
  }
}

#if os(iOS)
struct StudentQuestionHomeView_Previews: PreviewProvider {
  static var previews: some View {
    StudentQuestionHomeView(
      viewModel: MockStudentHomeViewModel(),
      mayAskTeacher: { true },
      onLoadMinutes: {}
    )
  }
}
#endif
