//
//  LaunchPresencePicker.swift
//  teacher-minute
//

import SwiftUI

/// Availability at launch, laid out like `MultilineConversationTypePicker`
/// rather than as a `Picker`: the three labels wrap on a narrow screen, and a
/// segmented picker clips them instead.
struct LaunchPresencePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TeacherLaunchPresence.allCases, id: \.rawValue) { presence in
                Button {
                    selection = presence.rawValue
                } label: {
                    Text(presence.title)
                        .font(.system(size: 15, weight: isSelected(presence) ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 6)
                        .background {
                            if isSelected(presence) {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilitySelected(isSelected(presence))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func isSelected(_ presence: TeacherLaunchPresence) -> Bool {
        selection == presence.rawValue
    }
}
