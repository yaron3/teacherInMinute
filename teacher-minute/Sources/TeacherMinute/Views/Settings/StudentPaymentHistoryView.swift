//
//  StudentPaymentHistoryView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

/// A student's purchases of minutes, month by month, in the brand's look —
/// Instant Teacher is the only app with student payments.
struct StudentPaymentHistoryView: View {
    let viewModel: any SettingsViewModeling
    @State  var monthSections: [PaymentHistoryMonthSection] = []
    @State  var isLoading = true
    private let authService = AuthService()

    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            BrandSubpage(
                label: viewModel.settingsTitle,
                title: viewModel.settingsPageTitle(SettingsDestination.studentPayments.title),
                backLabel: viewModel.backLabel
            ) {
                BrandPageHero(title: SettingsDestination.studentPayments.title)
                content
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    var content: some View {
        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(theme.onDarkFill)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if monthSections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "cart")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(theme.brandActionBackground)
                    .frame(width: 36, height: 36)
                Text(viewModel.noPaymentsTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.onDarkFill)
                Text(viewModel.noPaymentsSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.brandSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .brandCard()
        } else {
            ForEach(monthSections) { section in
                monthCard(section)
            }
        }
    }

    /// A month's total above the card of its purchases.
    func monthCard(_ section: PaymentHistoryMonthSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(section.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.brandSecondaryText)
                Spacer(minLength: 0)
                Text(section.totalText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.onDarkFill)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(section.entries) { entry in
                    if entry.id != section.entries.first?.id {
                        BrandRule()
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.onDarkFill)
                                .lineLimit(1)
                            Text(entry.dateText)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.brandSecondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.amountText)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.brandActionBackground)
                    }
                }
            }
            .brandCard()
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard let uid = authService.currentUserID else { return }
        do {
            let currencyCode = try await HistoryModel.shared.fetchPurchasedCurrencyCode(for: uid)
            let purchases = try await HistoryModel.shared.fetchPurchases(for: uid)
            monthSections = Self.groupByMonth(purchases, currencyCode: currencyCode)
        } catch {
            logger.error("[PaymentHistory] failed loading: \(error.localizedDescription)")
        }
    }

    /// Files each purchase under the month it was paid for. This used to group
    /// lessons by when they were taught, which answered a different question:
    /// a student who bought a package in March and used it through May saw the
    /// money spread across three months, and never saw the payment itself.
    private static func groupByMonth(_ purchases: [HistoryPurchase], currencyCode: String) -> [PaymentHistoryMonthSection] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d, HH:mm"

        var purchasesByKey: [String: [HistoryPurchase]] = [:]
        var monthTitleByKey: [String: String] = [:]

        for purchase in purchases {
            let comps = calendar.dateComponents([.year, .month], from: purchase.purchasedAt)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            var existing = purchasesByKey[key] ?? []
            existing.append(purchase)
            purchasesByKey[key] = existing
            if monthTitleByKey[key] == nil {
                monthTitleByKey[key] = monthFormatter.string(from: purchase.purchasedAt)
            }
        }

        return purchasesByKey.keys
            .sorted(by: >)
            .compactMap { key in
                guard let monthPurchases = purchasesByKey[key], let title = monthTitleByKey[key] else { return nil }
                let sorted = monthPurchases.sorted { $0.purchasedAt > $1.purchasedAt }
                let totalCents = sorted.reduce(0) { $0 + $1.amountCents }
                let monthCurrencyCode = sorted.first?.currencyCode ?? currencyCode
                let entries = sorted.map { purchase in
                    PaymentHistoryEntry(
                        id: purchase.id,
                        title: purchase.title,
                        dateText: dayFormatter.string(from: purchase.purchasedAt),
                        amountText: LessonFormatting.currencyText(cents: purchase.amountCents, currencyCode: purchase.currencyCode)
                    )
                }
                return PaymentHistoryMonthSection(
                    id: key,
                    title: title,
                    totalText: LessonFormatting.currencyText(cents: totalCents, currencyCode: monthCurrencyCode),
                    entries: entries
                )
            }
    }
}

 struct PaymentHistoryMonthSection: Identifiable {
    let id: String
    let title: String
    let totalText: String
    let entries: [PaymentHistoryEntry]
}

 struct PaymentHistoryEntry: Identifiable {
    let id: String
    let title: String
    let dateText: String
    let amountText: String
}
