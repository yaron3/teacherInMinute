//
//  StudentHomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct StudentHomeView: View {
    @State var viewModel: any StudentHomeViewModeling
    @State var paymentReturnStore = PaymentReturnStore.shared
    @State var showingAskSheet = false
    @State var showingLowBalanceAlert = false
    @Binding var hidesTabBar: Bool
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
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
                        eyebrow: "Welcome Back",
                        name: viewModel.name,
                        avatarImageURL: viewModel.profileImageURL,
                        showNotificationBadge: viewModel.hasUnreadMessages,
                        onMessagesDismissed: {
                            Task { await viewModel.refreshUnreadMessages() }
                        }
                    )
                    .padding(.top, 18)

                    askTeacherCard
                        .padding(.top, 20)

                    sectionHeader(title: "Pricing Options")
                        .padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.pricingOptions) { option in
                                PricingCard(
                                    option: option,
                                    isLoading: viewModel.isStartingCheckout && viewModel.checkoutPricingOptionID == option.id
                                ) {
                                    Task { await viewModel.checkout(option) }
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

                    Group {
                            sectionHeader(title: "Recent Lessons", actionTitle: "")
				
                    }
                    .padding(.top, 28)

                    if viewModel.recentLessons.isEmpty {
                        RoundedInfoCard {
                            HStack(spacing: 12) {
                                PlatformIcon(
                                    systemName: "clock",
                                    size: 16,
                                    color: theme.appSecondaryText
                                )
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
                .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
                .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
                .id(languagePreference)
        }
        .task {
            await viewModel.loadProfileIfNeeded()
        }
        .onChange(of: viewModel.checkoutURL) { _, url in
            guard let url else { return }
            logger.info("[PaymentReturn] opening checkoutURL=\(url.absoluteString)")
            openURL(url)
            viewModel.checkoutDidOpen()
            viewModel.consumeCheckoutURL()
        }
        .onChange(of: paymentReturnStore.resultVersion) { _, _ in
            guard let result = paymentReturnStore.latestResult else { return }
            logger.info("[PaymentReturn] StudentHome observed resultVersion=\(paymentReturnStore.resultVersion) rawURL=\(result.rawURL.absoluteString)")
            Task { await viewModel.handlePaymentReturn(result) }
        }
        .onChange(of: scenePhase) { _, phase in
            logger.info("[PaymentReturn] StudentHome scenePhase changed active=\(phase == .active) awaiting=\(viewModel.isAwaitingPaymentReturn) resultVersion=\(paymentReturnStore.resultVersion)")
            guard phase == .active else { return }
            handleActiveAfterExternalCheckout()
        }
        .alert(LocalizationSupport.localized("Low Balance"), isPresented: $showingLowBalanceAlert) {
            Button(LocalizationSupport.localized("OK"), role: .cancel) {}
        } message: {
            Text(lowBalanceMessage)
        }
        .alert(paymentReturnStore.latestResult?.title ?? LocalizationSupport.localized("Payment"), isPresented: isShowingPaymentReturnResult) {
            Button(LocalizationSupport.localized("OK"), role: .cancel) {
                paymentReturnStore.consumeLatestResult()
            }
        } message: {
            Text(paymentReturnStore.latestResult?.message ?? "")
        }
    }

    var lowBalanceMessage: String {
        let format = LocalizationSupport.localized("You have %@ remaining. You need at least 2 minutes to ask a teacher. Please buy more minutes to continue.")
        return String(format: format, LessonFormatting.minutesText(viewModel.remainingMinutes))
    }

    var isShowingPaymentReturnResult: Binding<Bool> {
        Binding(
            get: { paymentReturnStore.latestResult != nil },
            set: { isPresented in
                if !isPresented {
                    paymentReturnStore.consumeLatestResult()
                }
            }
        )
    }

    private func handleActiveAfterExternalCheckout() {
        guard viewModel.isAwaitingPaymentReturn else { return }
        let resultVersionBeforeWait = paymentReturnStore.resultVersion
        logger.info("[PaymentReturn] app active after checkout; waiting for deep link resultVersion=\(resultVersionBeforeWait)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard viewModel.isAwaitingPaymentReturn else {
                logger.info("[PaymentReturn] fallback skipped; no longer awaiting return")
                return
            }
            guard paymentReturnStore.resultVersion == resultVersionBeforeWait, paymentReturnStore.latestResult == nil else {
                logger.info("[PaymentReturn] fallback skipped; payment result arrived resultVersion=\(paymentReturnStore.resultVersion)")
                return
            }
            logger.info("[PaymentReturn] no payment return URL arrived after wait; refreshing balance before fallback")
            let confirmedByBalance = await viewModel.handleCheckoutReturnWithoutResult()
            if confirmedByBalance {
                paymentReturnStore.handleConfirmedWithoutReturnURL()
            } else {
                logger.info("[PaymentReturn] balance did not update after checkout return; showing pending confirmation")
                paymentReturnStore.handleMissingReturn()
            }
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
                title: LocalizationSupport.localized("Teacher"),
                initialDetails: viewModel.chatInitialDetails(questionId: questionId)
            ) {
                Task {
                    await viewModel.refreshAfterLessonEnded()
                    viewModel.resetSearch()
                }
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
                title: "Total Purchased",
                value: viewModel.totalPurchasedText,
                systemImage: "clock.badge.checkmark.fill",
                tint: theme.appPurple
            )
        }
    }

    // MARK: - Ask card

    var askTeacherCard: some View {
        Button {
            if viewModel.remainingMinutes >= 2 {
                showingAskSheet = true
            } else {
                showingLowBalanceAlert = true
            }
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
                            PlatformIcon(
                                systemName: "building.columns.fill",
                                size: 24,
                                weight: .semibold,
                                color: theme.appPrimaryText
                            )
                        }

                    Spacer()

                    Text("Ask a math teacher")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    HStack(spacing: 6) {
                        Text(String(format: LocalizationSupport.localized("%lld min remaining"), Int64(viewModel.remainingMinutes)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.appGrayBackground.opacity(0.6))
                        Text("Per-minute billing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.appGrayBackground.opacity(0.9))
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .fill(theme.appPrimaryText)
                    .frame(width: 44, height: 44)
                    .overlay {
                        PlatformIcon(
                            systemName: "arrow.right",
                            size: 17,
                            weight: .bold,
                            color: theme.appGrayBackground
                        )
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
					  PlatformIcon(systemName: "lightbulb.fill", size: 14, weight: .semibold,color: theme.appOrange)
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
            PlatformIcon(systemName: "checkmark", size: 10, weight: .bold,
						 color: theme.appGreen)

            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .foregroundStyle(theme.appSecondaryText)
        }
    }

    func sectionHeader(title: String, actionTitle: String? = nil, action: (@MainActor @Sendable () -> Void)? = nil) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(LocalizedStringKey(actionTitle))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.appPink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}



struct ConversationTypeChip: View {
    let title: String
    let isSelected: Bool
    let action: @MainActor @Sendable () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
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
    let avatarURLs: [URL?]
    let onCancel: @MainActor @Sendable () -> Void

    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    @State  var ringRotation = 0.0
    @State  var cycleIndex = 0

    private let slotCount = 6
    private let ringDiameter: CGFloat = 240
    private let avatarSize: CGFloat = 60

    init(avatarURLs: [URL?] = [], onCancel: @escaping @MainActor @Sendable () -> Void) {
        self.avatarURLs = avatarURLs
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            theme.appGrayBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                avatarRing

                VStack(spacing: 8) {
                    Text("Searching for a teacher\u{2026}")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
                    Text("This usually takes under 30 seconds.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.appSecondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(theme.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.appBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(32)
        }
        .task {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                cycleIndex += 1
            }
        }
    }

    private var avatarRing: some View {
        ZStack {
            Circle()
                .stroke(theme.appPink.opacity(0.18), lineWidth: 1.5)
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .fill(theme.appPink.opacity(0.08))
                .frame(width: ringDiameter * 0.45, height: ringDiameter * 0.45)

            ForEach(0..<slotCount, id: \.self) { index in
                avatarSlot(index: index)
            }
            .rotationEffect(.degrees(ringRotation))
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    @ViewBuilder
    private func avatarSlot(index: Int) -> some View {
        let angle = (Double(index) / Double(slotCount)) * 360.0 - 90.0
        let radius = (ringDiameter - avatarSize) / 2
        let x = cos(angle * .pi / 180) * Double(radius)
        let y = sin(angle * .pi / 180) * Double(radius)

        avatarImage(for: index)
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(theme.appCardBackground, lineWidth: 3)
            }
            .shadow(color: theme.appPrimaryText.opacity(0.10), radius: 6, x: 0, y: 3)
            .rotationEffect(.degrees(-ringRotation))
            .offset(x: CGFloat(x), y: CGFloat(y))
    }

    @ViewBuilder
    private func avatarImage(for index: Int) -> some View {
        if let url = currentURL(for: index) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderAvatar
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(theme.appPurpleSoft)
            PlatformIcon(
                systemName: "person.crop.circle.fill",
                size: avatarSize * 0.9,
                color: theme.appPurple
            )
        }
    }

    private func currentURL(for index: Int) -> URL? {
        guard !avatarURLs.isEmpty else { return nil }
        let urlIndex = (cycleIndex + index) % avatarURLs.count
        return avatarURLs[urlIndex]
    }
}

struct MatchedOverlay: View {
    let liveKitRoom: String
    let liveKitToken: String
    let onDismiss: @MainActor @Sendable () -> Void
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
                        PlatformIcon(
                            systemName: "checkmark.circle.fill",
                            size: 44,
                            color: theme.appGreen
                        )
                    }

                Text("Teacher Found!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.appPrimaryText)

                Text(String(format: LocalizationSupport.localized("Your session is ready.\nRoom: %@"), liveKitRoom))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
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
    let onDismiss: @MainActor @Sendable () -> Void
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
                        PlatformIcon(
                            systemName: "person.slash.fill",
                            size: 36,
                            color: theme.appSecondaryText
                        )
                    }

                Text("No Teachers Available")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.appPrimaryText)

                Text("All teachers are busy right now.\nTry again in a few minutes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
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
    let onDismiss: @MainActor @Sendable () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ZStack {
            theme.appCardBackground.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 20) {
                Circle()
                    .fill(theme.appPink.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .overlay {
                        PlatformIcon(
                            systemName: "exclamationmark.triangle.fill",
                            size: 34,
                            color: theme.appPink
                        )
                    }

                Text("Could Not Send Question")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.appPrimaryText)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.appPrimaryText)
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
    let isLoading: Bool
    let action: @MainActor @Sendable () -> Void
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
				  if let minutesText = option.minutesText {
					HStack(spacing: 4) {
					  PlatformIcon(systemName: "clock.fill", size: 28, color: theme.appGreen)
					  Text(minutesText)
						#if os(Android)
                            .font(.system(size: 22, weight: .bold))
#else
                            .font(.system(size: 28, weight: .bold))
#endif
						.foregroundStyle(theme.appGreen)
					}
					.padding(.top, 4)
					
				  }
				  
                    Text(option.priceText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
				  
//                    Text(priceSuffix(for: option))
//					.font(.system(size: 11, weight: .semibold))
//                        .foregroundStyle(theme.appSecondaryText)
                }
                .padding(.top, 8)
				.padding(.leading, 5)
			  
                Text(LocalizedStringKey(option.description))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.appSecondaryText)
                    .lineSpacing(4)
                    .padding(.top, 8)
					.frame(maxWidth: .infinity, alignment: .topLeading)

                Button(action: action) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(option.isHighlighted ? theme.appCardBackground : theme.appPrimaryText)
                        }

                        Text(isLoading ? LocalizationSupport.localized("Connecting...") : LocalizationSupport.localized("Checkout"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(option.isHighlighted ?theme.appCardBackground: theme.appPrimaryText)
                    }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(option.isHighlighted ? theme.appPurple : theme.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(.top, 14)
            }
            .frame(width: 172)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(option.isHighlighted ? theme.appPurple : Color.clear, lineWidth: 2)
        }
    }

    private func priceSuffix(for option: PricingOption) -> String {
        if let period = option.type.billingPeriodText {
            return period
        }
        return LocalizationSupport.localized("/min")
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
                ProfileAvatarView(
                    imageURL: lesson.teacherImageURL,
                    size: 50,
                    fallbackSystemImage: "person.crop.circle.fill",
                    background: theme.appPurpleSoft,
                    tint: theme.appPurple
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    Text(String(format: LocalizationSupport.localized("%@ • %@"), lesson.teacher, lesson.time))
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
			.background(theme.appCardBackground)
        }
    }
}

#if os(iOS)
struct StudentHomeView_Previews: PreviewProvider {
    static var previews: some View {
        StudentHomeView(viewModel: MockStudentHomeViewModel())
    }
}

struct StudentSearchHomeView_Previews: PreviewProvider {
  static var previews: some View {

	StudentHomeView(viewModel: MockStudentHomeViewModel(searchState: .searching(questionId: "fdjhfdhdf")))
  }
}

struct ErrorOverlay_Previews: PreviewProvider {
  static var previews: some View {
    ErrorOverlay(message: "Could not connect to the teacher service. Please check your connection and try again.") {}
  }
}

struct PricingCard_Previews: PreviewProvider {
  static var previews: some View {
    pricingCards
      .previewDisplayName("English")

    pricingCards
      .environment(\.locale, Locale(identifier: "he"))
      .environment(\.layoutDirection, .rightToLeft)
      .previewDisplayName("Hebrew RTL")
  }

   static var pricingCards: some View {
    HStack(spacing: 16) {
      PricingCard(
        option: PricingOption(
          id: "starter",
          name: "מתחילים",
          priceCents: 5000,
          currency: "ILS",
          type: .payAsYouGo,
          description: "עזרה קצרה בשיעורי בית ושאלות תרגול.",
          isHighlighted: false,
          sortOrder: 0,
          purchaseSKU: nil,
          minutesGranted: 30
        ),
        isLoading: false
      ) {}

      PricingCard(
        option: PricingOption(
          id: "popular",
          name: "פופולרי",
          priceCents: 9000,
          currency: "ILS",
          type: .payAsYouGo,
          description: "יותר זמן להסברים מעמיקים ופתרון מודרך.",
          isHighlighted: true,
          sortOrder: 1,
          purchaseSKU: nil,
          minutesGranted: 60
        ),
        isLoading: true
      ) {}
    }
    .padding()
    .background(Color(.systemBackground))
  }
}
#endif
