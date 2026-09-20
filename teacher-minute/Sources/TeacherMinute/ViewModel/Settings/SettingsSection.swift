//
//  SettingsSection.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

struct SettingsSection: Identifiable {
    let title: String
    let rows: [SettingsRow]
    
    var id: String { title }
}
