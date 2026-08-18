//
//  TeacherLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
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
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FlatTopHeader(
                        eyebrow: LocalizationSupport.localized("Teaching History"),
                        name: viewModel.teacherName,
                        avatarImageURL: viewModel.profileImageURL,
                        avatarSystemImage: "person.crop.circle.fill",
                        showNotificationBadge: false
                    )
                    .padding(.top, 16)

                    FlatPageTitle(title: LocalizationSupport.localized("Past Lessons"))
                        .padding(.top, 24)

                    summaryStrip
                        .padding(.top, 20)

                    FlatSearchField(
                        placeholder: LocalizationSupport.localized("Search lessons or students"),
                        text: $viewModel.query
                    )
                    .padding(.top, 16)

                    FlatSectionHeader(LocalizationSupport.localized("Past")) {
                        FlatChip(title: viewModel.completedCountText)
                    }
                    .padding(.top, 28)

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.4)
                                .tint(theme.primaryText)
                                .padding(.vertical, 40)
                            Spacer()
                        }
                        .padding(.top, 14)
                    } else if viewModel.filteredLessons.isEmpty {
                        Text(LocalizationSupport.localized("You don't have any recent activity"))
                            .font(.system(size: 17))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.top, 20)
                    } else {
                        FlatCard(padding: 0, outlined: true) {
                            VStack(spacing: 0) {
                                ForEach(viewModel.filteredLessons) { lesson in
                                    LessonHistoryRow(
                                        lesson: lesson,
                                        accentColor: theme.primaryText,
                                        iconName: "person.fill.checkmark",
                                        isLoading: viewModel.isLoading(lesson)
                                    ) {
                                        presentingLesson = lesson
                                    }

                                    if lesson.id != viewModel.filteredLessons.last?.id {
                                        FlatRule()
                                    }
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(theme.screenBackground)
        }
        .task {
            await viewModel.loadProfile()
            isLoading = false
        }
        .sheet(item: $presentingLesson) { lesson in
            LessonDetailView(
                lesson: lesson,
                amountLabel: LocalizationSupport.localized("Earnings"),
                isPlaying: viewModel.isPlaying(lesson),
                initialDetails: nil,
                audioAction: { viewModel.toggleAudio(for: lesson) }
            )
        }
    }
    
    private var summaryStrip: some View {
        HStack(spacing: 12) {
            HistoryMetricCard(
                title: LocalizationSupport.localized("Time Taught"),
                value: viewModel.totalTimeTaughtText,
                systemImage: "clock.fill",
                tint: theme.primaryText
            )

            HistoryMetricCard(
                title: LocalizationSupport.localized("Earnings"),
                value: viewModel.totalEarningsText,
                systemImage: "dollarsign.circle.fill",
                tint: theme.primaryText
            )
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
