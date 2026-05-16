//
//  StudentHomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct StudentHomeView: View {
    @State var viewModel: any StudentHomeViewModeling
    @State var showingAskSheet = false
    @Binding var hidesTabBar: Bool
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    init(
        viewModel: any StudentHomeViewModeling = StudentHomeViewModel(),
        hidesTabBar: Binding<Bool> = .constant(false)
    ) {
        self._viewModel = State(initialValue: viewModel)
        self._hidesTabBar = hidesTabBar
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    AppTopHeader(
                        avatarSystemImage: "person.crop.circle.fill",
                        eyebrow: "Welcome back",
                        name: viewModel.name,
                        showNotificationBadge: true
                    )
                    .padding(.top, 18)

                    askTeacherCard
                        .padding(.top, 20)

                    sectionHeader(title: "Pricing Options", actionTitle: "Compare all") {}
                        .padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.pricingOptions) { option in
                                PricingCard(option: option) {
                                    viewModel.selectTier(option)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                    .padding(.top, 10)

                    statsStrip
                        .padding(.top, 24)

                    tipsCard
                        .padding(.top, 28)

                    sectionHeader(title: "Recent Lessons", actionTitle: "View all") {
                        viewModel.viewAllLessons()
                    }
                    .padding(.top, 28)

                    if viewModel.recentLessons.isEmpty {
                        RoundedInfoCard {
                            HStack(spacing: 12) {
                                PlatformIcon(systemName: "clock")
                                    .font(.system(size: 16))
                                    .foregroundStyle(theme.appSecondaryText)
                                Text("No lessons yet. Ask a teacher to get started!")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.appSecondaryText)
                            }
                        }
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.recentLessons) { lesson in
                                RecentLessonRow(lesson: lesson)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))

            searchStateOverlay
        }
        .sheet(isPresented: $showingAskSheet) {
            AskTeacherSheet(viewModel: viewModel, isPresented: $showingAskSheet)
        }
        .task {
            await viewModel.loadProfileIfNeeded()
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    var searchStateOverlay: some View {
        switch viewModel.searchState {
        case .idle:
            EmptyView()
        case .error(let message):
            ErrorOverlay(message: message) {
                viewModel.resetSearch()
            }
        case .searching:
            SearchingOverlay {
                Task { await viewModel.cancelSearch() }
            }
        case .matched(let questionId, _, _):
            ChatSessionView(
                questionId: questionId,
                role: "student",
                title: "Teacher",
                initialDetails: viewModel.chatInitialDetails(questionId: questionId)
            ) {
                viewModel.resetSearch()
            }
            .onAppear {
                hidesTabBar = true
            }
            .onDisappear {
                hidesTabBar = false
            }
        case .noMatch:
            NoMatchOverlay {
                viewModel.resetSearch()
            }
        }
    }

    // MARK: - Stats

    var statsStrip: some View {
        HStack(spacing: 14) {
            HistoryMetricCard(
                title: "Time Learned",
                value: viewModel.totalTimeLearnedText,
                systemImage: "clock.fill",
                tint: theme.appPink
            )

            HistoryMetricCard(
                title: "Total Spend",
                value: viewModel.totalSpendText,
                systemImage: "creditcard.fill",
                tint: theme.appPurple
            )
        }
    }

    // MARK: - Ask card

    var askTeacherCard: some View {
        Button {
            showingAskSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [theme.appPink, theme.appPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 116, height: 116)
                    .offset(x: 34, y: -26)

                VStack(alignment: .leading, spacing: 0) {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 58, height: 58)
                        .overlay {
                            PlatformIcon(systemName: "building.columns.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Spacer()

                    Text("Ask a math teacher")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Connect instantly • Per-minute billing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                    .overlay {
                        PlatformIcon(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.appPink)
                    }
                    .padding(.top, 36)
                    .padding(.trailing, 20)
            }
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.appPink.opacity(0.25), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Supporting views

    var tipsCard: some View {
        RoundedInfoCard {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(theme.yellow.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(systemName: "lightbulb.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.appOrange)
                    }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tips for faster matches")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    tipLine("Upload a clear photo of your math problem")
                    tipLine("Specify the exact topic (e.g., \u{201C}Derivatives\u{201D})")
                }

                Spacer()
            }
        }
    }

    func tipLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            PlatformIcon(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.appGreen)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.appSecondaryText)
        }
    }

    func sectionHeader(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.appPink)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Ask Teacher Sheet

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
                                    Text(topic.capitalized)
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
                        ConversationTypeChip(title: "Text", isSelected: true) {
                            conversationType = "text"
                        }
                        ConversationTypeChip(title: "Audio + Text", isSelected: false) {}
                            .opacity(0.45)
                        ConversationTypeChip(title: "Video + Audio + Text", isSelected: false) {}
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
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(theme.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isQuestionFocused {
                        MathSymbolRow(text: $questionText, isFocused: $isQuestionFocused)
                    }

                    Text("\(questionText.count) / 10 min chars")
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background( theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(20)
            .navigationTitle("Ask a Teacher")
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

struct ConversationTypeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ?theme.appCardBackground: theme.appPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? theme.appPink : theme.appGrayBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - State Overlays

struct SearchingOverlay: View {
    let onCancel: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ZStack {
            theme.appPrimaryText.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Searching for a teacher\u{2026}")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Text("This usually takes under 30 seconds.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(32)
        }
    }
}

struct MatchedOverlay: View {
    let liveKitRoom: String
    let liveKitToken: String
    let onDismiss: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ZStack {
            theme.appPrimaryText.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Circle()
                    .fill(theme.appGreen.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay {
                        PlatformIcon(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.appGreen)
                    }

                Text("Teacher Found!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your session is ready.\nRoom: \(liveKitRoom)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.appGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(32)
        }
    }
}

struct NoMatchOverlay: View {
    let onDismiss: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ZStack {
            theme.appPrimaryText.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Circle()
                    .fill(theme.appSecondaryText.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        PlatformIcon(systemName: "person.slash.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(theme.appSecondaryText)
                    }

                Text("No Teachers Available")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("All teachers are busy right now.\nTry again in a few minutes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(32)
        }
    }
}

struct ErrorOverlay: View {
    let message: String
    let onDismiss: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ZStack {
            theme.appPrimaryText.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Circle()
                    .fill(theme.appPink.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .overlay {
                        PlatformIcon(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(theme.appPink)
                    }

                Text("Could Not Send Question")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(32)
        }
    }
}

// MARK: - Supporting Cards

struct PricingCard: View {
    let option: PricingOption
    let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        RoundedInfoCard {
            VStack(alignment: .leading, spacing: 0) {
                SmallPill(
                    title: option.name,
					foreground: option.isHighlighted ?theme.appCardBackground: theme.appPink,
                    background: option.isHighlighted ? theme.appPurple : theme.appPinkSoft
                )

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(option.price)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    Text("/min")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.appSecondaryText)
                }
                .padding(.top, 18)

                Text(option.description)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.appSecondaryText)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .frame(height: 48, alignment: .top)

                Button(action: action) {
                    Text("Select Tier")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(option.isHighlighted ?theme.appCardBackground: theme.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(option.isHighlighted ? theme.appPurple : theme.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .frame(width: 172)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(option.isHighlighted ? theme.appPurple : Color.clear, lineWidth: 2)
        }
    }
}

struct RecentLessonRow: View {
    let lesson: RecentLesson
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        RoundedInfoCard {
            HStack(spacing: 12) {
                Circle()
                    .fill(theme.appPurpleSoft)
                    .frame(width: 50, height: 50)
                    .overlay {
                        PlatformIcon(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.appPurple)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    Text("\(lesson.teacher) \u{2022} \(lesson.time)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.appSecondaryText)
                }

                Spacer()

                VStack(spacing: 6) {
                    SmallPill(title: "Solved", foreground: theme.appGreen, background: theme.appGreenSoft)

                    Text(lesson.duration)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
                }
            }
        }
    }
}

#if os(iOS)
struct StudentHomeView_Previews: PreviewProvider {
    static var previews: some View {
        StudentHomeView(viewModel: MockStudentHomeViewModel())
    }
}
#endif
