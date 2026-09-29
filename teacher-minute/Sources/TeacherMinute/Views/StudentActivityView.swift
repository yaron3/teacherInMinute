//
//  StudentActivityView.swift
//  teacher-minute
//
//  Instant Teacher's lesson history, as its design draws it: the time learned,
//  three counts, and the lessons as cards. It runs on the same view model as
//  `StudentLessonHistoryView` and opens the same lesson detail.
//

import SwiftUI

struct StudentActivityView: View {
  @State var viewModel = StudentLessonHistoryViewModel()
  @State var isLoading = true
  @State var presentingLesson: LessonHistoryItem?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    BrandTabScreen {
      VStack(spacing: 0) {
        BrandPageHeader(label: viewModel.recentSessionsLabel, title: viewModel.studentName) {
          BrandMenuButton()
        }
        ScrollView(.vertical, showsIndicators: false) {
          content
        }
      }
      // On a plain stack inside the screen, not on `BrandTabScreen`; see
      // there.
      .task {
        await viewModel.loadProfile()
        isLoading = false
      }
      .sheet(item: $presentingLesson) { lesson in
        LessonDetailView(
          viewModel: viewModel,
          lesson: lesson,
          amountLabel: viewModel.costLabel,
          viewerRole: "student",
          isPlaying: viewModel.isPlaying(lesson),
          initialDetails: nil,
          showsAmount: false,
          audioAction: { viewModel.toggleAudio(for: lesson) }
        )
      }
    }
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        BrandPageHero(title: viewModel.activityTitle, subtitle: viewModel.activitySubtitle)
        summaryCard
      }
      .padding(.top, 16)
      .padding(.bottom, 20)

      statsRow
        .padding(.bottom, 16)

      lessonList
        .padding(.bottom, 16)
    }
    .padding(.horizontal, 20)
  }

  /// The time learned, with the timer at the start of the card, as designed.
  private var summaryCard: some View {
    HStack(spacing: 12) {
      Image("brand-timer", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onDarkFill)
        .frame(width: 24, height: 24)
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.timeLearnedTitle)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
        Text(isLoading ? "–" : viewModel.learnedMinutesText)
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 55)
    .brandCard()
  }

  /// Teachers, minutes and completed lessons, from the start of the row.
  private var statsRow: some View {
    HStack(spacing: 12) {
      statCard(value: viewModel.teachersCount, label: viewModel.teachersStatLabel)
      statCard(value: viewModel.learnedMinutes, label: viewModel.minutesStatLabel)
      statCard(value: viewModel.lessons.count, label: viewModel.completedStatLabel)
    }
  }

  private func statCard(value: Int, label: String) -> some View {
    VStack(spacing: 6) {
      Text(isLoading ? "–" : "\(value)")
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 72)
    .background(theme.brandCardSurface)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var lessonList: some View {
    if isLoading {
      ProgressView()
        .progressViewStyle(.circular)
        .scaleEffect(1.4)
        .tint(theme.onDarkFill)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    } else if viewModel.lessons.isEmpty {
      Text(viewModel.emptyHistoryText)
        .font(.system(size: 15))
        .foregroundStyle(theme.brandSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      // Lazy: a lesson asked as a formula draws it in a web view, which only
      // the cards on screen should pay for.
      LazyVStack(spacing: 12) {
        ForEach(viewModel.lessons) { lesson in
          lessonCard(lesson)
        }
      }
    }
  }

  /// The book at the start, then the question and who, when and how long.
  private func lessonCard(_ lesson: LessonHistoryItem) -> some View {
    Button {
      presentingLesson = lesson
      viewModel.view(lesson)
    } label: {
      HStack(spacing: 12) {
        Image("brand-book-open", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onDarkFill)
          .frame(width: 20, height: 20)
          .frame(width: 48, height: 48)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 8) {
          FormulaAwareText(
            text: lesson.title,
            textColor: theme.onDarkFill,
            font: .system(size: 15, weight: .bold),
            formulaMinWidth: 120,
            formulaMaxWidth: 220,
            lineLimit: 1,
            displayMode: false,
            formulaHeight: 44,
            formulaInset: 0
          )
          HStack(spacing: 8) {
            Text(viewModel.minutesText(for: lesson))
            Text("\(lesson.otherParticipant) \u{2022} \(lesson.completedAt)")
          }
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
          .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: 48)
      .padding(16)
      .background(theme.brandCardSurface)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("activity_lesson_\(lesson.questionId)")
  }
}

#if os(iOS)
struct StudentActivityView_Previews: PreviewProvider {
  static var previews: some View {
    StudentActivityView()
  }
}
#endif
