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
    @Binding var isPresented: Bool

    static let topics = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"]

    @State  var selectedTopic = "algebra"
    @State  var questionText = ""
    @State  var conversationType = "text"
    @FocusState var isQuestionFocused: Bool
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
    private var canSubmit: Bool { questionText.trimmingCharacters(in: .whitespaces).count >= 10 }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

    var body: some View {
        NavigationStack {
		  VStack(alignment: .leading, spacing: 24) {
			VStack(alignment: .leading, spacing: 10) {
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

			VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizationSupport.localized("Session type"))
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.appPrimaryText)

                    HStack(spacing: 10) {
                        ConversationTypeChip(title: LocalizationSupport.localized("Text"), isSelected: true) {
                            conversationType = "text"
                        }
                        ConversationTypeChip(title: LocalizationSupport.localized("Audio + Text"), isSelected: false) {}
                            .opacity(0.9)
                        ConversationTypeChip(title: LocalizationSupport.localized("Video + Audio + Text"), isSelected: false) {}
                            .opacity(0.9)
                    }
					.frame(maxWidth: .infinity, alignment: .leading)
                }

			  VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizationSupport.localized("Your question"))
                        .font(.system(size: 14, weight: .semibold))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.appPrimaryText)

                    TextEditor(text: $questionText)
                        .focused($isQuestionFocused)
                        .font(.system(size: 14))
						.multilineTextAlignment(.leading)
                        .foregroundStyle(theme.appPrimaryText)
                        .tint(theme.appPink)
                        .scrollContentBackground(.hidden)
                        .padding(12)
						.frame(minHeight: 120, alignment: .leading)
                        .background(theme.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isQuestionFocused {
                        MathSymbolRow(text: $questionText, isFocused: $isQuestionFocused)
                    }

                    Text(String(format: LocalizationSupport.localized("%lld / 10 minimum characters"), Int64(questionText.count)))
                        .font(.system(size: 11))
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(canSubmit ? theme.appGreen : theme.appSecondaryText)
                }


                Button {
                    isPresented = false
                    Task {
                        await viewModel.askTeacher(
                            topic: selectedTopic,
                            text: questionText.trimmingCharacters(in: .whitespaces),
                            photoUrls: [],
                            conversationType: conversationType
                        )
                    }
                } label: {
                    Text(LocalizationSupport.localized("Find a Teacher"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background( theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(10)
            .navigationTitle(LocalizationSupport.localized("Ask a Teacher"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
				  Button(LocalizationSupport.localized("Cancel")) { isPresented = false }
                }

            }
        }
        .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
        .id(languagePreference)
        .task {
            isQuestionFocused = true
        }
        .trackScreen(AnalyticsScreen.askTeacherSheet)
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
    AskTeacherSheet(
      viewModel: MockStudentHomeViewModel(),
      isPresented: .constant(true)
    )
    .environment(\.locale, LocalizationSupport.locale(languagePreference: language.rawValue))
    .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: language.rawValue))
    .onAppear {
      UserDefaults.standard.set(language.rawValue, forKey: LocalizationSupport.languagePreferenceKey)
    }
  }
}
#endif
