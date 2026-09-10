//
//  TeacherPayoutMethodSheet.swift
//  teacher-minute
//
// Edit form for where a teacher's monthly payout is sent. The type picker
// swaps in the fields that method actually needs — bank transfer, Bit, or
// PayPal. The backend re-validates everything (functions/src/payoutMethod.ts);
// this only gates Save on the required fields being filled in.

import SwiftUI

struct TeacherPayoutMethodSheet: View {
  let viewModel: TeacherEarningsViewModel
  @Binding var method: TeacherPayoutMethod
  /// Which destinations to offer. PayPal is gated behind a Remote Config flag,
  /// so this is not always every `PayoutMethodType`.
  let availableTypes: [PayoutMethodType]
  let banks: [PayoutBank]
  let isSaving: Bool
  let errorMessage: String?
  /// The number already on the teacher's profile, offered instead of retyping.
  let profilePhone: String
  let isConnectingPayPal: Bool
  let onUseProfilePhone: @MainActor () -> Void
  let onConnectPayPal: @MainActor () -> Void
  let onSave: @MainActor () -> Void
  let onCancel: @MainActor () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(viewModel.payoutMethodTitle)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 24)

        Text(viewModel.payoutMethodSheetSubtitle)
          .font(.system(size: 14))
          .foregroundStyle(theme.secondaryText)
          .frame(maxWidth: .infinity, alignment: .leading)

        typePicker

        fields

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        AuthPrimaryButton(
          title: viewModel.payoutSaveButtonLabel,
          systemImage: "checkmark",
          isEnabled: method.isComplete && !isSaving
        ) {
          onSave()
        }
        .padding(.top, 4)

        Button(viewModel.cancelLabel) {
          onCancel()
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
      }
      .padding(.horizontal, 20)
    }
    .background(theme.screenBackground)
  }

  // MARK: - Type picker

  var typePicker: some View {
    HStack(spacing: 0) {
      ForEach(availableTypes) { type in
        typeTab(type)
      }
    }
    .padding(3)
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  func typeTab(_ type: PayoutMethodType) -> some View {
    let isSelected = method.type == type
    // The selected tab sits on the saturated `accent` fill, so its label needs
    // a colour that stays light in both schemes. `onAccentText` is not it: its
    // light value is black, which leaves near-unreadable dark text on indigo.
    let selectedForeground = theme.ctaForeground
    return Button {
      method.type = type
    } label: {
      HStack(spacing: 6) {
        PlatformIcon(
          systemName: type.systemImage,
          size: 13,
          weight: .semibold,
          color: isSelected ? selectedForeground : theme.secondaryText
        )
        Text(type.displayName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? selectedForeground : theme.secondaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity)
      .background(isSelected ? theme.accent : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Per-type fields

  @ViewBuilder
  var fields: some View {
    switch method.type {
    case .bank:   bankFields
    case .bit:    bitFields
    case .paypal: payPalFields
    }
  }

  var bankFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      bankPicker
      AuthInputField(
        title: viewModel.branchNumberFieldTitle,
        placeholder: viewModel.branchNumberPlaceholder,
        systemImage: "number",
        text: $method.branchNumber,
        keyboardType: .numberPad
      )
      AuthInputField(
        title: viewModel.accountNumberFieldTitle,
        placeholder: viewModel.accountNumberPlaceholder,
        systemImage: "creditcard",
        text: $method.accountNumber,
        keyboardType: .numberPad
      )
      AuthInputField(
        title: viewModel.accountHolderFieldTitle,
        placeholder: viewModel.accountHolderPlaceholder,
        systemImage: "person",
        text: $method.accountHolderName,
        textContentType: .name,
        autocapitalization: .words
      )
    }
  }

  /// Picking the bank from the list is what makes this field checkable at all —
  /// the backend resolves the name from the code and rejects anything else.
  var bankPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(viewModel.bankFieldTitle)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(theme.primaryText)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(banks) { bank in
            let isSelected = method.bankCode == bank.code
            Button {
              method.bankCode = bank.code
              method.bankName = bank.displayName
            } label: {
              Text(bank.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? theme.primaryText : theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? theme.accent : theme.cardBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 1)
      }
    }
  }

  /// Quiet until something has been typed, so the field does not open in red.
  var showsPhoneError: Bool {
    let phone = method.phone.trimmingCharacters(in: .whitespacesAndNewlines)
    return !phone.isEmpty && !phone.isValidPhoneNumber
  }

  var showsPayPalEmailError: Bool {
    let email = method.email.trimmingCharacters(in: .whitespacesAndNewlines)
    return !email.isEmpty && !email.isEmail
  }

  var bitFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      AuthInputField(
        title: viewModel.bitPhoneFieldTitle,
        placeholder: viewModel.bitPhonePlaceholder,
        systemImage: "phone",
        text: $method.phone,
        keyboardType: .phonePad,
        textContentType: .telephoneNumber,
        isValid: !showsPhoneError,
        errorMessage: viewModel.phoneErrorMessage
      )

      if !profilePhone.isEmpty, method.phone.trimmingCharacters(in: .whitespacesAndNewlines) != profilePhone {
        Button {
          onUseProfilePhone()
        } label: {
          HStack(spacing: 8) {
            PlatformIcon(systemName: "arrow.down.doc", size: 14, weight: .semibold, color: theme.info)
            Text(viewModel.useProfileNumberText(profilePhone))
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.info)
            Spacer()
          }
          .padding(12)
          .background(theme.info.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
      }

      Text(viewModel.bitPhoneHint)
        .font(.system(size: 13))
        .foregroundStyle(theme.secondaryText)
    }
  }

  /// PayPal offers no API to check whether an address has an account, so the
  /// address is simply typed and saved. Signing in to PayPal (below) still
  /// proves ownership and marks the account confirmed, but it is optional —
  /// a payout to an address with no PayPal account is rejected by PayPal at
  /// transfer time, which is the backstop.
  var payPalFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      AuthInputField(
        title: viewModel.payPalEmailFieldTitle,
        placeholder: viewModel.emailPlaceholder,
        systemImage: "envelope",
        text: $method.email,
        keyboardType: .emailAddress,
        textContentType: .emailAddress,
        isValid: !showsPayPalEmailError,
        errorMessage: viewModel.payPalEmailErrorMessage
      )

//      if method.isPayPalVerified, !method.email.isEmpty {
//        HStack(spacing: 12) {
//          FlatIconTile(
//            systemName: "checkmark.seal.fill",
//            size: 40,
//            tint: theme.positive,
//            background: theme.screenBackground
//          )
//          VStack(alignment: .leading, spacing: 3) {
//            Text(LocalizationSupport.localized("PayPal account confirmed"))
//              .font(.system(size: 14, weight: .bold))
//              .foregroundStyle(theme.primaryText)
//            Text(method.email)
//              .font(.system(size: 13))
//              .foregroundStyle(theme.secondaryText)
//              .lineLimit(1)
//          }
//          Spacer()
//        }
//      }

      // A secondary link, not a second primary button: it looked identical to
      // Save, and teachers were tapping it by mistake to submit a typed
      // address — landing on an unrelated PayPal-account-linking flow instead.
//      Button {
//        onConnectPayPal()
//      } label: {
//        HStack(spacing: 8) {
//          if isConnectingPayPal {
//            ProgressView()
//          } else {
//            PlatformIcon(systemName: "link", size: 14, weight: .semibold, color: theme.info)
//          }
//          Text(
//            isConnectingPayPal
//              ? LocalizationSupport.localized("Connecting...")
//              : (method.isPayPalVerified
//                 ? LocalizationSupport.localized("Connect a different account")
//                 : LocalizationSupport.localized("Or sign in to PayPal to confirm it's you"))
//          )
//          .font(.system(size: 13, weight: .semibold))
//          .foregroundStyle(theme.info)
//          Spacer()
//        }
//      }
//      .buttonStyle(.plain)
//      .disabled(isConnectingPayPal)
//
//      Text(LocalizationSupport.localized("We never see your PayPal password."))
//        .font(.system(size: 13))
//        .foregroundStyle(theme.secondaryText)
    }
  }
}
