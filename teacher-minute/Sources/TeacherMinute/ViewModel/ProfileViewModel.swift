//
//  ProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation

@Observable
final class ProfileViewModel {
    var name = "Mr. Davis"
    var role = "Math Teacher"
    var isVerified = true
    var memberSince = "Member since Aug 2023"

    var microphoneEnabled = true
    var notificationsEnabled = false

    func editProfile() {
        // TODO: edit profile
    }

    func changePhoto() {
        // TODO: image picker
    }

    func editGradeLevels() {
        // TODO
    }

    func editSubjects() {
        // TODO
    }

    func addGradeLevel() {
        // TODO
    }

    func manageNotifications() {
        // TODO
    }

    func logout() {
        // TODO
    }
}
