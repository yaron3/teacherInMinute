//
//  StudentLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import SwiftUI

struct StudentLessonHistoryView: View {
    @State var viewModel = StudentLessonHistoryViewModel()
    
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
                        .foregroundStyle(Color.appPrimaryText)
                    
                    Spacer()
                    
                    SmallPill(
                        title: viewModel.completedCountText,
                        foreground: .appPurple,
                        background: .appPurpleSoft
                    )
                }
                .padding(.top, 26)
                
                VStack(spacing: 12) {
                    ForEach(viewModel.filteredLessons) { lesson in
                        StudentLessonHistoryRow(
                            lesson: lesson,
                            isPlaying: viewModel.isPlaying(lesson),
                            viewAction: { viewModel.view(lesson) },
                            audioAction: { viewModel.toggleAudio(for: lesson) }
                        )
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
            StudentLessonDetailView(
                lesson: lesson,
                isPlaying: viewModel.isPlaying(lesson),
                audioAction: { viewModel.toggleAudio(for: lesson) }
            )
        }
    }
    
    private var summaryStrip: some View {
        HStack(spacing: 14) {
            HistoryMetricCard(
                title: "Time Learned",
                value: "54 min",
                systemImage: "clock.fill",
                tint: .appPink
            )
            
            HistoryMetricCard(
                title: "Total Spend",
                value: viewModel.totalSpendText,
                systemImage: "creditcard.fill",
                tint: .appPurple
            )
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 10) {
            PlatformIcon(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
            
            TextField("Search lessons or teachers", text: $viewModel.query)
                .font(.system(size: 14))
                .foregroundStyle(Color.appPrimaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appGrayBackground, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.025), radius: 10, x: 0, y: 5)
    }
}

struct HistoryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    
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
                    .foregroundStyle(Color.appSecondaryText)
                
                Text(value)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StudentLessonHistoryRow: View {
    let lesson: StudentLessonHistoryItem
    let isPlaying: Bool
    let viewAction: () -> Void
    let audioAction: () -> Void
    
    var body: some View {
        RoundedInfoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color.appPinkSoft)
                        .frame(width: 46, height: 46)
                        .overlay {
                            PlatformIcon(systemName: "function")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.appPink)
                        }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lesson.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.appPrimaryText)
                        
                        Text("\(lesson.teacher) • \(lesson.completedAt)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    
                    Spacer()
                    
                    Text(lesson.price)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                }
                
                Text(lesson.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineSpacing(3)
                
                HStack(spacing: 10) {
                    LessonActionButton(
                        title: "View",
                        systemImage: "doc.text.fill",
                        foreground: .appPrimaryText,
                        background: .appGrayBackground,
                        action: viewAction
                    )
                    
                    LessonActionButton(
                        title: isPlaying ? "Pause" : "Listen",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        foreground: lesson.hasAudio ? .white : .appSecondaryText,
                        background: lesson.hasAudio ? Color.appPink : Color.appGrayBackground,
                        action: audioAction
                    )
                    .disabled(!lesson.hasAudio)
                    
                    Spacer()
                    
                    SmallPill(
                        title: lesson.duration,
                        foreground: .appGreen,
                        background: .appGreenSoft
                    )
                }
            }
        }
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

struct StudentLessonDetailView: View {
    let lesson: StudentLessonHistoryItem
    let isPlaying: Bool
    let audioAction: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.appPrimaryText)
                        
                        Text("\(lesson.teacher) • \(lesson.completedAt) • \(lesson.duration)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    
                    LessonActionButton(
                        title: isPlaying ? "Pause Audio" : "Listen to Lesson",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        foreground: lesson.hasAudio ? .white : .appSecondaryText,
                        background: lesson.hasAudio ? Color.appPink : Color.appGrayBackground,
                        action: audioAction
                    )
                    .disabled(!lesson.hasAudio)
                    
                    RoundedInfoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Summary")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.appPrimaryText)
                            
                            Text(lesson.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appSecondaryText)
                                .lineSpacing(4)
                        }
                    }
                    
                    RoundedInfoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transcript Preview")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.appPrimaryText)
                            
                            Text(lesson.transcriptPreview)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appSecondaryText)
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
