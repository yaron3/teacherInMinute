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
            VStack(alignment: .trailing, spacing: 20) {
                headerTitle
                segmentPicker

                if selectedSegment == 1 {
                    summaryCards
                    nextPaymentCard
                    monthSelectorRow
                    if let selected = viewModel.selectedMonth {
                        monthDetailCard(selected)
                    }
                } else {
                    Text(LocalizationSupport.localized("Teacher profile coming soon"))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(theme.screenBackground)
        .task {
            viewModel.load()
        }
    }

    // MARK: - Header

    var headerTitle: some View {
        Text(LocalizationSupport.localized("Income and Payments"))
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Segment Picker

    var segmentPicker: some View {
        HStack(spacing: 0) {
            segmentTab(title: LocalizationSupport.localized("Teacher Profile"), icon: "person.fill", index: 0)
            segmentTab(title: LocalizationSupport.localized("Monthly Summary"), icon: "chart.bar.fill", index: 1)
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

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
                title: LocalizationSupport.localized("Current Month"),
                amount: viewModel.formattedEarnings(viewModel.currentMonthSummary?.earningsCents ?? 0),
                subtitle: LessonFormatting.minutesText(viewModel.currentMonthSummary?.minutesCount ?? 0),
                background: theme.accent
            )
            summaryCard(
                title: LocalizationSupport.localized("Total Income"),
                amount: viewModel.formattedEarnings(viewModel.totalEarningsCents),
                subtitle: String(format: LocalizationSupport.localized("%d months"), viewModel.totalMonthsActive),
                background: theme.positive
            )
        }
    }

    func summaryCard(title: String, amount: String, subtitle: String, background: Color) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(amount)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(16)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Next Payment Card

    var nextPaymentCard: some View {
        FlatCard {
            VStack(alignment: .trailing, spacing: 10) {
                Text(LocalizationSupport.localized("Next Payment"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Divider()

                paymentRow(icon: "banknote", value: viewModel.formattedEarnings(viewModel.nextPaymentCents))
                paymentRow(icon: "calendar", value: viewModel.nextPaymentDate)
                paymentRow(icon: "phone", value: viewModel.nextPaymentPhone)

                HStack {
                    Text("ביט")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.91, green: 0.25, blue: 0.36))
                        .clipShape(Capsule())
                    Spacer()
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
            VStack(alignment: .trailing, spacing: 12) {
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
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text("\(month.minutesCount) \(LocalizationSupport.localized("min")) · \(month.lessonCount) \(LocalizationSupport.localized("Lessons"))")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if !month.weeklyBreakdown.isEmpty {
                    Divider().padding(.vertical, 4)

                    Text(LocalizationSupport.localized("Weekly Breakdown"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)

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
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.formattedEarnings(week.earningsCents))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(week.label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 6)
    }
}
