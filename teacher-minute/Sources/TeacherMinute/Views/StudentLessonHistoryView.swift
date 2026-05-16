//
//  StudentLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import SwiftUI

struct StudentLessonHistoryView: View {
    @State var viewModel = StudentLessonHistoryViewModel()
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AppTopHeader(
                    avatarSystemImage: "person.crop.circle.fill",
                    eyebrow: "Lesson History",
                    name: viewModel.studentName,
                    showNotificationBadge: false
                )
                .padding(.top, 18)
                
                summaryStrip
                    .padding(.top, 22)
                
                searchField
                    .padding(.top, 22)
                
                HStack {
                    Text("Past Lessons")
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
                            accentColor: theme.appPink,
                            iconName: "function"
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
        .sheet(item: $viewModel.selectedLesson) { lesson in
            LessonDetailView(
                lesson: lesson,
                amountLabel: "Cost",
                isPlaying: viewModel.isPlaying(lesson),
                audioAction: { viewModel.toggleAudio(for: lesson) }
            )
        }
    }
    
    private var summaryStrip: some View {
        HStack(spacing: 14) {
            HistoryMetricCard(
                title: "Time Learned",
                value: viewModel.totalTimeLearnedText,
                systemImage: "clock.fill",
                tint: theme.appPink
            )
			.frame(maxWidth: .infinity)
            
            HistoryMetricCard(
                title: "Total Spend",
                value: viewModel.totalSpendText,
                systemImage: "creditcard.fill",
                tint: theme.appPurple
            )
			.frame(maxWidth: .infinity)
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 10) {
            PlatformIcon(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.appSecondaryText)
            
            TextField("Search lessons or teachers", text: $viewModel.query)
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

struct HistoryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        RoundedInfoCard {
            VStack(alignment: .leading, spacing: 12) {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(
                            systemName: systemImage,
                            size: 14,
                            weight: .semibold,
                            color: tint
                        )
                    }
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.appSecondaryText)
                
                Text(value)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared Lesson Row

struct LessonHistoryRow: View {
    let lesson: LessonHistoryItem
    let accentColor: Color
    let iconName: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        Button(action: action) {
            RoundedInfoCard {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                        .overlay {
                            PlatformIcon(systemName: iconName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(accentColor)
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(lesson.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.appPrimaryText)

                        Text("\(lesson.otherParticipant) \u{2022} \(lesson.completedAt)")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.appSecondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(lesson.amount)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.appPrimaryText)

                        SmallPill(
                            title: lesson.duration,
                            foreground: theme.appGreen,
                            background: theme.appGreenSoft
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LessonActionButton: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                PlatformIcon(
                    systemName: systemImage,
                    size: 12,
                    weight: .bold,
                    color: foreground
                )
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Lesson Detail

struct LessonDetailView: View {
    let lesson: LessonHistoryItem
    let amountLabel: String
    let isPlaying: Bool
    let audioAction: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(theme.appPrimaryText)

                        Text("\(lesson.otherParticipant) \u{2022} \(lesson.completedAt) \u{2022} \(lesson.duration)")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.appSecondaryText)
                    }

                    HStack(spacing: 14) {
                        HistoryMetricCard(
                            title: amountLabel,
                            value: lesson.amount,
                            systemImage: "creditcard.fill",
                            tint: theme.appPurple
                        )

                        HistoryMetricCard(
                            title: "Duration",
                            value: lesson.duration,
                            systemImage: "clock.fill",
                            tint: theme.appPink
                        )
                    }

                    LessonActionButton(
                        title: isPlaying ? "Pause Audio" : "Listen to Lesson",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        foreground: lesson.hasAudio ? theme.appCardBackground : theme.appSecondaryText,
                        background: lesson.hasAudio ? theme.appPink : theme.appGrayBackground,
                        action: audioAction
                    )
                    .disabled(!lesson.hasAudio)

                    RoundedInfoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Summary")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.appPrimaryText)

                            Text(lesson.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.appSecondaryText)
                                .lineSpacing(4)
                        }
                    }

                    RoundedInfoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transcript Preview")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.appPrimaryText)

                            Text(lesson.transcriptPreview)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.appSecondaryText)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Lesson")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if os(iOS)
struct StudentLessonHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        StudentLessonHistoryView()
    }
}
#endif
