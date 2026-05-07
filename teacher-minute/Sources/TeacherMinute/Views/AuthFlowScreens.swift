//
//  AuthFlowScreens.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//
import SwiftUI

#if os(iOS)
struct AuthFlowScreens_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ResetPasswordView()
        }

        NavigationStack {
            ChooseRoleView()
        }

        NavigationStack {
            TeacherIdentityVerificationView()
        }

        NavigationStack {
            TeacherSubjectsView()
        }

        NavigationStack {
            CompleteProfileView()
        }

        NavigationStack {
            VerifyPhoneView()
        }

        NavigationStack {
            PermissionsSetupView()
        }
    }
}
#endif
