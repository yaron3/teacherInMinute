//
//  TeacherPayoutSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

/// Settings' entry point to the same payout editor Earnings uses — the
/// `TeacherPayoutMethodSheet` component itself, driven by the same
/// `TeacherEarningsViewModel`, so the two entry points can never drift into
/// showing different fields or writing to different places. The predecessor
/// of this view wrote a typed address straight to a `paypalEmail` field on
/// the profile, bypassing the domain check and the payout-method type system
/// entirely — a second, unvalidated path to the same real-world data.
///
/// Earnings presents this component as a sheet over the earnings history;
/// here, editing the payout method is the whole point of the screen, so it is
/// the pushed destination's entire body and "Cancel"/a successful save both
/// pop back to Settings instead of dismissing a sheet.
struct TeacherPayoutSettingsView: View {
    @State var payoutViewModel = TeacherEarningsViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TeacherPayoutMethodSheet(
            method: $payoutViewModel.payoutMethodDraft,
            availableTypes: payoutViewModel.availablePayoutMethodTypes,
            banks: payoutViewModel.banks,
            isSaving: payoutViewModel.isSavingPayoutMethod,
            errorMessage: payoutViewModel.payoutMethodErrorMessage,
            profilePhone: payoutViewModel.profilePhone,
            isConnectingPayPal: payoutViewModel.isConnectingPayPal,
            onUseProfilePhone: { payoutViewModel.useProfilePhone() },
            onConnectPayPal: { Task { await payoutViewModel.connectPayPalPayoutAccount() } },
            onSave: { Task { await payoutViewModel.savePayoutMethod() } },
            onCancel: { dismiss() }
        )
        .task {
            await payoutViewModel.loadForPayoutMethodEditing()
        }
        // Mirrors what a successful save/connect does in Earnings — there it
        // dismisses the sheet; here it pops back to Settings. Cancel already
        // pops directly above, so this only ever fires on that success path.
        .onChange(of: payoutViewModel.isEditingPayoutMethod) { _, isEditing in
            if !isEditing {
                dismiss()
            }
        }
    }
}
