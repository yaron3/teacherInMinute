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
  @State var showsNotificationExplainer = false
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
	  .navigationTitle(viewModel.askATeacherSheetTitle)
	}
	.sheet(isPresented: $showsNotificationExplainer) {
	  NotificationPermissionExplainerView {
		NotificationPromptStore.markExplanationShown()
		showsNotificationExplainer = false
	  }
	  .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
	  .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
	  .id(languagePreference)
	}
	.task {
	  await viewModel.loadProfileIfNeeded()
	}
	.sheet(isPresented: isChoosingPaymentMethod) {
	  if let option = pendingCheckoutOption {
		PaymentMethodSheet(
		  methods: PaymentMethod.supported(viewModel.availablePaymentMethods, forCurrency: option.currency),
		  theme: theme,
		  savedPayPalEmail: viewModel.savedPayPalEmail
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
	  viewModel.lowBalanceAlertTitle,
	  isPresented: $showingLowBalanceAlert,
	  message: viewModel.lowBalanceMessage,
	  actions: [AppDialogAction(viewModel.okLabel)]
	)
	.appDialog(
	  viewModel.purchaseCompleteTitle,
	  isPresented: $showingPurchaseSummaryAlert,
	  message: viewModel.purchaseSummaryMessage,
	  actions: [
		AppDialogAction(viewModel.okLabel) {
		  viewModel.consumePurchaseSummary()
		  // The redirect flows also leave a success result behind; clear it so a
		  // stale one cannot resurface.
		  paymentReturnStore.consumeLatestResult()
		}
	  ]
	)
	.appDialog(
	  viewModel.couponAlertTitle,
	  isPresented: $showingCouponAlert,
	  message: viewModel.couponAlertMessage,
	  actions: [
		AppDialogAction(viewModel.okLabel) {
		  viewModel.resetCouponState()
		}
	  ]
	)
#if !os(Android)
	.appDialog(
	  paymentReturnStore.latestResult?.title ?? viewModel.paymentFallbackTitle,
	  isPresented: isShowingPaymentReturnResult,
	  message: paymentReturnStore.latestResult?.message ?? "",
	  actions: [
		AppDialogAction(viewModel.okLabel) {
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
      studentHero

      studentSectionHeader(
        title: viewModel.availableSubjectsTitle,
        caption: viewModel.registeredTeacherCountText.isEmpty ? nil : viewModel.registeredTeacherCountText
      )
      .padding(.top, 28)

      popularSubjectsGrid
        .padding(.top, 14)

      studentSectionHeader(
        title: viewModel.teachersOnlineNowTitle,
        caption: viewModel.teachersOnlineNowCaption
      )
      .padding(.top, 30)

      onlineTeachersGrid
        .padding(.top, 14)

      howItWorksPanel
        .padding(.top, 30)

      studentOverviewCards
        .padding(.top, 18)

      if !viewModel.pricingOptions.isEmpty {
        studentSectionHeader(title: viewModel.creditsTitle)
          .padding(.top, 30)

        pricingGrid
          .padding(.top, 14)
      }

//      recentLessonsSection
//        .padding(.top, 30)
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 40)
  }

  var studentHero: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
		PlatformIcon(systemName: "books.vertical.fill", size: 19, weight: .semibold, color: theme.primaryText)
          Text(viewModel.appDisplayName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.primaryText)
          
		Spacer()
        }
      .padding(.horizontal, 18)
      .padding(.top, 18)
      .padding(.bottom, 18)

      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .center, spacing: 18) {
          

          VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.greetingText)
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(theme.info)

            Text(viewModel.appDisplayName)
              .font(.system(size: 36, weight: .bold))
              .foregroundStyle(theme.primaryText)
              .lineLimit(2)
              .minimumScaleFactor(0.75)

            Text(viewModel.connectPromiseText)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(theme.primaryText.opacity(0.65))
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
		  balancePill
        }

        //onlineStatusBar
		onlineTeacherStatus

        heroAskTeacherButton

        if !viewModel.pricePerMinuteText.isEmpty {
          Text(viewModel.pricePerMinuteText)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .padding(22)
      .padding(.top, 20)
    }
    .background(theme.accentBackground)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  var balancePill: some View {
    VStack(spacing: 8) {
      Text("\(viewModel.remainingMinutes)")
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(theme.warning)
      Text(viewModel.minutesLabel)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(theme.primaryText.opacity(0.65))
    }
    .frame(width: 92, height: 120)
    .background(theme.cardBackground.opacity(0.2))
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
        .stroke(theme.cardBackground.opacity(0.2), lineWidth: 1)
    }
  }

  @ViewBuilder
  var heroAskTeacherButton: some View {
    if viewModel.remainingMinutes >= 2 {
      Button {
        showsAskTeacher = true
      } label: {
        heroAskTeacherButtonContent
      }
      .buttonStyle(.plain)
    } else {
      Button {
        showingLowBalanceAlert = true
      } label: {
        heroAskTeacherButtonContent
      }
      .buttonStyle(.plain)
    }
  }

  var heroAskTeacherButtonContent: some View {
    HStack(spacing: 10) {
      PlatformIcon(systemName: "hand.raised.fill", size: 22, weight: .bold, color: theme.ctaForeground)
      Text(viewModel.askQuestionNowLabel)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.ctaForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 76)
    .background(theme.ctaBackground)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  var onlineTeacherStatus: some View {
	HStack {
	  Spacer()
	  Text(viewModel.onlineTeachersCountText)
		.font(.system(size: 18, weight: .bold))
		.foregroundStyle(theme.positive)
	  Spacer()
	}
  }
  var onlineStatusBar: some View {
    HStack(spacing: 10) {
      FlatStatusDot(color: theme.positive, size: 16)
      Text(viewModel.onlineTeachersCountText)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.positive)
      Spacer()
      // Measured by the backend; nothing is claimed until there is a
      // measurement to claim.
      if !viewModel.averageConnectText.isEmpty {
        Text(viewModel.averageConnectText)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.primaryText.opacity(0.55))
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 54)
    .background(theme.positiveBackground.opacity(0.18))
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
        .stroke(theme.positive.opacity(0.35), lineWidth: 1)
    }
  }

  var studentOverviewCards: some View {
    HStack(spacing: 12) {
      lastLessonInfoCard

      dashboardInfoCard(
        title: viewModel.yourBalanceTitle,
        value: LessonFormatting.minutesText(viewModel.remainingMinutes),
        detail: viewModel.leftToLearnDetail,
        systemImage: "creditcard.fill",
        actionTitle: viewModel.buyMoreLabel,
        action: selectFirstPricingOption
      )
    }
  }

  var lastLessonInfoCard: some View {
    FlatCard(outlined: true) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          PlatformIcon(systemName: "calendar", size: 16, weight: .semibold, color: theme.secondaryText)
          Text(viewModel.lastLessonCardTitle)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        }

        if let lesson = viewModel.recentLessons.last {
          Text(lesson.teacher)
            .font(.system(size: lesson.teacher.count > 8 ? 20 : 28, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(lesson.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)

          // The score this student actually gave. Unrated lessons show no
          // stars rather than a full row.
          if lesson.hasRating {
            RatingStarsView(rating: Double(lesson.rating), size: 10)
          }

          Text(lesson.duration)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        } else {
          Text(viewModel.noLessonsText)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(viewModel.noLessonsSubtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(minHeight: 170, alignment: .top)
    }
  }

  var subjectCatalogTints: [String: Color] {
    [
      "math": theme.accent,
      "physics": theme.warning,
      "chemistry": theme.positive,
      "statistics": theme.info,
      "computer_science": theme.accent,
      "biology": theme.danger,
    ]
  }

  var popularSubjectsGrid: some View {
    LazyVGrid(columns: twoColumnGrid, spacing: 14) {
      // Titles, subtopics and teacher counts all come from the view model,
      // which builds them from the published catalog and live presence.
      ForEach(viewModel.subjects) { subject in
        subjectCard(subject, tint: subjectCatalogTints[subject.key] ?? theme.accent)
      }
    }
  }

  /// Fill plus the foreground that is actually readable on it — `warning` and
  /// `info` are bright in both schemes and need dark ink, while `accent` and
  /// `positive` invert across schemes.
  var onlineTeacherTints: [(fill: Color, foreground: Color)] {
    [
      (theme.accent, theme.onAccentText),
      (theme.warning, theme.onBrightFill),
      (theme.positive, theme.onAccentText),
      (theme.info, theme.onBrightFill),
    ]
  }

  var onlineTeachersGrid: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 14) {
        let teachers = viewModel.onlineTeachers
        if teachers.isEmpty {
          Text(viewModel.noTeachersOnlineText)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        } else {
          ForEach(teachers) { teacher in
            let index = teachers.firstIndex(where: { $0.id == teacher.id }) ?? 0
            let tint = onlineTeacherTints[index % onlineTeacherTints.count]
            onlineTeacherCard(
              name: teacher.name,
              subject: teacher.subject,
              initial: teacher.initial,
              tint: tint.fill,
              tintForeground: tint.foreground
            )
            .frame(width: 155)
          }
        }
      }
    }
  }

  var howItWorksPanel: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text(viewModel.howItWorksTitle)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
		.frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 24) {
        howItWorksStep(
          number: 1,
          title: viewModel.howItWorksStep1Title,
          subtitle: viewModel.howItWorksStep1Subtitle,
          tint: theme.info
        )
        howItWorksStep(
          number: 2,
          title: viewModel.connectStepTitle,
          subtitle: viewModel.howItWorksStep2Subtitle,
          tint: theme.warning
        )
        howItWorksStep(
          number: 3,
          title: viewModel.howItWorksStep3Title,
          subtitle: viewModel.howItWorksStep3Subtitle,
          tint: theme.accent
        )
        howItWorksStep(
          number: 4,
          title: viewModel.howItWorksStep4Title,
          subtitle: viewModel.pricePerMinuteText.isEmpty
            ? viewModel.howItWorksStep4SubtitleFallback
            : viewModel.pricePerMinuteText,
          tint: theme.positive
        )
      }
    }
    .padding(22)
    .background(theme.accentStrong)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  func howItWorksStep(number: Int, title: String, subtitle: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Circle()
        .stroke(tint, lineWidth: 3)
        .frame(width: 46, height: 46)
        .overlay {
          Text("\(number)")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tint)
        }

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(2)
          .minimumScaleFactor(0.82)

        Text(subtitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.onDarkFill.opacity(0.6))
          .lineLimit(2)
          .minimumScaleFactor(0.82)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var pricingGrid: some View {
    LazyVGrid(columns: twoColumnGrid, spacing: 14) {
      ForEach(viewModel.pricingOptions) { option in
        creditOptionCard(option)
      }
    }
  }

//  var recentLessonsSection: some View {
//    VStack(alignment: .leading, spacing: 12) {
//      studentSectionHeader(title: LocalizationSupport.localized("Recent Lessons"))
//
//      if viewModel.recentLessons.isEmpty {
//        Text(LocalizationSupport.localized("No lessons yet. Ask a teacher to get started!"))
//          .font(.system(size: 15, weight: .semibold))
//          .foregroundStyle(theme.secondaryText)
//          .frame(maxWidth: .infinity, alignment: .leading)
//          .padding(.vertical, 4)
//      } else {
//        FlatCard(padding: 0, outlined: true) {
//          VStack(spacing: 0) {
//            ForEach(viewModel.recentLessons) { lesson in
//              RecentLessonRow(lesson: lesson)
//
//              if lesson.id != viewModel.recentLessons.last?.id {
//                FlatRule()
//              }
//            }
//          }
//        }
//      }
//    }
//  }


  var twoColumnGrid: [GridItem] {
    [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
  }

  func selectFirstPricingOption() {
    pendingCheckoutOption = viewModel.pricingOptions.first
  }

  func dashboardInfoCard(title: String, value: String, detail: String, systemImage: String, actionTitle: String? = nil, action: (@MainActor @Sendable () -> Void)? = nil) -> some View {
    FlatCard(outlined: true) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          PlatformIcon(systemName: systemImage, size: 16, weight: .semibold, color: theme.secondaryText)
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        }

        Text(value)
          .font(.system(size: value.count > 8 ? 20 : 34, weight: .bold))
          .foregroundStyle(systemImage == "creditcard.fill" ? theme.info : theme.primaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(detail)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.secondaryText)
          .lineLimit(2)
          .minimumScaleFactor(0.8)

        if let actionTitle, let action {
          Button(action: action) {
            Text(actionTitle)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(theme.info)
              .frame(maxWidth: .infinity)
              .frame(height: 42)
              .background(theme.info.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous)
                  .stroke(theme.info, lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
        }
      }
      .frame(minHeight: 170, alignment: .top)
    }
  }

  func studentSectionHeader(title: String, caption: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.primaryText)
      Spacer()
      if let caption {
        Text(caption)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(caption == viewModel.teachersOnlineNowCaption ? theme.info : theme.secondaryText)
      }
    }
  }

  func subjectCard(_ subject: StudentSubject, tint: Color) -> some View {
    FlatCard(outlined: true) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text(subject.title)
              .font(.system(size: 20, weight: .bold))
              .foregroundStyle(theme.primaryText)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
            // A live count of teachers online for this subject, so one is
            // enough to say so — the old copy only lit up past 30, a threshold
            // that made sense only against the invented counts.
            Text(viewModel.teacherCountText(for: subject))
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(tint)
          }
          Spacer()
          FlatIconTile(systemName: subject.systemImage, size: 48, tint: tint, background: tint.opacity(0.12))
        }

        if !subject.topics.isEmpty {
          Text(subject.topics)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
        }

        HStack(spacing: 7) {
          FlatStatusDot(color: subject.hasTeachersOnline ? theme.positive : theme.secondaryText, size: 9)
          Text(viewModel.teacherAvailabilityText(for: subject))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        }
      }
      .frame(minHeight: 150, alignment: .top)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(tint)
          .frame(height: 4)
          .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
          .offset(y: -16)
      }
    }
  }

  func onlineTeacherCard(name: String, subject: String, initial: String, tint: Color, tintForeground: Color) -> some View {
    FlatCard(outlined: true) {
      VStack(alignment: .center, spacing: 10) {
        ZStack(alignment: .bottomTrailing) {
          Circle()
            .fill(tint.opacity(0.82))
            .frame(width: 74, height: 74)
            .overlay {
              Text(initial)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(tintForeground)
            }
          Circle()
            .fill(theme.positive)
            .frame(width: 18, height: 18)
            .overlay { Circle().stroke(theme.screenBackground, lineWidth: 3) }
        }

        Text(name)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.primaryText)
          .lineLimit(1)

        Text(subject)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(tint)
          .lineLimit(1)

//        Button {
//          showsAskTeacher = true
//        } label: {
//          Text(viewModel.meetLabel)
//            .font(.system(size: 14, weight: .bold))
//            .foregroundStyle(theme.info)
//            .frame(maxWidth: .infinity)
//            .frame(height: 36)
//            .background(theme.info.opacity(0.12))
//            .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
//        }
//        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 210)
    }
  }

  func creditOptionCard(_ option: PricingOption) -> some View {
    Button {
      pendingCheckoutOption = option
    } label: {
      FlatCard(outlined: true) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(viewModel.localizedName(for: option))
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
            Spacer()
            PlatformIcon(systemName: "creditcard.fill", size: 16, weight: .semibold, color: theme.info)
          }

          Text(option.minutesText ?? option.priceText)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

          Text(option.minutesText == nil ? viewModel.localizedDescription(for: option) : option.priceText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 112, alignment: .top)
      }
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isStartingCheckout)
  }

  var pricingStrip: some View {
		  ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 16) {
			  ForEach(viewModel.pricingOptions) { option in
				PricingCard(
				  option: option,
				  isLoading: viewModel.isStartingCheckout && viewModel.checkoutPricingOptionID == option.id
				) {
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
	  TextField(viewModel.couponPlaceholder, text: couponBinding)
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
		  Text(viewModel.redeemLabel)
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
		  Text(viewModel.okLabel)
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
        title: viewModel.chatTeacherTitle,
        conversationType: viewModel.activeConversationType,
        liveKitRoom: liveKitRoom,
        liveKitToken: liveKitToken,
        initialDetails: viewModel.chatInitialDetails(questionId: questionId)
      ) {
        Task {
          await viewModel.refreshAfterLessonEnded()
          viewModel.resetSearch()
          // After the student's first lesson, offer notifications behind a
          // custom explanation (the system prompt only appears if they opt in).
          if await NotificationPromptStore.shouldPresentExplanation() {
            showsNotificationExplainer = true
          }
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
        title: viewModel.timeLearnedTitle,
        value: viewModel.totalTimeLearnedText,
        systemImage: "clock.fill",
        tint: theme.primaryText
      )

      HistoryMetricCard(
        title: viewModel.totalPurchasedTitle,
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

        Text(viewModel.askMathTeacherLabel)
          .font(.system(size: 26, weight: .bold))
          .foregroundStyle(theme.onAccentText)

        HStack(spacing: 6) {
          Text(viewModel.remainingMinutesText)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.onAccentText.opacity(0.75))
          Text("•")
            .font(.system(size: 14))
            .foregroundStyle(theme.onAccentText.opacity(0.5))
          Text(viewModel.perMinuteBillingLabel)
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
          Text(viewModel.tipsTitle)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.primaryText)

          tipLine(viewModel.tip1Text)
          tipLine(viewModel.tip2Text)
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
      Text(title)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.primaryText)

      Spacer()

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
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
  /// Readable on `accentColor`: `info` is bright in both schemes, `accent`
  /// inverts across them.
  var accentForeground: Color {
	switch accent {
	  case .pink: return theme.onAccentText
	  case .teal: return theme.onBrightFill
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
			color: isSelected ? accentForeground : theme.primaryText
		  )
		}
		Text(LocalizationSupport.localized(title))
		  .font(.system(size: 12, weight: .semibold))
		  .foregroundStyle(isSelected ? accentForeground : theme.primaryText)
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
  let isLoading: Bool
  let action: @MainActor @Sendable () -> Void
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

        Button(action: action) {
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
        .stroke(option.isHighlighted ? theme.accent : Color.clear, lineWidth: 2)
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
