//
//  TeacherEarningsView.swift
//  teacher-minute
//
//  The teacher's income and payments, on the brand's tab screen: this month
//  and all time, the next payment, where payouts go, and each month's lessons.
//

import SwiftUI

struct TeacherEarningsView: View {
    @State var viewModel = TeacherEarningsViewModel()
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        BrandTabScreen {
            VStack(spacing: 0) {
                BrandPageHeader(label: "", title: viewModel.earningsScreenTitle) {
                    BrandMenuButton()
                }
                ScrollView(.vertical, showsIndicators: false) {
                    content
                }
            }
            // On a plain stack inside the screen, not on `BrandTabScreen`; see
            // there.
            .task {
                viewModel.load()
            }
            .sheet(isPresented: $viewModel.isEditingPayoutMethod) {
                TeacherPayoutMethodSheet(
                    viewModel: viewModel,
                    method: $viewModel.payoutMethodDraft,
                    availableTypes: viewModel.availablePayoutMethodTypes,
                    banks: viewModel.banks,
                    isSaving: viewModel.isSavingPayoutMethod,
                    errorMessage: viewModel.payoutMethodErrorMessage,
                    profilePhone: viewModel.profilePhone,
                    isConnectingPayPal: viewModel.isConnectingPayPal,
                    onUseProfilePhone: { viewModel.useProfilePhone() },
                    onConnectPayPal: { Task { await viewModel.connectPayPalPayoutAccount() } },
                    onSave: { Task { await viewModel.savePayoutMethod() } },
                    onCancel: { viewModel.cancelPayoutMethodEditing() }
                )
            }
            .appDialog(
                viewModel.updateProfileDialogTitle,
                isPresented: $viewModel.isOfferingProfilePhoneUpdate,
                message: viewModel.updateProfileDialogMessage,
                actions: [
                    AppDialogAction(viewModel.updateLabel, kind: .primary) {
                        Task { await viewModel.confirmProfilePhoneUpdate() }
                    },
                    AppDialogAction(viewModel.notNowLabel, kind: .cancel) {
                        viewModel.declineProfilePhoneUpdate()
                    },
                ]
            )
        }
    }

    // Split out of `body`, which the type checker would otherwise have to
    // solve in one piece.
    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandPageHero(title: viewModel.earningsScreenTitle)
            summaryCards
            if viewModel.hasPendingPayment {
                nextPaymentCard
            }
            payoutMethodCard
            if viewModel.hasEarningsData {
                monthSelectorRow
                if let selected = viewModel.selectedMonth {
                    monthDetailCard(selected)
                }
            } else if viewModel.showsEmptyState {
                emptyState
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    // MARK: - Payout Method

    var payoutMethodCard: some View {
        FlatCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(viewModel.payoutMethodTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.onDarkFill)
                    Spacer()
                    if viewModel.showsPayoutMethodAction {
                        Button {
                            viewModel.editPayoutMethod()
                        } label: {
                            Text(viewModel.payoutMethodActionLabel)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.brandActionBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }

                BrandRule()

                if let method = viewModel.payoutMethod {
                    HStack(spacing: 12) {
                        FlatIconTile(systemName: method.type.systemImage, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(method.type.displayName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.onDarkFill)
                            Text(viewModel.payoutMethodSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.brandSecondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                } else if let pending = viewModel.payoutMethodAwaitingDetails {
                    // A destination was chosen while completing the profile, so
                    // the card names it and asks for the details rather than
                    // telling the teacher they have no method at all.
                    HStack(spacing: 12) {
                        FlatIconTile(systemName: pending.systemImage, size: 40, tint: theme.brandSecondaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pending.displayName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.onDarkFill)
                            Text(viewModel.completePayoutDetailsText)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.brandSecondaryText)
                        }
                        Spacer()
                    }
                } else {
                    Text(viewModel.noPayoutMethodText)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.brandSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        Text(viewModel.emptyStateText)
            .font(.system(size: 15))
            .foregroundStyle(theme.brandSecondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 30)
    }

    // MARK: - Summary Cards

    var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: viewModel.currentMonthTitle,
                amount: viewModel.currentMonthEarningsText,
                subtitle: viewModel.currentMonthMinutesText,
                tint: theme.brandActionBackground
            )
            summaryCard(
                title: viewModel.totalIncomeTitle,
                amount: viewModel.totalEarningsText,
                subtitle: viewModel.totalMonthsActiveText,
                tint: theme.brandSuccess
            )
        }
    }

    func summaryCard(title: String, amount: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.brandSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(tint)
                // The loading placeholder is a word, not an amount, and would
                // wrap instead of scaling without an explicit single line.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.brandSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
    }

    // MARK: - Next Payment Card

    var nextPaymentCard: some View {
        FlatCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.nextPaymentTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.onDarkFill)
                    .frame(maxWidth: .infinity, alignment: .leading)

                BrandRule()

                paymentRow(icon: "banknote", value: viewModel.formattedEarnings(viewModel.nextPaymentCents))
                paymentRow(icon: "calendar", value: viewModel.nextPaymentDate)
                if let method = viewModel.payoutMethod {
                    paymentRow(icon: method.type.systemImage, value: viewModel.payoutMethodSummary)

                    HStack {
                        Text(method.type.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.onBrandAction)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(theme.brandActionBackground)
                            .clipShape(Capsule())
                        Spacer()
                    }
                }
            }
        }
    }

    func paymentRow(icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(theme.onDarkFill)
            Spacer()
            PlatformIcon(systemName: icon, size: 16, weight: .regular, color: theme.brandActionBackground)
        }
    }

    // MARK: - Month Selector

    var monthSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.months) { month in
                    let isSelected = viewModel.selectedMonthId == month.id
                    Button {
                        viewModel.selectedMonthId = month.id
                    } label: {
                        Text(month.shortName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? theme.onBrandAction : theme.brandSecondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSelected ? theme.brandActionBackground : theme.brandCardSurface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Month Detail

    func monthDetailCard(_ month: MonthSummary) -> some View {
        FlatCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    if month.isCurrentMonth {
                        Text(viewModel.inProgressLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.onBrandAction)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.brandSuccess)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(month.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.onDarkFill)
                }

                Text(viewModel.formattedEarnings(month.earningsCents))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.brandActionBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(viewModel.monthSummaryText(minutes: month.minutesCount, lessons: month.lessonCount))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.brandSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !month.weeklyBreakdown.isEmpty {
                    BrandRule()
                        .padding(.vertical, 4)

                    Text(viewModel.weeklyBreakdownTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.onDarkFill)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(month.weeklyBreakdown) { week in
                            weekRow(week)
                            if let lastId = month.weeklyBreakdown.last?.id, lastId != week.id {
                                BrandRule()
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    func weekRow(_ week: WeekSummary) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LessonFormatting.minutesText(week.minutesCount))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.brandSecondaryText)
                Text(viewModel.weekLessonsText(week.lessonCount))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.brandSecondaryText)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formattedEarnings(week.earningsCents))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.onDarkFill)
                Text(week.label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.brandSecondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 8)
    }
}
