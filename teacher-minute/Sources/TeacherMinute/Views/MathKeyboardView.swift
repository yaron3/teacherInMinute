//
//  MathKeyboardView.swift
//  teacher-minute
//
//  Custom math keyboard. Each button emits either a LaTeX token to insert
//  or a control action (delete / clear).
//

import SwiftUI

enum MathKeyboardAction {
    case insert(String)
    case delete
    case clear
    case moveLeft
    case moveRight
    // Take the atom just typed before the cursor as the numerator, then drop
    // the cursor into the empty denominator slot. Lets the user type
    // `3` → tap a⁄b → `2` to build a real stacked 3/2 fraction.
    case fraction
}

struct MathKey: Identifiable {
    let label: String
    let action: MathKeyboardAction
    let style: KeyStyle

    // Stable id so Skip / Compose doesn't rebuild the rows on every render.
    // Labels are unique across the entire keyboard.
    var id: String { label }

    enum KeyStyle {
        case standard
        case operatorKey
        case command
        case destructive
    }
}

struct MathKeyboardView: View {
    let onAction: (MathKeyboardAction) -> Void
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var rows: [[MathKey]] {
        [
            [
                MathKey(label: "7", action: .insert("7"), style: .standard),
                MathKey(label: "8", action: .insert("8"), style: .standard),
                MathKey(label: "9", action: .insert("9"), style: .standard),
                MathKey(label: "÷", action: .insert("\\div "), style: .operatorKey),
                MathKey(label: "×", action: .insert("\\times "), style: .operatorKey),
            ],
            [
                MathKey(label: "4", action: .insert("4"), style: .standard),
                MathKey(label: "5", action: .insert("5"), style: .standard),
                MathKey(label: "6", action: .insert("6"), style: .standard),
                MathKey(label: "+", action: .insert("+"), style: .operatorKey),
                MathKey(label: "−", action: .insert("-"), style: .operatorKey),
            ],
            [
                MathKey(label: "1", action: .insert("1"), style: .standard),
                MathKey(label: "2", action: .insert("2"), style: .standard),
                MathKey(label: "3", action: .insert("3"), style: .standard),
                MathKey(label: "(", action: .insert("("), style: .operatorKey),
                MathKey(label: ")", action: .insert(")"), style: .operatorKey),
            ],
            [
                MathKey(label: "0", action: .insert("0"), style: .standard),
                MathKey(label: ".", action: .insert("."), style: .standard),
                MathKey(label: "x", action: .insert("x"), style: .standard),
                MathKey(label: "y", action: .insert("y"), style: .standard),
                MathKey(label: "=", action: .insert("="), style: .operatorKey),
            ],
            [
                MathKey(label: "x²", action: .insert("^{2}"), style: .command),
                MathKey(label: "xʸ", action: .insert("^{}"), style: .command),
                MathKey(label: "a⁄b", action: .fraction, style: .command),
                MathKey(label: "√", action: .insert("\\sqrt{}"), style: .command),
                MathKey(label: "∫", action: .insert("\\int "), style: .command),
            ],
            [
                MathKey(label: "π", action: .insert("\\pi"), style: .command),
                MathKey(label: "◀", action: .moveLeft, style: .operatorKey),
                MathKey(label: "▶", action: .moveRight, style: .operatorKey),
                MathKey(label: "Clear", action: .clear, style: .destructive),
                MathKey(label: "⌫", action: .delete, style: .destructive),
            ],
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex]) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .padding(8)
        .background(theme.appGrayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func keyButton(_ key: MathKey) -> some View {
        Button {
            onAction(key.action)
        } label: {
            Text(key.label)
                .font(font(for: key.style))
                .foregroundStyle(foreground(for: key.style))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(background(for: key.style))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func font(for style: MathKey.KeyStyle) -> Font {
        switch style {
        case .standard:    return .system(size: 18, weight: .semibold)
        case .operatorKey: return .system(size: 18, weight: .bold)
        case .command:     return .system(size: 15, weight: .semibold)
        case .destructive: return .system(size: 14, weight: .bold)
        }
    }

    func background(for style: MathKey.KeyStyle) -> Color {
        switch style {
        case .standard:    return theme.appCardBackground
        case .operatorKey: return theme.appPurpleSoft
        case .command:     return theme.appPinkSoft
        case .destructive: return theme.yellow.opacity(0.22)
        }
    }

    func foreground(for style: MathKey.KeyStyle) -> Color {
        switch style {
        case .standard:    return theme.appPrimaryText
        case .operatorKey: return theme.appPurple
        case .command:     return theme.appPink
        case .destructive: return theme.appOrange
        }
    }
}
