//
//  SimulateStudentQuestionView.swift
//  teacher-minute
//
//  Demo tool: lets a teacher send themselves a simulated student question,
//  written by the local AI model behind the `demo-student` service.
//

import SwiftUI

@MainActor
struct SimulateStudentQuestionView: View {
  @State var viewModel: SimulateStudentQuestionViewModel
  let teacherName: String
  let onClose: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(
    viewModel: SimulateStudentQuestionViewModel = SimulateStudentQuestionViewModel(),
    teacherName: String,
    onClose: @escaping () -> Void
  ) {
    self._viewModel = State(initialValue: viewModel)
    self.teacherName = teacherName
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
        statusArea
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .background(theme.screenBackground)
    // Close once the question is on its way, so the incoming-question overlay
    // is visible on the dashboard behind this sheet.
    .onChange(of: viewModel.dispatchedQuestionText) { _, questionText in
      guard let questionText, !questionText.isEmpty else { return }
      Task {
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        onClose()
      }
    }
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
          viewModel.cancel()
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
    Button {
      viewModel.send(teacherName: teacherName)
    } label: {
      HStack(spacing: 9) {
        if viewModel.isSending {
          ProgressView()
        } else {
          PlatformIcon(systemName: "paperplane.fill", size: 14, weight: .bold, color: theme.onAccentText)
        }
        Text(viewModel.isSending
             ? LocalizationSupport.localized("Sending...")
             : LocalizationSupport.localized("Send Simulated Question"))
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(theme.onAccentText)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(viewModel.canSend ? theme.accent : theme.controlDisabled)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.canSend)
  }

  var statusArea: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let statusMessage = viewModel.statusMessage {
        Text(statusMessage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.positive)
      }

      if let questionText = viewModel.dispatchedQuestionText, !questionText.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(LocalizationSupport.localized("QUESTION"))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(theme.secondaryText)
          Text(questionText)
            .font(.system(size: 13))
            .foregroundStyle(theme.primaryText)
            .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }

      if viewModel.usedCannedQuestion {
        Text(LocalizationSupport.localized("The local AI model was unreachable, so a sample question was used instead."))
          .font(.system(size: 11))
          .foregroundStyle(theme.secondaryText)
      }

      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.danger)
          .lineSpacing(3)
      }
    }
    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
  }
}
