//
//  TeacherEarningsView.swift
//  teacher-minute
//

import SwiftUI

struct TeacherEarningsView: View {
    @State var viewModel = TeacherEarningsViewModel()
    @State var selectedSegment: Int = 1
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerTitle
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
            .padding(20)
        }
        .background(theme.screenBackground)
        .task {
            viewModel.load()
        }
        .sheet(isPresented: $viewModel.isEditingPayoutMethod) {
            TeacherPayoutMethodSheet(
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
            LocalizationSupport.localized("Update your profile?"),
            isPresented: $viewModel.isOfferingProfilePhoneUpdate,
            message: LocalizationSupport.localized("Save this number as your profile phone number too?"),
            actions: [
                AppDialogAction(LocalizationSupport.localized("Update"), kind: .primary) {
                    Task { await viewModel.confirmProfilePhoneUpdate() }
                },
                AppDialogAction(LocalizationSupport.localized("Not now"), kind: .cancel) {
                    viewModel.declineProfilePhoneUpdate()
                },
            ]
        )
    }

    // MARK: - Payout Method

    var payoutMethodCard: some View {
        FlatCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(viewModel.payoutMethodTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    if viewModel.showsPayoutMethodAction {
                        Button {
                            viewModel.editPayoutMethod()
                        } label: {
                            Text(viewModel.payoutMethodActionLabel)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.info)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                if let method = viewModel.payoutMethod {
                    HStack(spacing: 12) {
                        FlatIconTile(
                            systemName: method.type.systemImage,
                            size: 40,
                            tint: theme.accent,
                            background: theme.screenBackground
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(method.type.displayName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.primaryText)
                            Text(viewModel.payoutMethodSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                } else {
                    Text(viewModel.noPayoutMethodText)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        Text(viewModel.emptyStateText)
            .font(.system(size: 14))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 30)
    }

    // MARK: - Header

    var headerTitle: some View {
        Text(LocalizationSupport.localized("Income and Payments"))
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Segment Picker

//    var segmentPicker: some View {
//        HStack(spacing: 0) {
//            segmentTab(title: LocalizationSupport.localized("Teacher Profile"), icon: "person.fill", index: 0)
//            segmentTab(title: LocalizationSupport.localized("Monthly Summary"), icon: "chart.bar.fill", index: 1)
//        }
//        .background(theme.cardBackground)
//        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//    }

    func segmentTab(title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedSegment == index
        return Button {
            selectedSegment = index
        } label: {
            HStack(spacing: 6) {
                PlatformIcon(systemName: icon, size: 13, weight: .semibold, color: isSelected ? .white : theme.secondaryText)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? theme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(3)
    }

    // MARK: - Summary Cards

    var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: viewModel.currentMonthTitle,
                amount: viewModel.currentMonthEarningsText,
                subtitle: viewModel.currentMonthMinutesText,
                background: theme.accent
            )
            summaryCard(
                title: viewModel.totalIncomeTitle,
                amount: viewModel.totalEarningsText,
                subtitle: viewModel.totalMonthsActiveText,
                background: theme.positive
            )
        }
    }

    func summaryCard(title: String, amount: String, subtitle: String, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                // The loading placeholder is a word, not an amount, and would
                // wrap instead of scaling without an explicit single line.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Next Payment Card

    var nextPaymentCard: some View {
        FlatCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizationSupport.localized("Next Payment"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                paymentRow(icon: "banknote", value: viewModel.formattedEarnings(viewModel.nextPaymentCents))
                paymentRow(icon: "calendar", value: viewModel.nextPaymentDate)
                if let method = viewModel.payoutMethod {
                    paymentRow(icon: method.type.systemImage, value: viewModel.payoutMethodSummary)

                    HStack {
                        Text(method.type.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(theme.accent)
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
                .font(.system(size: 14))
                .foregroundStyle(theme.primaryText)
            Spacer()
            PlatformIcon(systemName: icon, size: 16, weight: .regular, color: theme.secondaryText)
        }
    }

    // MARK: - Month Selector

    var monthSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.months) { month in
                    Button {
                        viewModel.selectedMonthId = month.id
                    } label: {
                        Text(month.shortName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(viewModel.selectedMonthId == month.id ? .white : theme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedMonthId == month.id ? theme.accent : theme.cardBackground)
                            .clipShape(Capsule())
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
                        Text(LocalizationSupport.localized("In progress"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.positive)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(month.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }

                Text(viewModel.formattedEarnings(month.earningsCents))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(month.minutesCount) \(LocalizationSupport.localized("min")) · \(month.lessonCount) \(LocalizationSupport.localized("Lessons"))")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !month.weeklyBreakdown.isEmpty {
                    Divider().padding(.vertical, 4)

                    Text(LocalizationSupport.localized("Weekly Breakdown"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(month.weeklyBreakdown) { week in
                            weekRow(week)
                            if let lastId = month.weeklyBreakdown.last?.id, lastId != week.id {
                                Divider()
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
                    .foregroundStyle(theme.secondaryText)
                Text("\(week.lessonCount) \(LocalizationSupport.localized("Lessons"))")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formattedEarnings(week.earningsCents))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(week.label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 6)
    }
}
