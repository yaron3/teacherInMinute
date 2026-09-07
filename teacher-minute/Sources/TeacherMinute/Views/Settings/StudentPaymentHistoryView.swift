//
//  StudentPaymentHistoryView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct StudentPaymentHistoryView: View {
    let viewModel: any SettingsViewModeling
    @State  var monthSections: [PaymentHistoryMonthSection] = []
    @State  var isLoading = true
    private let authService = AuthService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if monthSections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(viewModel.noPaymentsTitle)
                        .font(.headline)
                    Text(viewModel.noPaymentsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(monthSections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                        Text(entry.dateText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.amountText)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text(section.totalText)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
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
