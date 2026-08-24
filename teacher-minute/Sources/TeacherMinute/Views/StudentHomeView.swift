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
  @State var showingLowBalanceAlert = false
  @State var showingCouponAlert = false
  @State var showingPurchaseSummaryAlert = false
  @State var showsAskTeacher = false
  @State var showsPricingOptions: Bool
  @State var selectedPricingOptionID: String?
  @State var pendingCheckoutOption: PricingOption?
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
		self._showsPricingOptions = State(initialValue: Self.shouldShowPricingOptions(remainingMinutes: viewModel.remainingMinutes))
		self._hidesTabBar = hidesTabBar
  }
  
  var body: some View {
	homeContent
	.fullScreenCover(isPresented: $showsAskTeacher) {
	  NavigationStack {
		AskTeacherSheet(viewModel: viewModel)
		  .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
		  .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
		  .id(languagePreference)
	  }
	  .navigationTitle(LocalizationSupport.localized("Ask a Teacher"))
	}
	.task {
		  await viewModel.loadProfileIfNeeded()
		  updatePricingVisibilityForCurrentBalance()
		}
	.sheet(isPresented: isChoosingPaymentMethod) {
	  if let option = pendingCheckoutOption {
		PaymentMethodSheet(
		  methods: PaymentMethod.supported(viewModel.availablePaymentMethods, forCurrency: option.currency),
		  theme: theme
		) { method in
		  pendingCheckoutOption = nil
		  Task { await viewModel.checkout(option, method: method) }
		}
	  }
	}
  }

  // `body` is deliberately split across the properties below. As one
  // expression — ZStack, scroll content and the whole modifier chain — it
  // is more than the Swift type checker will solve, and it gives up first
  // on the Android build, where SkipUI's view types make inference costlier.
  var homeContent: some View {
	homeLayers
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
	.onChange(of: couponStateKey) { _, _ in
	  handleCouponStateChange()
	}
		.onChange(of: viewModel.purchaseSummary?.id) { _, id in
		  showingPurchaseSummaryAlert = id != nil
		  if id != nil {
			updatePricingVisibilityForCurrentBalance()
		  }
		}
		.onChange(of: viewModel.remainingMinutes) { _, _ in
		  if viewModel.purchaseSummary != nil {
			updatePricingVisibilityForCurrentBalance()
		  }
		}
  }

  var homeLayers: some View {
	ZStack {
	  homeScroll

	  searchStateOverlay
	  
#if os(Android)
	  if let result = paymentReturnStore.latestResult {
		paymentReturnOverlay(result)
		  .frame(maxWidth: .infinity, maxHeight: .infinity)
		  .zIndex(10)
	  }
#endif
	}
	.appDialog(
	  LocalizationSupport.localized("Low Balance"),
	  isPresented: $showingLowBalanceAlert,
	  message: lowBalanceMessage,
	  actions: [AppDialogAction(LocalizationSupport.localized("OK"))]
	)
	.appDialog(
	  LocalizationSupport.localized("Purchase complete"),
	  isPresented: $showingPurchaseSummaryAlert,
	  message: purchaseSummaryMessage,
	  actions: [
		AppDialogAction(LocalizationSupport.localized("OK")) {
		  viewModel.consumePurchaseSummary()
		  // The redirect flows also leave a success result behind; clear it so a
		  // stale one cannot resurface.
		  paymentReturnStore.consumeLatestResult()
		}
	  ]
	)
	.appDialog(
	  couponAlertTitle,
	  isPresented: $showingCouponAlert,
	  message: couponAlertMessage,
	  actions: [
		AppDialogAction(LocalizationSupport.localized("OK")) {
		  viewModel.resetCouponState()
		}
	  ]
	)
#if !os(Android)
	.appDialog(
	  paymentReturnStore.latestResult?.title ?? LocalizationSupport.localized("Payment"),
	  isPresented: isShowingPaymentReturnResult,
	  message: paymentReturnStore.latestResult?.message ?? "",
	  actions: [
		AppDialogAction(LocalizationSupport.localized("OK")) {
		  paymentReturnStore.consumeLatestResult()
		}
	  ]
	)
#endif
  }

  var homeScroll: some View {
	  ScrollView(.vertical, showsIndicators: false) {
	  homeSections
	}
  .background(theme.screenBackground)
	  .refreshable {
		await viewModel.refresh()
	  }
  }

  var homeSections: some View {
		VStack(alignment: .leading, spacing: 0) {
      FlatTopHeader(
        eyebrow: LocalizationSupport.localized("Welcome Back"),
        name: viewModel.name,
        avatarImageURL: viewModel.profileImageURL,
        avatarSystemImage: "person.crop.circle.fill",
        showNotificationBadge: viewModel.hasUnreadMessages,
        onMessagesDismissed: {
          Task { await viewModel.refreshUnreadMessages() }
        }
      )
      .padding(.top, 8)

		  askTeacherCard
			.padding(.top, 14)
		  
		  EmptyView() // Coupon entry hidden on the Home tab (bug #28).
			.padding(.top, 0)
		  
			  sectionHeader(title: LocalizationSupport.localized("Pricing Options"))
				.padding(.top, 24)

			  pricingControls
				.padding(.top, 10)
		  
		  statsStrip
			.padding(.top, 24)
		  
		  tipsCard
			.padding(.top, 28)
		  
		  Group {
			sectionHeader(title: LocalizationSupport.localized("Recent Lessons"), actionTitle: "")
			
		  }
		  .padding(.top, 28)
		  
      if viewModel.recentLessons.isEmpty {
        Text(LocalizationSupport.localized("No lessons yet. Ask a teacher to get started!"))
          .font(.system(size: 17))
          .foregroundStyle(theme.secondaryText)
          .padding(.top, 16)
      } else {
        FlatCard(padding: 0, outlined: true) {
          VStack(spacing: 0) {
            ForEach(viewModel.recentLessons) { lesson in
              RecentLessonRow(lesson: lesson)

              if lesson.id != viewModel.recentLessons.last?.id {
                FlatRule()
              }
            }
          }
        }
        .padding(.top, 12)
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 40)
  }
  

  @ViewBuilder
  var pricingControls: some View {
	if showsPricingOptions {
	  pricingStrip
		.transition(.opacity)
	} else {
	  topUpMinutesButton
		.transition(.opacity)
	}
  }

  var topUpMinutesButton: some View {
	Button {
	  withAnimation(.easeInOut(duration: 0.22)) {
		showsPricingOptions = true
	  }
	} label: {
	  Text(LocalizationSupport.localized("Top up minutes"))
		.font(.system(size: 15, weight: .bold))
		.foregroundStyle(theme.onAccentText)
		.frame(maxWidth: .infinity)
		.frame(height: 44)
		.background(theme.accent)
		.clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
	}
	.buttonStyle(.plain)
  }

  var pricingStrip: some View {
			  ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 16) {
				  ForEach(viewModel.pricingOptions) { option in
					PricingCard(
					  option: option,
					  isSelected: isPricingOptionSelected(option),
					  isLoading: viewModel.isStartingCheckout && viewModel.checkoutPricingOptionID == option.id,
					  onSelect: {
						selectedPricingOptionID = option.id
					  }
					) {
					  selectedPricingOptionID = option.id
					  pendingCheckoutOption = option
					}
				  }
				}
				.padding(.horizontal, 2)
				.padding(.vertical, 4)
			  }
  }

  var redeemCouponRow: some View {
	let couponBinding = Binding<String>(
	  get: { viewModel.couponCode },
	  set: { viewModel.couponCode = $0 }
	)
	let trimmedCode = viewModel.couponCode.trimmingCharacters(in: .whitespacesAndNewlines)
	let isLoading = viewModel.couponState == .loading
	let isDisabled = trimmedCode.isEmpty || isLoading
	return HStack(spacing: 10) {
	  TextField(LocalizationSupport.localized("Have a code?"), text: couponBinding)
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled(true)
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(
		  RoundedRectangle(cornerRadius: 8, style: .continuous)
			.stroke(theme.controlBorder, lineWidth: 1)
		)
		.multilineTextAlignment(.leading)
		.frame(maxWidth: .infinity, alignment: .leading)

	  Button {
		Task {
		  await viewModel.redeemCoupon()
		  if case .alreadyActivated = viewModel.couponState {
			viewModel.couponCode = ""
		  }
		}
	  } label: {
		if isLoading {
		  ProgressView()
		} else {
		  Text(LocalizationSupport.localized("Redeem"))
		}
	  }
	  .buttonStyle(.borderedProminent)
	  .disabled(isDisabled)
	}
	.frame(maxWidth: .infinity)
  }

  var couponStateKey: String {
	switch viewModel.couponState {
	case .idle: return "idle"
	case .loading: return "loading"
	case .success(let minutes): return "success-\(minutes)"
	case .alreadyActivated(let date): return "already-\(date)"
	case .invalid: return "invalid"
	case .error(let msg): return "error-\(msg)"
	}
  }

  func handleCouponStateChange() {
	switch viewModel.couponState {
	case .success, .alreadyActivated, .invalid, .error:
	  showingCouponAlert = true
	default:
	  break
	}
  }

  var couponAlertTitle: String {
	switch viewModel.couponState {
	case .success:
	  return LocalizationSupport.localized("Success")
	case .alreadyActivated:
	  return LocalizationSupport.localized("Code Already Used")
	case .invalid:
	  return LocalizationSupport.localized("Invalid Code")
	case .error:
	  return LocalizationSupport.localized("Error")
	default:
	  return ""
	}
  }

  var couponAlertMessage: String {
	switch viewModel.couponState {
	case .success(let minutes):
	  let format = LocalizationSupport.localized("Code applied! Added %d minutes.")
	  return String(format: format, minutes)
	case .alreadyActivated(let date):
	  let format = LocalizationSupport.localized("This code was already activated on %@.")
	  return String(format: format, date)
	case .invalid:
	  return LocalizationSupport.localized("This code is not valid.")
	case .error(let msg):
	  return msg
	default:
	  return ""
	}
  }

#if os(Android)
  func paymentReturnOverlay(_ result: PaymentReturnResult) -> some View {
	ZStack {
	  theme.scrim.opacity(0.34)
		.ignoresSafeArea()
	  
	  VStack(spacing: 14) {
		Text(result.title)
		  .font(.system(size: 18, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		  .multilineTextAlignment(.center)
		
		Text(result.message)
		  .font(.system(size: 14))
		  .foregroundStyle(theme.secondaryText)
		  .multilineTextAlignment(.center)
		
		Button {
		  paymentReturnStore.consumeLatestResult()
		} label: {
		  Text(LocalizationSupport.localized("OK"))
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(theme.onAccentText)
			.frame(maxWidth: .infinity)
			.frame(height: 44)
			.background(theme.accent)
			.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		}
		.buttonStyle(.plain)
		.padding(.top, 4)
	  }
	  .padding(20)
	  .frame(maxWidth: 320)
	  .background(theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	  .padding(.horizontal, 24)
	}
  }
#endif
  
  var lowBalanceMessage: String {
	let format = LocalizationSupport.localized("You have %@ remaining. You need at least 2 minutes to ask a teacher. Please buy more minutes to continue.")
	return String(format: format, LessonFormatting.minutesText(viewModel.remainingMinutes))
  }
  
  var isShowingPaymentReturnResult: Binding<Bool> {
	Binding(
	  get: {
		guard let result = paymentReturnStore.latestResult else { return false }
		// Successful payments are announced by the purchase-summary alert,
		// which also names the package and the amount charged; showing this
		// generic one too would stack two alerts on the same event.
		if case .success = result.status { return false }
		return true
	  },
	  set: { isPresented in
		if !isPresented {
		  paymentReturnStore.consumeLatestResult()
		}
	  }
	)
  }

  var purchaseSummaryMessage: String {
	guard let summary = viewModel.purchaseSummary else { return "" }
	let purchased = String(
	  format: LocalizationSupport.localized("%@ purchased for %@."),
	  summary.packageName,
	  summary.priceText
	)
	guard let minutesText = summary.minutesText else { return purchased }
	let added = String(
	  format: LocalizationSupport.localized("Added %@ to your balance."),
	  minutesText
	)
	return purchased + "\n" + added
  }

  var isChoosingPaymentMethod: Binding<Bool> {
	Binding(
	  get: { pendingCheckoutOption != nil },
	  set: { isPresented in
		if !isPresented {
		  pendingCheckoutOption = nil
		}
	  }
	)
  }

  private static let pricingAutoShowMinuteThreshold = 10

  private static func shouldShowPricingOptions(remainingMinutes: Int) -> Bool {
	remainingMinutes <= pricingAutoShowMinuteThreshold
  }

  private func updatePricingVisibilityForCurrentBalance() {
	showsPricingOptions = Self.shouldShowPricingOptions(remainingMinutes: viewModel.remainingMinutes)
  }

  private func isPricingOptionSelected(_ option: PricingOption) -> Bool {
	if let selectedPricingOptionID {
	  return selectedPricingOptionID == option.id
	}
	return option.isHighlighted
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
    case .matched(let questionId, let liveKitRoom, let liveKitToken):
      ChatSessionView(
        questionId: questionId,
        role: "student",
        title: LocalizationSupport.localized("Teacher"),
        conversationType: viewModel.activeConversationType,
        liveKitRoom: liveKitRoom,
        liveKitToken: liveKitToken,
        initialDetails: viewModel.chatInitialDetails(questionId: questionId)
      ) {
        Task {
          await viewModel.refreshAfterLessonEnded()
          updatePricingVisibilityForCurrentBalance()
          viewModel.resetSearch()
        }
      }
      .onAppear { hidesTabBar = true }
      .onDisappear { hidesTabBar = false }
    case .noMatch:
      NoMatchOverlay {
        viewModel.resetSearch()
      }
    }
  }
  
  // MARK: - Stats
  
  var statsStrip: some View {
    HStack(spacing: 12) {
      HistoryMetricCard(
        title: LocalizationSupport.localized("Time Learned"),
        value: viewModel.totalTimeLearnedText,
        systemImage: "clock.fill",
        tint: theme.primaryText
      )

      HistoryMetricCard(
        title: LocalizationSupport.localized("Total Purchased"),
        value: viewModel.totalPurchasedText,
        systemImage: "clock.badge.checkmark.fill",
        tint: theme.primaryText
      )
    }
  }
  
  // MARK: - Ask card
  
  @ViewBuilder
  var askTeacherCard: some View {
	if viewModel.remainingMinutes >= 2 {
	  Button {
		showsAskTeacher = true
	  } label: {
		askTeacherCardContent
	  }
	  .buttonStyle(.plain)
	} else {
	  Button {
		showingLowBalanceAlert = true
	  } label: {
		askTeacherCardContent
	  }
	  .buttonStyle(.plain)
  }
  }

  // Solid ink panel instead of the pink/purple gradient: one strong CTA, the
  // same role the Go Online button plays on the teacher dashboard.
  var askTeacherCardContent: some View {
    ZStack(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 0) {
        Spacer()

        Text(LocalizationSupport.localized("Ask a math teacher"))
          .font(.system(size: 26, weight: .bold))
          .foregroundStyle(theme.onAccentText)

        HStack(spacing: 6) {
          Text(String(format: LocalizationSupport.localized("%d min remaining"), viewModel.remainingMinutes))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.onAccentText.opacity(0.75))
          Text(LocalizationSupport.localized("•"))
            .font(.system(size: 14))
            .foregroundStyle(theme.onAccentText.opacity(0.5))
          Text(LocalizationSupport.localized("Per-minute billing"))
            .font(.system(size: 14))
            .foregroundStyle(theme.onAccentText.opacity(0.75))
        }
        .padding(.top, 6)
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)

      Circle()
        .fill(theme.screenBackground)
        .frame(width: 44, height: 44)
        .overlay {
          PlatformIcon(
            systemName: "arrow.right",
            size: 17,
            weight: .bold,
            color: theme.primaryText
          )
        }
        .padding(.top, 20)
        .padding(.trailing, 20)
    }
    .frame(height: 150)
    .background(theme.accent)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }
  
  // MARK: - Supporting views
  
  var tipsCard: some View {
    FlatCard(filled: theme.positiveBackground) {
      HStack(alignment: .top, spacing: 14) {
        FlatIconTile(systemName: "lightbulb.fill", size: 44, background: theme.screenBackground)

        VStack(alignment: .leading, spacing: 10) {
          Text(LocalizationSupport.localized("Tips for faster matches"))
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.primaryText)

          tipLine(LocalizationSupport.localized("Upload a clear photo of your math problem"))
          tipLine(LocalizationSupport.localized("Specify the exact topic (e.g., \u{201C}Derivatives\u{201D})"))
        }

        Spacer()
      }
    }
  }

  func tipLine(_ text: String) -> some View {
    HStack(spacing: 8) {
      PlatformIcon(systemName: "checkmark", size: 11, weight: .bold, color: theme.positive)

      Text(text)
        .font(.system(size: 13))
        .foregroundStyle(theme.secondaryText)
    }
  }
  
  func sectionHeader(title: String, actionTitle: String? = nil, action: (@MainActor @Sendable () -> Void)? = nil) -> some View {
    HStack {
      Text(LocalizationSupport.localized(title))
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.primaryText)

      Spacer()

      if let actionTitle, let action {
        Button(action: action) {
          Text(LocalizationSupport.localized(actionTitle))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.primaryText)
        }
        .buttonStyle(.plain)
      }
    }
  }
}



struct ConversationTypeChip: View {
  let title: String
  let isSelected: Bool
  var systemIcons: [String] = []
  var accent: ConversationTypeChipAccent = .pink
  let action: @MainActor @Sendable () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var accentColor: Color {
	switch accent {
	  case .pink: return theme.accent
	  case .teal: return theme.info
	}
  }
  var body: some View {
	Button(action: action) {
	  HStack(spacing: 6) {
		ForEach(systemIcons, id: \.self) { icon in
		  PlatformIcon(
			systemName: icon,
			size: 12,
			weight: .semibold,
			color: isSelected ? theme.onAccentText : theme.primaryText
		  )
		}
		Text(LocalizationSupport.localized(title))
		  .font(.system(size: 12, weight: .semibold))
		  .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
		  .lineLimit(1)
		  .minimumScaleFactor(0.75)
	  }
	  .padding(.horizontal, 12)
	  .padding(.vertical, 8)
	  .background(isSelected ? accentColor : theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	.buttonStyle(.plain)
  }
}

enum ConversationTypeChipAccent {
  case pink
  case teal
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
	  theme.screenBackground.ignoresSafeArea()
	  
	  VStack(spacing: 28) {
		avatarRing
		
		VStack(spacing: 8) {
		  Text(LocalizationSupport.localized("Searching for a teacher\u{2026}"))
			.font(.system(size: 17, weight: .semibold))
			.foregroundStyle(theme.primaryText)
		  Text(LocalizationSupport.localized("This usually takes under 30 seconds."))
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
			.multilineTextAlignment(.center)
		}
		
		Button(action: onCancel) {
		  Text(LocalizationSupport.localized("Cancel"))
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(theme.primaryText)
			.padding(.horizontal, 32)
			.padding(.vertical, 12)
			.background(theme.cardBackground)
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay {
			  RoundedRectangle(cornerRadius: 10, style: .continuous)
				.stroke(theme.controlBorder, lineWidth: 1)
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
		.stroke(theme.accent.opacity(0.18), lineWidth: 1.5)
		.frame(width: ringDiameter, height: ringDiameter)
	  
	  Circle()
		.fill(theme.accent.opacity(0.08))
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
		Circle().stroke(theme.cardBackground, lineWidth: 3)
	  }
	  .shadow(color: theme.cardShadow.opacity(0.10), radius: 6, x: 0, y: 3)
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
	  Circle().fill(theme.accentBackground)
	  PlatformIcon(
		systemName: "person.crop.circle.fill",
		size: avatarSize * 0.9,
		color: theme.accentStrong
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
	  theme.scrim.opacity(0.6).ignoresSafeArea()
	  
	  VStack(spacing: 20) {
		Circle()
		  .fill(theme.positive.opacity(0.2))
		  .frame(width: 80, height: 80)
		  .overlay {
			PlatformIcon(
			  systemName: "checkmark.circle.fill",
			  size: 44,
			  color: theme.positive
			)
		  }
		
		Text(LocalizationSupport.localized("Teacher Found!"))
		  .font(.system(size: 22, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		
		Text(String(format: LocalizationSupport.localized("Your session is ready.\nRoom: %@"), liveKitRoom))
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
		  .multilineTextAlignment(.center)
		
		Button(action: onDismiss) {
		  Text(LocalizationSupport.localized("Done"))
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(theme.onAccentText)
			.frame(maxWidth: .infinity)
			.frame(height: 48)
			.background(theme.positive)
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
	  theme.scrim.opacity(0.6).ignoresSafeArea()
	  
	  VStack(spacing: 20) {
		Circle()
		  .fill(theme.cardBackground)
		  .frame(width: 80, height: 80)
		  .overlay {
			PlatformIcon(
			  systemName: "person.slash.fill",
			  size: 36,
			  color: theme.secondaryText
			)
		  }
		
		Text(LocalizationSupport.localized("No Teachers Available"))
		  .font(.system(size: 20, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		
		Text(LocalizationSupport.localized("All teachers are busy right now.\nTry again in a few minutes."))
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
		  .multilineTextAlignment(.center)
		
		Button(action: onDismiss) {
		  Text(LocalizationSupport.localized("OK"))
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(theme.onAccentText)
			.frame(maxWidth: .infinity)
			.frame(height: 48)
			.background(theme.accent)
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
	  theme.cardBackground.opacity(0.9).ignoresSafeArea()
	  
	  VStack(spacing: 20) {
		Circle()
		  .fill(theme.accent.opacity(0.18))
		  .frame(width: 80, height: 80)
		  .overlay {
			PlatformIcon(
			  systemName: "exclamationmark.triangle.fill",
			  size: 34,
			  color: theme.accent
			)
		  }
		
		Text(LocalizationSupport.localized("Could Not Send Question"))
		  .font(.system(size: 20, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		
		Text(LocalizationSupport.localized(message))
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
		  .multilineTextAlignment(.center)
		
		Button(action: onDismiss) {
		  Text(LocalizationSupport.localized("OK"))
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(theme.onAccentText)
			.frame(maxWidth: .infinity)
			.frame(height: 48)
			.background(theme.accent)
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
  let isSelected: Bool
  let isLoading: Bool
  let onSelect: @MainActor @Sendable () -> Void
  let onCheckout: @MainActor @Sendable () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    // Highlighted plans are marked with a heavier ink border rather than a
    // second accent colour.
    FlatCard(outlined: true) {
      VStack(alignment: .leading, spacing: 0) {
        if option.isHighlighted {
          FlatBadge(title: option.name)
        } else {
          FlatChip(title: option.name, outlined: true)
        }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if let minutesText = option.minutesText {
            Text(minutesText)
#if os(Android)
              .font(.system(size: 24, weight: .bold))
#else
              .font(.system(size: 30, weight: .bold))
#endif
              .foregroundStyle(theme.primaryText)
          }

          Text(option.priceText)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.secondaryText)
        }
        .padding(.top, 12)

        Text(LocalizationSupport.localized(option.description))
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
          .lineSpacing(4)
          .padding(.top, 8)
          .frame(maxWidth: .infinity, alignment: .topLeading)

        Button(action: onCheckout) {
          HStack(spacing: 8) {
            if isLoading {
              ProgressView()
                .scaleEffect(0.8)
                .tint(theme.onAccentText)
            }

            Text(isLoading ? LocalizationSupport.localized("checkout_connecting") : LocalizationSupport.localized("Checkout"))
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(theme.onAccentText)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(theme.accent)
          .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .padding(.top, 16)
      }
      .frame(width: 176)
    }
    .overlay {
      RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
        .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 2)
    }
    .onTapGesture(perform: onSelect)
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
    // Borderless row; the screen supplies the list container and separators.
    HStack(spacing: 14) {
      ProfileAvatarView(
        imageURL: lesson.teacherImageURL,
        size: 44,
        fallbackSystemImage: "person.crop.circle.fill",
        background: theme.cardBackground,
        tint: theme.primaryText
      )

      VStack(alignment: .leading, spacing: 3) {
        Text(lesson.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.primaryText)

        Text(String(format: LocalizationSupport.localized("%@ • %@"), lesson.teacher, lesson.time))
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 3) {
        Text(LocalizationSupport.localized("Solved"))
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(theme.positive)

        Text(lesson.duration)
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(theme.screenBackground)
  }
}

#if os(iOS)
#Preview {
  StudentHomeView(viewModel: MockStudentHomeViewModel())
}
struct StudentHomeView_Previews: PreviewProvider {
  static var previews: some View {
	StudentHomeView(viewModel: MockStudentHomeViewModel())
  }
}

/*
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
 */
#endif

// RedeemCouponSheet view (assumed to be inside this file or imported)
// Instructions: Update TextField placeholder to "Have a code?"
// and add success alert + auto-dismiss on success

struct RedeemCouponSheet: View {
  @State  var couponCode: String = ""
  @State  var state: RedeemCouponState = .idle
  let onRedeem: (String) async -> RedeemCouponState
  let onDismiss: @MainActor @Sendable () -> Void
  
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  
  @State  var showSuccessAlert = false
  @State  var successMinutes: Int = 0
  
  var body: some View {
	NavigationStack {
	  VStack(spacing: 20) {
		TextField(LocalizationSupport.localized("Have a code?"), text: $couponCode)
		  .textFieldStyle(.roundedBorder)
		  .textInputAutocapitalization(.never)
		  .autocorrectionDisabled(true)
		  .padding(.horizontal)
		
		Button {
		  Task {
			state = await onRedeem(couponCode)
		  }
		} label: {
		  if case .loading = state {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.accent)
			  .frame(maxWidth: .infinity)
		  } else {
			Text(LocalizationSupport.localized("Redeem"))
			  .frame(maxWidth: .infinity)
		  }
		}
		.buttonStyle(.borderedProminent)
		.disabled(couponCode.isEmpty || (state == .loading))
		.padding(.horizontal)
		
		switch state {
		  case .error(let message):
			Text(LocalizationSupport.localized(message))
			  .foregroundColor(theme.accent)
			  .multilineTextAlignment(.center)
			  .padding(.horizontal)
		  default:
			EmptyView()
		}
		
		Spacer()
	  }
	  .navigationTitle(LocalizationSupport.localized("Redeem Code"))
	  .toolbar {
		ToolbarItem(placement: .cancellationAction) {
		  Button(LocalizationSupport.localized("Cancel")) {
			onDismiss()
		  }
		}
	  }
	}
	.onChange(of: state) { oldValue, newValue in
	  if case .success(let minutes) = newValue {
		successMinutes = minutes
		showSuccessAlert = true
	  }
	}
	.appDialog(
	  LocalizationSupport.localized("Success"),
	  isPresented: $showSuccessAlert,
	  message: String(format: LocalizationSupport.localized("Code applied! Added %d minutes."), successMinutes),
	  actions: [AppDialogAction(LocalizationSupport.localized("OK")) { onDismiss() }]
	)
  }
}

// RedeemCouponState enum assumed definition (for context)
enum RedeemCouponState: Equatable {
  case idle
  case loading
  case success(Int) // Int = minutes added
  case error(String)
}
