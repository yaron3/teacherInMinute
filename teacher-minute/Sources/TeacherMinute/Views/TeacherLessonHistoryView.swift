//
//  TeacherLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import SwiftUI

struct TeacherLessonHistoryView: View {
    @State var viewModel = TeacherLessonHistoryViewModel()
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AppTopHeader(
                    avatarSystemImage: "person.crop.circle.fill",
                    eyebrow: "Teaching History",
                    name: viewModel.teacherName,
                    avatarImageURL: viewModel.profileImageURL,
                    showNotificationBadge: false
                )
                .padding(.top, 18)
                
                summaryStrip
                    .padding(.top, 22)
                
                searchField
                    .padding(.top, 22)
                
                HStack {
                    Text(LocalizationSupport.localized("Past Lessons"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
                    
                    Spacer()
                    
                    SmallPill(
                        title: viewModel.completedCountText,
                        foreground: theme.appPurple,
                        background: theme.appPurpleSoft
                    )
                }
                .padding(.top, 26)
                
                VStack(spacing: 12) {
                    ForEach(viewModel.filteredLessons) { lesson in
                        LessonHistoryRow(
                            lesson: lesson,
                            accentColor: theme.appPurple,
                            iconName: "person.fill.checkmark",
                            isLoading: viewModel.isLoading(lesson)
                        ) {
                            viewModel.view(lesson)
                        }
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .task {
            await viewModel.loadProfile()
        }
        .sheet(isPresented: $viewModel.isLessonSheetPresented) {
            if let lesson = viewModel.selectedLesson {
                LessonDetailView(
                    lesson: lesson,
                    amountLabel: "Earnings",
                    isPlaying: viewModel.isPlaying(lesson),
                    initialDetails: viewModel.selectedLessonDetails,
                    audioAction: { viewModel.toggleAudio(for: lesson) }
                )
            }
        }
    }
    
    private var summaryStrip: some View {
        HStack(spacing: 14) {
            HistoryMetricCard(
                title: "Time Taught",
                value: viewModel.totalTimeTaughtText,
                systemImage: "clock.fill",
                tint: theme.appPink
            )
            
            HistoryMetricCard(
                title: "Earnings",
                value: viewModel.totalEarningsText,
                systemImage: "dollarsign.circle.fill",
                tint: theme.appPurple
            )
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 10) {
            PlatformIcon(
                systemName: "magnifyingglass",
                size: 14,
                weight: .semibold,
                color: theme.appSecondaryText
            )
            
            TextField("Search lessons or students", text: $viewModel.query)
                .font(.system(size: 14))
                .foregroundStyle(theme.appPrimaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(theme.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.appGrayBackground, lineWidth: 1)
        }
        .shadow(color: theme.appPrimaryText.opacity(0.025), radius: 10, x: 0, y: 5)
    }
}

#if os(iOS)
struct TeacherLessonHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        TeacherLessonHistoryView()
    }
}
#endif
