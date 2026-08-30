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
    // Skip's @Observable bridge doesn't recompose when class properties
    // mutate on Android. Bumping this counter from every mutation forces
    // SwiftUI to re-evaluate body and pick up the new model state.
    @State var modelTick: Int = 0
    let onSend: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var inputCapsuleHeight: CGFloat {
#if os(Android)
        52
#else
        42
#endif
    }

    var body: some View {
        // Reading modelTick is what actually subscribes this body to
        // recomposition — Skip's @Observable bridge on Android does not
        // recompose on class property mutations, so we drive it with an Int.
        _ = modelTick
        let latex = model.currentLatex
        let cursor = model.cursorIndex
        let preview = model.latexWithCursorMarker()
        let exported = model.exportLatex()
        let canSend = !exported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        logger.info("[MathEditor] body eval tick=\(modelTick) latex='\(latex)' cursor=\(cursor) preview='\(preview)'")

        return VStack(spacing: 8) {

            HStack(spacing: 10) {
                MathFormulaView(latex: preview, displayMode: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: inputCapsuleHeight)
                    .padding(.horizontal, 6)
                    .background(theme.fieldBackground)
                    .clipShape(Capsule())

                Button {
                    sendCurrent(exported: exported)
                    modelTick &+= 1
                } label: {
                    PlatformIcon(systemName: "paperplane.fill", size: 15, weight: .bold, color: theme.onDarkFill)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: canSend ? [theme.accent, theme.accentStrong] : [theme.controlDisabled, theme.controlDisabled],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
		  MathKeyboardView(onAction: handleKeyboardAction)
        }
        .padding(.top, 10)
        .environment(\.layoutDirection, .leftToRight)
    }

    func sendCurrent(exported: String) {
        let trimmed = exported.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Clear before handing off. `onSend` appends to the parent's message
        // list, which rebuilds this view — in the chat session it sits inside a
        // `safeAreaInset`, so the rebuild can hand us a fresh `model` and a
        // clear afterwards lands on the discarded one. The equation then stays
        // in the field, which reads as "the send button did nothing".
        model.clear()
        onSend(trimmed)
    }

    func handleKeyboardAction(_ action: MathKeyboardAction) {
        logger.info("[MathEditor] handleKeyboardAction received action, before latex='\(model.currentLatex)' cursor=\(model.cursorIndex)")
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
        modelTick &+= 1
        logger.info("[MathEditor] after action tick=\(modelTick) latex='\(model.currentLatex)' cursor=\(model.cursorIndex)")
    }
}

#if os(iOS)
#Preview {
    MathEquationEditorView(onSend: { _ in })
}
#endif
