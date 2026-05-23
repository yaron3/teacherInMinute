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
  @Environment(\.layoutDirection) var layoutDirection
  
  private static let bundledIcons: Set<String> = [
	"bubble.left.and.bubble.right.fill",
	"g.circle.fill",
	"teaching_tab_icon"
  ]
  
  private var resolvedName: String {
	guard layoutDirection == .rightToLeft else { return systemName }
	if systemName == "chevron.right" { return "chevron.left" }
		if systemName == "chevron.left"  { return "chevron.right" }
	if systemName == "arrow.right"   { return "arrow.left" }
		if systemName == "arrow.left"    { return "arrow.right" }
	return systemName
  }
  
  var body: some View {
	if Self.bundledIcons.contains(resolvedName) {
	  Image(resolvedName, bundle: .module)
		.resizable()
		.frame(width: size, height: size)
	} else {
#if os(Android)
	  Text(Self.emoji(for: resolvedName))
		.font(.system(size: size))
		.foregroundStyle(color)
#else
	  Image(systemName: resolvedName)
		.font(.system(size: size, weight: weight))
		.foregroundStyle(color)
#endif
	}
	
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
	  case "speaker.wave.2.fill":                 return "🔊"
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
	  case "clock":								return "⏰"
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
	  case "arrow.right":							return "➡"
	  case "arrow.left":							return "←"
	  case "person.crop.circle.fill":             return "👤"
	  case "xmark":                               return "✕"
	  case "wifi":                                return "🛜"
	  case "camera.fill":                         return "📸"
	  case "star.fill":                           return "⭐"
	  case "pencil":                             return "✏️"
	  case "atom":                               return "⚛️"
	  case "x.squareroot":                       return "√"
	  case "phone":                              return "📞"
	  case "chevron.down":                       return "🔽"
	  case "chevron.left":						return "<"
	  case "chevron.right":                      return ">"
	  case "person":                             return "👤"
	  case "desktopcomputer":                    return "🖥️"
	  case "person.text.rectangle": 			return "🗂️"
	  case "icloud.and.arrow.up.fill":			return "☁️"
	  case "paperplane.fill":					return "📩"
	  case "bubble.left.fill":                  return "💬"
	  case "pin.fill":                          return "📍"
	  case "square":                           	return "□"
	  case "graduationcap.fill":				return "🎓"
	  case "envelope":                          return "📧"
	  case "eye.slash":							return "👁"
	  case "g.circle.fill":						return "G"
	  case "building.columns.fill":				return "🏰"
	  case "lightbulb.fill":					return "💡"
	  case "checkmark":							return "✓"
	  case "envelope.fill":						return "📧"
	  case "envelope.open.fill":                  return "📬"
	  case "phone.fill":							return "📞"
	  case "globe":                               return "🌍"
	  case "p.circle.fill":                       return "P"
		
	  case "doc.plaintext.fill":					return "txt"
	  case "hand.raised.fill":					return "✋"
	  case "clock.badge.checkmark.fill":			return "⏰"
		
		
	  default:
		logger.error("!!! icon: \(systemName) is missing !!!")
		return "●"
	}
  }
}
