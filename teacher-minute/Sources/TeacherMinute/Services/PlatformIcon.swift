//
//  PlatformIcon.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 09/05/2026.
//

import SwiftUI
import SkipFuse

/// Cross-platform icon: uses SF Symbols on iOS, emoji text on Android.
/// 

struct PlatformIcon: View {

    let systemName: String
    var size: CGFloat = 20
    var weight: Font.Weight = .regular
    var color: Color = .primary

    var body: some View {
#if os(Android)
        Text(Self.emoji(for: systemName))
            .font(.system(size: size * 0.9))
            .frame(width: size, height: size)
#else
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
#endif
    }

    static func emoji(for systemName: String) -> String {
        switch systemName {
        case "moon.fill":                           return "🌙"
        case "antenna.radiowaves.left.and.right":   return "📡"
        case "checkmark.seal":                      return "☑️"
        case "checkmark.seal.fill":                 return "✅"
        case "checkmark.circle.fill":               return "✓"
        case "questionmark.circle":                 return "?"
        case "photo.fill":                          return "▧"
        case "mic.fill":                            return "🎤"
        case "video.fill":                          return "📷"
        case "circle.fill":                         return "🟢"
        case "bell.fill":                           return "🔔"
        case "lock.fill":                           return "🔒"
        case "rectangle.portrait.and.arrow.right":  return "↪"
        case "trash.fill":                          return "🗑"
        case "banknote.fill":                       return "💵"
        case "creditcard.fill":                     return "💳"
        case "shield.lefthalf.filled":              return "🛡"
        case "doc.text.fill":                       return "📄"
        case "clock.fill":                          return "🕒"
        case "dollarsign.circle.fill":              return "$"
        case "person.fill.checkmark":               return "✓"
        case "bubble.left.and.bubble.right.fill":   return "💬"
        case "house.fill":                          return "⌂"
        case "person.fill":                         return "👤"
        case "gearshape.fill":                      return "⚙"
        case "play.fill":                           return "▶"
        case "pause.fill":                          return "Ⅱ"
        case "function":                            return "ƒ"
        case "magnifyingglass":                     return "⌕"
        case "arrow.up":                            return "↑"
		case "arrow.rigt":							return "→"
        case "person.crop.circle.fill":             return "👤"
        case "xmark":                               return "✕"
        case "wifi":                                return "📶"
        case "camera.fill":                         return "📸"
        case "chevron.right":                       return "›"
        case "star.fill":                           return "⭐"
		case "pencil":                            	return "✏️"
		case "atom":                                return "⚛️"
		case "x.squareroot":                       	return "√"
		case "phone":                               return "📱"
		case "chevron.down":                        return "↓"
        default:
			logger.error("!!! icon: \(systemName) is missing !!!")
			return "●"
        }
    }
}
