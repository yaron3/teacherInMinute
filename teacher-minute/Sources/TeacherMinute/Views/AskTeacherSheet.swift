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
    private var canSubmit: Bool { questionText.trimmingCharacters(in: .whitespaces).count >= 10 }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Topic")
                        .font(.system(size: 14, weight: .semibold))
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
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Session type")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)

                    HStack(spacing: 10) {
                        ConversationTypeChip(title: LocalizationSupport.localized("Text"), isSelected: true) {
                            conversationType = "text"
                        }
                        ConversationTypeChip(title: LocalizationSupport.localized("Audio + Text"), isSelected: false) {}
                            .opacity(0.45)
                        ConversationTypeChip(title: LocalizationSupport.localized("Video + Audio + Text"), isSelected: false) {}
                            .opacity(0.45)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your question")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)

                    TextEditor(text: $questionText)
                        .focused($isQuestionFocused)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.appPrimaryText)
                        .tint(theme.appPink)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(theme.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isQuestionFocused {
                        MathSymbolRow(text: $questionText, isFocused: $isQuestionFocused)
                    }

                    Text(String(format: LocalizationSupport.localized("%lld / 10 min chars"), questionText.count))
                        .font(.system(size: 11))
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
                    Text("Find a Teacher")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

#if os(iOS)
struct AskTeacherSheet_Previews: PreviewProvider {
  static var previews: some View {
    AskTeacherSheet(
      viewModel: MockStudentHomeViewModel(),
      isPresented: .constant(true)
    )
  }
}
#endif
