//
//  StudentLessonHistoryView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import SwiftUI

struct StudentLessonHistoryView: View {
    @State var viewModel = StudentLessonHistoryViewModel()
    @State var isLoading = true
    @State var presentingLesson: LessonHistoryItem?
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                lessonSections
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
                amountLabel: "Cost",
                isPlaying: viewModel.isPlaying(lesson),
                initialDetails: nil,
                showsAmount: false,
                audioAction: { viewModel.toggleAudio(for: lesson) }
            )
        }
    }

    // Split out of `body` so the type checker solves the list and the
    // navigation chrome separately — together they are more than it will
    // solve in one expression on the Android build.
    private var lessonSections: some View {
                VStack(alignment: .leading, spacing: 0) {
                    FlatTopHeader(
                        eyebrow: LocalizationSupport.localized("Lesson History"),
                        name: viewModel.studentName,
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
                        placeholder: LocalizationSupport.localized("Search lessons or teachers"),
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
                                        iconName: "function",
                                        isLoading: viewModel.isLoading(lesson),
                                        showsAmount: false
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
    
    private var summaryStrip: some View {
        // Students only see the time they consumed — spend/cost is intentionally
        // omitted here.
        HStack(spacing: 12) {
            HistoryMetricCard(
                title: "Time Learned",
                value: viewModel.totalTimeLearnedText,
                systemImage: "clock.fill",
                tint: theme.primaryText
            )
            .frame(maxWidth: .infinity)
        }
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
        FlatCard {
            VStack(alignment: .leading, spacing: 10) {
                FlatIconTile(systemName: systemImage, size: 40, background: theme.screenBackground)

                Text(LocalizationSupport.localized(title))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)

                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.primaryText)
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
    var isLoading = false
    /// Students are only shown the time they consumed, so the monetary amount is
    /// hidden for them and shown only to teachers (their earnings).
    var showsAmount = true
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(isLoading)
    }

    /// Borderless row — the enclosing screen supplies the list container and the
    /// hairline separators, matching the grouped-list treatment.
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatarView(
                imageURL: lesson.otherParticipantImageURL,
                size: 44,
                fallbackSystemImage: iconName,
                background: theme.cardBackground,
                tint: theme.primaryText
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text(isLoading ? LocalizationSupport.localized("Loading session details") : "\(lesson.otherParticipant) \u{2022} \(lesson.completedAt)")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.primaryText)
                } else if showsAmount {
                    Text(lesson.amount)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }

                Text(lesson.duration)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            }

            PlatformIcon(
                systemName: "chevron.right",
                size: 13,
                weight: .medium,
                color: theme.secondaryText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // An opaque background keeps the whole row tappable; `contentShape` is
        // not available in Skip's SwiftUI.
        .background(theme.screenBackground)
        .opacity(isLoading ? 0.72 : 1)
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
    let initialDetails: LessonDetails?
    /// Whether to show the monetary amount card. Hidden for students, who only
    /// see the time they consumed.
    var showsAmount = true
    let audioAction: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    @State var messages: [LessonMessage]
    @State var questionText: String
    @State var questionPhotoUrls: [String]
    @State var isLoading: Bool

    init(
        lesson: LessonHistoryItem,
        amountLabel: String,
        isPlaying: Bool,
        initialDetails: LessonDetails?,
        showsAmount: Bool = true,
        audioAction: @escaping () -> Void
    ) {
        self.lesson = lesson
        self.amountLabel = amountLabel
        self.isPlaying = isPlaying
        self.initialDetails = initialDetails
        self.showsAmount = showsAmount
        self.audioAction = audioAction
        _messages = State(initialValue: initialDetails?.messages ?? [])
        _questionText = State(initialValue: initialDetails?.questionText ?? "")
        _questionPhotoUrls = State(initialValue: initialDetails?.questionPhotoUrls ?? lesson.questionPhotoUrls)
        _isLoading = State(initialValue: initialDetails == nil)
    }

     var viewerRole: String {
        amountLabel == "Earnings" ? "teacher" : "student"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(theme.primaryText)

                        Text("\(lesson.otherParticipant) \u{2022} \(lesson.completedAt) \u{2022} \(lesson.duration)")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }

                    HStack(spacing: 14) {
                        if showsAmount {
                            HistoryMetricCard(
                                title: amountLabel,
                                value: lesson.amount,
                                systemImage: "creditcard.fill",
                                tint: theme.accentBackground
                            )
                        }

                        HistoryMetricCard(
                            title: "Duration",
                            value: lesson.duration,
                            systemImage: "clock.fill",
                            tint: theme.accent
                        )
                    }

                    LessonActionButton(
                        title: isPlaying ? "Pause Audio" : "Listen to Lesson",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        foreground: lesson.hasAudio ? theme.cardBackground : theme.secondaryText,
                        background: lesson.hasAudio ? theme.accent : theme.cardBackground,
                        action: audioAction
                    )
                    .disabled(!lesson.hasAudio)

                    if !questionText.isEmpty || !questionPhotoUrls.isEmpty {
                        RoundedInfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    PlatformIcon(systemName: "pin.fill", size: 12, weight: .semibold, color: theme.warning)
                                    Text(LocalizationSupport.localized("Original Question"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(theme.warning)
                                }
                                if !questionText.isEmpty {
                                    // The question can carry equations built
                                    // with the algebra keyboard, so it is drawn
                                    // by the same renderer the chat bubbles and
                                    // the teacher's preview use.
                                    FormulaAwareText(
                                        text: questionText,
                                        textColor: theme.primaryText
                                    )
                                }
                                ForEach(questionPhotoUrls, id: \.self) { url in
                                    CachedRemoteImage(url: url, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    if !lesson.summary.isEmpty {
                        RoundedInfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LocalizationSupport.localized("Summary"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.primaryText)

                                Text(lesson.summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineSpacing(4)
                            }
                        }
                    }

                    if !messages.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(LocalizationSupport.localized("Chat Messages"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.primaryText)

                            VStack(spacing: 8) {
                                ForEach(messages) { message in
                                    LessonMessageBubble(
                                        message: message,
                                        isMine: message.senderRole == viewerRole,
                                        avatarImageURL: message.senderRole == viewerRole ? lesson.currentUserImageURL : lesson.otherParticipantImageURL
                                    )
                                }
                            }
                            .padding(12)
                            .background(theme.cardBackground.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    if !lesson.transcriptPreview.isEmpty {
                        RoundedInfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LocalizationSupport.localized("Transcript Preview"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.primaryText)

                                Text(lesson.transcriptPreview)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineSpacing(4)
                            }
                        }
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(.systemBackground))
            .navigationTitle(LocalizationSupport.localized("Lesson"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if initialDetails == nil {
                    await loadLessonDetails()
                }
            }
        }
    }

    private func loadLessonDetails() async {
        do {
            let details = try await HistoryModel.shared.fetchQuestionDetails(questionId: lesson.questionId)
            questionText = details.text
            questionPhotoUrls = details.photoUrls
            messages = try await HistoryModel.shared.fetchLessonMessages(questionId: lesson.questionId)
        } catch {
            // Basic lesson info is already displayed
        }
        isLoading = false
    }
}

struct LessonMessageBubble: View {
    let message: LessonMessage
    let isMine: Bool
    let avatarImageURL: String
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 54) }
            if !isMine { avatar }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                messageContent

                Text(timeText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if isMine { avatar }
            if !isMine { Spacer(minLength: 54) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.kind {
        case "image":
            CachedRemoteImage(url: message.text, contentMode: .fit)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        case "audio":
            HStack(spacing: 6) {
                PlatformIcon(systemName: "waveform", size: 14, weight: .semibold, color: isMine ? theme.outgoingBubbleText : theme.incomingBubbleText)
                Text(LocalizationSupport.localized("Audio message"))
                    .font(.system(size: 14))
                    .foregroundStyle(isMine ? theme.outgoingBubbleText : theme.incomingBubbleText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isMine ? theme.outgoingBubbleBackground : theme.incomingBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        case "video":
            HStack(spacing: 6) {
                PlatformIcon(systemName: "video.fill", size: 14, weight: .semibold, color: isMine ? theme.outgoingBubbleText : theme.incomingBubbleText)
                Text(LocalizationSupport.localized("Video message"))
                    .font(.system(size: 14))
                    .foregroundStyle(isMine ? theme.outgoingBubbleText : theme.incomingBubbleText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isMine ? theme.outgoingBubbleBackground : theme.incomingBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        default:
            // Formulas sent during the lesson are stored as the LaTeX between
            // `$$` markers, so the replay uses the same renderer the live chat
            // does rather than printing the markup back at the student.
            FormulaAwareText(
                text: message.text,
                textColor: isMine ? theme.outgoingBubbleText : theme.incomingBubbleText,
                lineSpacing: 3
            )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
				.background(isMine ? theme.outgoingBubbleBackground : theme.incomingBubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }

    private var avatar: some View {
        ProfileAvatarView(
            imageURL: avatarImageURL,
            size: 24,
            fallbackSystemImage: "person.crop.circle.fill",
            background: isMine ? theme.accentBackground : theme.positiveBackground,
            tint: isMine ? theme.accentStrong : theme.positive
        )
    }

    private var timeText: String {
        guard message.createdAt > .distantPast else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.createdAt)
    }
}

#if os(iOS)
struct StudentLessonHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        StudentLessonHistoryView()
    }
}
#endif
