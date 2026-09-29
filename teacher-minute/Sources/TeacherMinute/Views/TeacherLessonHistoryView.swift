//
//  TeacherLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//
//  The teacher's past lessons, in the brand's style the student's Activity
//  has: the time taught and the earnings, a search, and the lessons as cards
//  that open the lesson's detail.
//

import SwiftUI

struct TeacherLessonHistoryView: View {
  @State var viewModel = TeacherLessonHistoryViewModel()
  @State var isLoading = true
  @State var presentingLesson: LessonHistoryItem?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    BrandTabScreen {
      VStack(spacing: 0) {
        BrandPageHeader(label: viewModel.historyEyebrow, title: viewModel.teacherName) {
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
          amountLabel: viewModel.earningsLabel,
          viewerRole: "teacher",
          isPlaying: viewModel.isPlaying(lesson),
          initialDetails: nil,
          audioAction: { viewModel.toggleAudio(for: lesson) }
        )
      }
    }
    .trackScreen(AnalyticsScreen.teacherLessonHistory)
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  private var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      BrandPageHero(title: viewModel.pastLessonsTitle)
      summaryStrip
      FlatSearchField(
        placeholder: viewModel.searchPlaceholder,
        text: $viewModel.query
      )
      FlatSectionHeader(viewModel.pastSectionTitle) {
        FlatChip(title: viewModel.completedCountText)
      }
      .padding(.top, 8)
      lessonList
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 20)
  }

  private var summaryStrip: some View {
    HStack(spacing: 12) {
      HistoryMetricCard(
        title: viewModel.timeTaughtTitle,
        value: viewModel.totalTimeTaughtText,
        systemImage: "clock.fill",
        tint: theme.brandActionBackground
      )

      HistoryMetricCard(
        title: viewModel.earningsLabel,
        value: viewModel.totalEarningsText,
        systemImage: LessonFormatting.currencySignIconFilled,
        tint: theme.brandActionBackground
      )
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
    } else if viewModel.filteredLessons.isEmpty {
      Text(viewModel.emptyHistoryText)
        .font(.system(size: 15))
        .foregroundStyle(theme.brandSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      // Lazy for the same reason as the student's list: the row draws the
      // question's formula.
      LazyVStack(spacing: 12) {
        ForEach(viewModel.filteredLessons) { lesson in
          LessonHistoryRow(
            lesson: lesson,
            loadingLabel: viewModel.loadingSessionDetailsLabel,
            accentColor: theme.brandActionBackground,
            iconName: "person.fill.checkmark",
            isLoading: viewModel.isLoading(lesson)
          ) {
            presentingLesson = lesson
            viewModel.view(lesson)
          }
          .brandCard(padding: 0)
        }
      }
    }
  }
}

#if os(iOS)
struct TeacherLessonHistoryView_Previews: PreviewProvider {
  static var previews: some View {
    TeacherLessonHistoryView()
  }
}
#endif
