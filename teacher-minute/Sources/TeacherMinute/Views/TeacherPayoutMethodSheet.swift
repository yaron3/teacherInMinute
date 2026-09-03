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
        Text(LocalizationSupport.localized("Payment Method"))
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 24)

        Text(LocalizationSupport.localized("Choose where we should send your monthly payout."))
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

        // PayPal saves itself when the login completes, so it has no Save
        // button — there is nothing to submit that PayPal has not confirmed.
        if method.type != .paypal {
          AuthPrimaryButton(
            title: isSaving
              ? LocalizationSupport.localized("Saving...")
              : LocalizationSupport.localized("Save"),
            systemImage: "checkmark",
            isEnabled: method.isComplete && !isSaving
          ) {
            onSave()
          }
          .padding(.top, 4)
        }

        Button(LocalizationSupport.localized("Cancel")) {
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
        title: LocalizationSupport.localized("Branch Number"),
        placeholder: LocalizationSupport.localized("e.g. 123"),
        systemImage: "number",
        text: $method.branchNumber,
        keyboardType: .numberPad
      )
      AuthInputField(
        title: LocalizationSupport.localized("Account Number"),
        placeholder: LocalizationSupport.localized("e.g. 45678901"),
        systemImage: "creditcard",
        text: $method.accountNumber,
        keyboardType: .numberPad
      )
      AuthInputField(
        title: LocalizationSupport.localized("Account Holder Name"),
        placeholder: LocalizationSupport.localized("Full name as it appears at the bank"),
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
      Text(LocalizationSupport.localized("Bank"))
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

  var bitFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      AuthInputField(
        title: LocalizationSupport.localized("Bit Phone Number"),
        placeholder: LocalizationSupport.localized("place holder phone number"),
        systemImage: "phone",
        text: $method.phone,
        keyboardType: .phonePad,
        textContentType: .telephoneNumber,
        isValid: !showsPhoneError,
        errorMessage: LocalizationSupport.localized("Enter a valid phone number.")
      )

      if !profilePhone.isEmpty, method.phone.trimmingCharacters(in: .whitespacesAndNewlines) != profilePhone {
        Button {
          onUseProfilePhone()
        } label: {
          HStack(spacing: 8) {
            PlatformIcon(systemName: "arrow.down.doc", size: 14, weight: .semibold, color: theme.info)
            Text(String(format: LocalizationSupport.localized("Use my profile number (%@)"), profilePhone))
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

      Text(LocalizationSupport.localized("Use the phone number registered with your Bit account."))
        .font(.system(size: 13))
        .foregroundStyle(theme.secondaryText)
    }
  }

  /// No email field: PayPal offers no way to check whether an address has an
  /// account, so the address is taken from a completed PayPal login instead of
  /// being typed — that is also what proves the teacher controls it.
  var payPalFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      if method.isPayPalVerified, !method.email.isEmpty {
        HStack(spacing: 12) {
          FlatIconTile(
            systemName: "checkmark.seal.fill",
            size: 40,
            tint: theme.positive,
            background: theme.screenBackground
          )
          VStack(alignment: .leading, spacing: 3) {
            Text(LocalizationSupport.localized("PayPal account confirmed"))
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(theme.primaryText)
            Text(method.email)
              .font(.system(size: 13))
              .foregroundStyle(theme.secondaryText)
              .lineLimit(1)
          }
          Spacer()
        }
      }

      AuthPrimaryButton(
        title: isConnectingPayPal
          ? LocalizationSupport.localized("Connecting...")
          : (method.isPayPalVerified
             ? LocalizationSupport.localized("Connect a different account")
             : LocalizationSupport.localized("Connect PayPal")),
        systemImage: "link",
        isEnabled: !isConnectingPayPal
      ) {
        onConnectPayPal()
      }

      Text(LocalizationSupport.localized("You will sign in to PayPal so we can confirm the account is yours. We never see your PayPal password."))
        .font(.system(size: 13))
        .foregroundStyle(theme.secondaryText)
    }
  }
}
