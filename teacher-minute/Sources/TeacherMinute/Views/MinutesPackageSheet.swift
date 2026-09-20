//
//  MinutesPackageSheet.swift
//  teacher-minute
//
//  Which bundle of minutes to buy, for a student who ran out mid-lesson.
//  Shown only when there is more than one to choose from — a single package is
//  not a decision, so that case goes straight to the payment methods.
//

import SwiftUI

struct MinutesPackageSheet: View {
  let viewModel: any StudentHomeViewModeling
  let options: [PricingOption]
  let theme: AppTheme
  let onSelect: (PricingOption) -> Void

  @Environment(\.dismiss) var dismiss

  var body: some View {
    VStack(spacing: 16) {
      Text(viewModel.choosePackageTitle)
        .font(.headline)
        .foregroundStyle(theme.primaryText)
        .padding(.top, 20)

      VStack(spacing: 12) {
        ForEach(options) { option in
          row(for: option)
        }
      }
      .padding(.horizontal, 20)

      Button(viewModel.cancelLabel) {
        dismiss()
      }
      .foregroundStyle(theme.secondaryText)
      .padding(.top, 4)

      Spacer()
    }
  }

  /// Same geometry as the payment-method rows, so the two steps of one
  /// purchase look like one flow.
  private func row(for option: PricingOption) -> some View {
    Button {
      onSelect(option)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(option.name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.primaryText)

          Text(option.minutesText ?? viewModel.localizedDescription(for: option))
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryText)
        }

        Spacer(minLength: 8)

        Text(option.priceText)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.primaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(theme.cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            option.isHighlighted ? theme.accent : theme.controlBorder,
            lineWidth: option.isHighlighted ? 2 : 1
          )
      )
      .cornerRadius(12)
    }
    .buttonStyle(.plain)
  }
}
