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
          title: viewModel.topicTitle,
          options: DemoStudentSimulation.topics,
          selected: viewModel.simulation.topic
        ) { option in
          viewModel.selectTopic(option)
        }
        chipSection(
          title: viewModel.difficultyTitle,
          options: DemoStudentSimulation.difficulties,
          selected: viewModel.simulation.difficulty
        ) { option in
          viewModel.selectDifficulty(option)
        }
        chipSection(
          title: viewModel.sessionTypeTitle,
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
    .screenGround()
  }

  // MARK: - Sections

  var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(viewModel.screenTitle)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.primaryText)

        Spacer()

        Button {
          trackTap("simulate_question_close")
          onClose()
        } label: {
          PlatformIcon(systemName: "xmark", size: 13, weight: .semibold, color: theme.secondaryText)
        }
        .buttonStyle(.plain)
      }

      Text(viewModel.introText)
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
              trackTap("simulate_question_option", detail: option)
              select(option)
            } label: {
              Text(viewModel.optionLabel(option))
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
      Text(viewModel.hintTitle)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primaryText)

      TextField(
        viewModel.hintPlaceholder,
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
      title: viewModel.sendLabel,
      systemImage: "paperplane.fill"
    ) {
      trackTap("simulate_question_send")
      onSend(viewModel.pendingSimulation())
      onClose()
    }
  }

  var footnote: some View {
    Text(viewModel.footnoteText)
      .font(.system(size: 12))
      .foregroundStyle(theme.secondaryText)
      .lineSpacing(3)
      .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
  }
}
