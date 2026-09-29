//
//  AccountSecuritySettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct AccountSecuritySettingsView: View {
    let viewModel: any SettingsViewModeling
    @Environment(\.appRouter) var router
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        ZStack {
            if AppTheme.isBrand {
                BrandSubpage(
                    label: viewModel.settingsTitle,
                    title: viewModel.settingsPageTitle(SettingsDestination.accountSecurity.title),
                    backLabel: viewModel.backLabel
                ) {
                    BrandPageHero(title: SettingsDestination.accountSecurity.title)
                    BrandSettingsRows(rows: viewModel.accountSecuritySection.rows) { row in
                        viewModel.select(row)
                    }
                }
            } else {
                List {
                    SettingsSectionView(section: viewModel.accountSecuritySection) { row in
                        viewModel.select(row)
                    }
                }
            }

            if viewModel.isLoading {
                theme.scrim.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.primaryText)
            }
        }
        // Log Out and Delete Account are the only rows that raise a
        // confirmation, and they are raised from here — so the dialogs are
        // presented here rather than on `SettingsView`.
        //
        // `appDialog` draws as an overlay, and an overlay lives inside the
        // bounds of the view it modifies. Attached to Settings' NavigationStack
        // it is therefore covered by whatever that stack pushes, so a
        // confirmation raised from this screen rendered *behind* it: the row
        // looked dead, and the dialog only became visible after tapping back.
        .appDialog(
            viewModel.activeConfirmation?.title ?? viewModel.settingsTitle,
            isPresented: isShowingConfirmation,
            message: viewModel.activeConfirmation?.message ?? "",
            actions: confirmationDialogActions
        )
        // Same reasoning for the error alert: a failed log out reports through
        // `present(title:message:)`, which would otherwise be invisible here.
        .appDialog(
            viewModel.alertTitle,
            isPresented: isShowingAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
        // And for the password Delete Account may ask for, in Instant
        // Teacher's dialog. Pro Teacher asks in `SettingsView`'s system alert,
        // which a pushed screen cannot cover.
        .appDialog(
            viewModel.deleteAccountTitle,
            isPresented: isShowingBrandReauthPrompt,
            message: viewModel.reauthPasswordMessage,
            secureField: AppDialogSecureField(
                placeholder: viewModel.passwordPlaceholder,
                text: reauthPassword
            ),
            actions: [
                AppDialogAction(viewModel.cancelLabel, kind: .cancel) {
                    viewModel.reauthPassword = ""
                },
                AppDialogAction(viewModel.deleteLabel, kind: .destructive) {
                    completeAccountDeletion()
                }
            ]
        )
    }

    /// Cancel first so it reads as the safe default, then the confirm action —
    /// destructive confirmations get the danger styling.
    var confirmationDialogActions: [AppDialogAction] {
        var actions = [
            AppDialogAction(viewModel.cancelLabel, kind: .cancel) {
                viewModel.activeConfirmation = nil
            }
        ]
        if let confirmation = viewModel.activeConfirmation {
            actions.append(
                AppDialogAction(
                    confirmation.confirmTitle,
                    kind: confirmation.isDestructive ? .destructive : .primary
                ) {
                    confirm(confirmation)
                }
            )
        }
        return actions
    }

    // The view model is held as an existential, so the bindings SwiftUI needs
    // are built by hand instead of through `$viewModel`.
    var isShowingConfirmation: Binding<Bool> {
        Binding {
            viewModel.activeConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.activeConfirmation = nil
            }
        }
    }

    var isShowingAlert: Binding<Bool> {
        Binding {
            viewModel.showAlert
        } set: { isPresented in
            viewModel.showAlert = isPresented
        }
    }

    var isShowingBrandReauthPrompt: Binding<Bool> {
        Binding {
            AppTheme.isBrand && viewModel.showReauthPasswordPrompt
        } set: { isPresented in
            viewModel.showReauthPasswordPrompt = isPresented
        }
    }

    var reauthPassword: Binding<String> {
        Binding {
            viewModel.reauthPassword
        } set: { password in
            viewModel.reauthPassword = password
        }
    }

    private func confirm(_ confirmation: SettingsConfirmation) {
        viewModel.activeConfirmation = nil

        Task {
            if await viewModel.confirm(confirmation) {
                router.signOut()
            }
        }
    }

    /// As `SettingsView`'s alert does it: the password is taken and cleared
    /// before the deletion runs.
    private func completeAccountDeletion() {
        let password = viewModel.reauthPassword
        viewModel.reauthPassword = ""
        Task {
            if await viewModel.completeAccountDeletion(withPassword: password) {
                router.signOut()
            }
        }
    }
}
