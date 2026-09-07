//
//  SettingsAction.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

enum SettingsAction: Equatable {
    case accountSecurity
    case appPreferences
    case changePassword
    case logOut
    case deleteAccount
    case teacherPayouts
    case studentPayments
    case notifications
    case privacyControls
    case language
    case about
    case contactUs
    case eula
    case privacyPolicy
    #if DEBUG
    case forceReloadRemoteConfig
    case testCrashlyticsCrash
    #endif
    
    var id: String {
        switch self {
        case .accountSecurity: "accountSecurity"
        case .appPreferences: "appPreferences"
        case .changePassword: "changePassword"
        case .logOut: "logOut"
        case .deleteAccount: "deleteAccount"
        case .teacherPayouts: "teacherPayouts"
        case .studentPayments: "studentPayments"
        case .notifications: "notifications"
        case .privacyControls: "privacyControls"
        case .language: "language"
        case .about: "about"
        case .contactUs: "contactUs"
        case .eula: "eula"
        case .privacyPolicy: "privacyPolicy"
        #if DEBUG
        case .forceReloadRemoteConfig: "forceReloadRemoteConfig"
        case .testCrashlyticsCrash: "testCrashlyticsCrash"
        #endif
        }
    }
}
