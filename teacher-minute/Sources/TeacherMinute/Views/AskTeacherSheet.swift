//
//  AskTeacherSheet.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 17/05/2026.
//


// MARK: - Ask Teacher Sheet
import SwiftUI

struct AskTeacherSheet: View {
    let viewModel: any StudentHomeViewModeling

    static let topics = [("Algebra"), ("Geometry"), ("Trigonometry"), ("Calculus"), ("Statistics"), ("Arithmetic")]

    @State  var selectedTopic = ("Algebra")
    @State  var questionText = ""
    @State  var conversationType = "text"
    @State  var composerMode: ChatComposerMode = .regular
    @State  var permissionAlertMessage: String? = nil
    @State  var isRequestingPermission = false
    @FocusState var isQuestionFocused: Bool
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
    @Environment(\.dismiss) var dismiss
  private var canSubmit: Bool { questionText.trimmingCharacters(in: .whitespaces).count >= 10 || composerMode == .algebra}
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
                    Text(LocalizationSupport.localized("Session type"))
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.appPrimaryText)

                    HStack(spacing: 10) {
                        ConversationTypeChip(
                            title: LocalizationSupport.localized("Text"),
                            isSelected: conversationType == "text",
                            systemIcons: ["bubble.left.fill"],
                            accent: .teal
                        ) {
                            conversationType = "text"
                        }
                        ConversationTypeChip(
                            title: LocalizationSupport.localized("Audio"),
                            isSelected: conversationType == "audio",
                            systemIcons: ["mic.fill"],
                            accent: .teal
                        ) {
                            conversationType = "audio"
                        }
                        ConversationTypeChip(
                            title: LocalizationSupport.localized("Video"),
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
                    Text(LocalizationSupport.localized("Topic"))
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.appPrimaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AskTeacherSheet.topics, id: \.self) { topic in
                                Button {
                                    selectedTopic = topic
                                } label: {
                                    Text(LocalizationSupport.localized(topic.capitalized))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selectedTopic == topic ?theme.appCardBackground: theme.appPrimaryText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedTopic == topic ? theme.appPink : theme.appGrayBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
						.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

			  VStack(alignment: .leading, spacing: sectionSpacing) {
                    Text(LocalizationSupport.localized("Your question"))
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.appPrimaryText)

                    if composerMode == .regular {
                        TextEditor(text: $questionText)
                            .focused($isQuestionFocused)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(true)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(theme.appPrimaryText)
                            .tint(theme.appPink)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: editorMinHeight, alignment: .leading)
                            .background(theme.appGrayBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Text(questionText.isEmpty
                             ? LocalizationSupport.localized("Tap math keys, then send to add to your question.")
                             : questionText)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(questionText.isEmpty ? theme.appSecondaryText : theme.appPrimaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .frame(minHeight: editorMinHeight, alignment: .leading)
                            .background(theme.appGrayBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    composerModeToggle

                    Text(String(format: LocalizationSupport.localized("%d / 10 minimum characters"), questionText.count))
                        .font(.system(size: 11))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(canSubmit ? theme.appGreen : theme.appSecondaryText)
                }


                Button {
                    Task { await findTeacherTapped() }
                } label: {
                    Text(LocalizationSupport.localized("Find a Teacher"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: findButtonHeight)
                        .background( theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isRequestingPermission)
            }
            .padding(sheetPadding)
        }
        .scrollDismissesKeyboard(.immediately)

        if composerMode == .algebra {
            MathEquationEditorView { latex in
                appendEquation(latex)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, sheetPadding)
            .padding(.bottom, sheetPadding)
            .background(theme.appCardBackground)
        }
        }
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
        .alert(
            LocalizationSupport.localized("Permission required"),
            isPresented: Binding(
                get: { permissionAlertMessage != nil },
                set: { if !$0 { permissionAlertMessage = nil } }
            )
        ) {
            Button(LocalizationSupport.localized("OK"), role: .cancel) {}
        } message: {
            Text(permissionAlertMessage ?? "")
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
            photoUrls: [],
            conversationType: conversationType
        )
    }

    func closeAskTeacher() {
        dismiss()
    }

    var composerModeToggle: some View {
        HStack(spacing: 6) {
            composerModePill(title: LocalizationSupport.localized("Regular"), isSelected: composerMode == .regular) {
                composerMode = .regular
                isQuestionFocused = true
            }
            composerModePill(title: LocalizationSupport.localized("Algebra"), isSelected: composerMode == .algebra) {
                composerMode = .algebra
                isQuestionFocused = false
            }
            Spacer()
        }
    }

    func composerModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(LocalizationSupport.localized(title))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? theme.white : theme.appPrimaryText)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(isSelected ? theme.appPurple : theme.appGrayBackground)
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
