//
//  MultilineConversationTypePicker.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

 struct MultilineConversationTypePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ConversationType.allCases, id: \.rawValue) { type in
                Button {
                    selection = type.rawValue
                } label: {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: isSelected(type) ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 6)
                        .background {
                            if isSelected(type) {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
               // .accessibilityLabel(type.displayName)
                .accessibilitySelected(isSelected(type))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func isSelected(_ type: ConversationType) -> Bool {
        selection == type.rawValue
    }
}

extension View {
    /// Marks a control as selected for assistive technology.
    ///
    /// The trait is only ever *added*: never hand `accessibilityAddTraits` an
    /// empty `AccessibilityTraits` (`[]`, or `AccessibilityTraits()`). On
    /// Android, SkipFuseUI declares `init() { self = [] }`, and `[]` routes
    /// through `SetAlgebra`'s default array-literal init straight back into
    /// `init()` — the recursion overflows the stack and kills the process
    /// before the screen ever draws. iOS is unaffected, so the crash only
    /// shows up on device.
    @ViewBuilder
    func accessibilitySelected(_ isSelected: Bool) -> some View {
        if isSelected {
            self.accessibilityAddTraits(.isSelected)
        } else {
            self
        }
    }
}
