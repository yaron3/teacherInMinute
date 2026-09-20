//
//  SimulateStudentQuestionView.swift
//  teacher-minute
//
//  Demo tool: lets a teacher send themselves a simulated student question,
//  written by the local AI model behind the `demo-student` service.
//  Tapping Send hands the request to the dashboard and closes immediately, so
//  the teacher is back on the dashboard when the invite arrives.
//

import SwiftUI

@MainActor
struct SimulateStudentQuestionView: View {
  @State var viewModel: SimulateStudentQuestionViewModel
  let onSend: (DemoStudentSimulation) -> Void
  let onClose: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(
    viewModel: SimulateStudentQuestionViewModel = SimulateStudentQuestionViewModel(),
    onSend: @escaping (DemoStudentSimulation) -> Void,
    onClose: @escaping () -> Void
  ) {
    self._viewModel = State(initialValue: viewModel)
    self.onSend = onSend
    self.onClose = onClose
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 22) {
        header
        chipSection(
          title: LocalizationSupport.localized("Topic"),
          options: DemoStudentSimulation.topics,
          selected: viewModel.simulation.topic
        ) { option in
          viewModel.selectTopic(option)
        }
        chipSection(
          title: LocalizationSupport.localized("Difficulty"),
          options: DemoStudentSimulation.difficulties,
          selected: viewModel.simulation.difficulty
        ) { option in
          viewModel.selectDifficulty(option)
        }
        chipSection(
          title: LocalizationSupport.localized("Session Type"),
          options: DemoStudentSimulation.conversationTypes,
          selected: viewModel.simulation.conversationType
        ) { option in
          viewModel.selectConversationType(option)
        }
        hintField
        sendButton
        footnote
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .background(theme.screenBackground)
  }

  // MARK: - Sections

  var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(LocalizationSupport.localized("Simulate a Student Question"))
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.primaryText)

        Spacer()

        Button {
          onClose()
        } label: {
          PlatformIcon(systemName: "xmark", size: 13, weight: .semibold, color: theme.secondaryText)
        }
        .buttonStyle(.plain)
      }

      Text(LocalizationSupport.localized("A demo student writes the question with a local AI model and sends it to you, so you can practise the whole flow without a real student."))
        .font(.system(size: 12))
        .foregroundStyle(theme.secondaryText)
        .lineSpacing(3)
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
    }
  }

  /// A titled row of single-choice chips — topic, difficulty and session type
  /// all share the same shape.
  func chipSection(
    title: String,
    options: [String],
    selected: String,
    select: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primaryText)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(options, id: \.self) { option in
            Button {
              select(option)
            } label: {
              Text(LocalizationSupport.localized(option.capitalized))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected == option ? theme.onAccentText : theme.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(selected == option ? theme.accent : theme.cardBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
  }

  var hintField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(LocalizationSupport.localized("What should it be about? (optional)"))
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primaryText)

      TextField(
        LocalizationSupport.localized("e.g. solving quadratic equations"),
        text: $viewModel.hint
      )
      .font(.system(size: 15))
      .foregroundStyle(theme.primaryText)
      .tint(theme.accent)
      .padding(.horizontal, 14)
      .padding(.vertical, 14)
      .background(theme.fieldBackground)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }
    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
  }

  var sendButton: some View {
    FlatPrimaryButton(
      title: LocalizationSupport.localized("Send Simulated Question"),
      systemImage: "paperplane.fill"
    ) {
      onSend(viewModel.pendingSimulation())
      onClose()
    }
  }

  var footnote: some View {
    Text(LocalizationSupport.localized("The question takes a few seconds to write. You will get it on your dashboard like any other request."))
      .font(.system(size: 12))
      .foregroundStyle(theme.secondaryText)
      .lineSpacing(3)
      .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
  }
}
