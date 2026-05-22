//
//  MathEquationEditorView.swift
//  teacher-minute
//
//  Chat-style math composer: a compact capsule that mirrors the regular
//  chat input, plus a math keyboard sitting above it. The only difference
//  from the regular input is the keyboard.
//

import SwiftUI

struct MathEquationEditorView: View {
    @State var model = MathEquationViewModel()
    let onSend: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var exportedLatex: String {
        model.exportLatex()
    }

    var canSend: Bool {
        !exportedLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var inputCapsuleHeight: CGFloat {
#if os(Android)
        52
#else
        42
#endif
    }

    var body: some View {
        VStack(spacing: 8) {
            MathKeyboardView(onAction: handleKeyboardAction)

            HStack(spacing: 10) {
                inputCapsule

                Button {
                    sendCurrent()
                } label: {
                    PlatformIcon(systemName: "paperplane.fill", size: 15, weight: .bold, color: theme.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: canSend ? [theme.appPink, theme.appPurple] : [theme.appBorder, theme.appBorder],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.top, 10)
        .environment(\.layoutDirection, .leftToRight)
    }

    var inputCapsule: some View {
        MathFormulaView(latex: previewLatex, displayMode: false)
            .frame(maxWidth: .infinity)
            .frame(height: inputCapsuleHeight)
            .padding(.horizontal, 6)
            .background(theme.appGrayBackground)
            .clipShape(Capsule())
    }

    var previewLatex: String {
        model.latexWithCursorMarker()
    }

    func sendCurrent() {
        let latex = exportedLatex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else { return }
        onSend(latex)
        model.clear()
    }

    func handleKeyboardAction(_ action: MathKeyboardAction) {
        switch action {
        case .insert(let token):
            model.insertToken(token)
        case .delete:
            model.deleteBackward()
        case .clear:
            model.clear()
        case .moveLeft:
            model.moveCursorLeft()
        case .moveRight:
            model.moveCursorRight()
        case .fraction:
            model.wrapPreviousAsNumerator()
        }
    }
}

#if os(iOS)
#Preview {
    MathEquationEditorView(onSend: { _ in })
}
#endif
