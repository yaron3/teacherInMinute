//
//  ContactSupportPreviewSheet.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ContactSupportPreviewSheet: View {
    let viewModel: any SettingsViewModeling
    let request: ContactSupportRequest
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        if AppTheme.isBrand {
            brandSheet
        } else {
            standardSheet
        }
    }

    /// Instant Teacher's look: what will be sent, in a brand card, then Send.
    var brandSheet: some View {
        BrandSheet(title: viewModel.previewTitle, closeLabel: viewModel.cancelLabel) {
            guard !isSubmitting else { return }
            onCancel()
            dismiss()
        } content: {
            Text(viewModel.contactSupportPreviewSectionTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.brandSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(request.previewRows, id: \.0) { title, value in
                    if title != request.previewRows.first?.0 {
                        BrandRule()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.brandSecondaryText)
                        Text(value)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.onDarkFill)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .brandCard()

            BrandPrimaryButton(title: viewModel.sendLabel, isLoading: isSubmitting) {
                onSubmit()
            }
        }
    }

    var standardSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(request.previewRows, id: \.0) { title, value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(viewModel.contactSupportPreviewSectionTitle)
                }
            }
            .navigationTitle(viewModel.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.cancelLabel) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(viewModel.sendLabel)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}
