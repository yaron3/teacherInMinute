//
//  MathEquationViewModel.swift
//  teacher-minute
//
//  Holds the LaTeX state for the math equation editor.
//

import Foundation
import Observation

@Observable
final class MathEquationViewModel {
    // Pure LaTeX without any cursor marker.
    var currentLatex: String = ""
    // Character offset into currentLatex where the next insertion happens.
    var cursorIndex: Int = 0
    var mode: MathTemplate = .freeform
    var templateValues: [String: String] = [:]

    // MARK: - Editing

    func insertToken(_ token: String) {
        let pos = clampedCursor()
        let startIdx = currentLatex.index(currentLatex.startIndex, offsetBy: pos)
        currentLatex.insert(contentsOf: token, at: startIdx)

        // When a token contains the placeholder `{}` (e.g. `^{}`, `\frac{}{}`,
        // `\sqrt{}`), drop the cursor between the first `{` and `}` so the
        // next keystroke fills the slot.
        if let range = token.range(of: "{}") {
            let offsetIntoToken = token.distance(from: token.startIndex, to: range.lowerBound) + 1
            cursorIndex = pos + offsetIntoToken
        } else {
            cursorIndex = pos + token.count
        }
    }

    func deleteBackward() {
        let pos = clampedCursor()
        guard pos > 0 else { return }

        // If the cursor sits between empty braces `{|}`, remove the whole `{}`.
        if pos >= 1, pos < currentLatex.count,
           charAt(pos - 1) == "{", charAt(pos) == "}" {
            removeRange(from: pos - 1, length: 2)
            cursorIndex = pos - 1
            return
        }

        // If the character before the cursor is `{` and we are right at the
        // start of an empty-braces token like `^{}`, scrub the whole token.
        let before = currentLatex.prefix(pos)
        if before.hasSuffix("^{") && pos < currentLatex.count && charAt(pos) == "}" {
            removeRange(from: pos - 2, length: 3)
            cursorIndex = pos - 2
            return
        }
        if before.hasSuffix("_{") && pos < currentLatex.count && charAt(pos) == "}" {
            removeRange(from: pos - 2, length: 3)
            cursorIndex = pos - 2
            return
        }

        // Drop a trailing LaTeX command (`\frac`, `\sqrt`, ...) as one unit.
        if let bs = before.lastIndex(of: "\\") {
            let tail = before[bs...]
            let isCommand = tail.dropFirst().allSatisfy { $0.isLetter }
            if isCommand && tail.count > 1 {
                let bsOffset = before.distance(from: before.startIndex, to: bs)
                removeRange(from: bsOffset, length: pos - bsOffset)
                cursorIndex = bsOffset
                return
            }
        }

        // Default: remove one character before the cursor.
        removeRange(from: pos - 1, length: 1)
        cursorIndex = pos - 1
    }

    func clear() {
        currentLatex = ""
        cursorIndex = 0
    }

    func moveCursorLeft() {
        cursorIndex = max(0, clampedCursor() - 1)
    }

    func moveCursorRight() {
        cursorIndex = min(currentLatex.count, clampedCursor() + 1)
    }

    /// `3` → tap a⁄b → `2` should produce `\frac{3}{2}`. The atom just before
    /// the cursor becomes the numerator, the cursor lands in the empty
    /// denominator. If nothing precedes the cursor, falls back to inserting
    /// an empty `\frac{}{}` with the cursor in the numerator slot.
    func wrapPreviousAsNumerator() {
        let pos = clampedCursor()
        guard pos > 0 else {
            insertToken("\\frac{}{}")
            return
        }
        let start = atomStart(endingBefore: pos)
        let numeratorRange = currentLatex.index(currentLatex.startIndex, offsetBy: start)
            ..< currentLatex.index(currentLatex.startIndex, offsetBy: pos)
        let numerator = String(currentLatex[numeratorRange])
        let replacement = "\\frac{\(numerator)}{}"
        currentLatex.replaceSubrange(numeratorRange, with: replacement)
        // `\frac{` = 6 chars + numerator + `}{` = 2 chars, then cursor sits
        // between `{` and `}` of the denominator.
        cursorIndex = start + 6 + numerator.count + 2
    }

    // Walks backwards from `end` and returns the start index of the atom
    // immediately preceding the cursor. An atom is:
    //   - a balanced `(...)` group,
    //   - a run of digits / decimal dots,
    //   - a run of letters,
    //   - or just the single character before the cursor.
    func atomStart(endingBefore end: Int) -> Int {
        guard end > 0 else { return 0 }
        let chars = Array(currentLatex)
        let lastIdx = end - 1
        let lastChar = chars[lastIdx]

        if lastChar == ")" {
            var depth = 1
            var i = lastIdx - 1
            while i >= 0 {
                if chars[i] == ")" { depth += 1 }
                else if chars[i] == "(" {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
            return 0
        }

        if lastChar.isNumber || lastChar == "." {
            var i = lastIdx
            while i > 0, chars[i - 1].isNumber || chars[i - 1] == "." {
                i -= 1
            }
            return i
        }

        if lastChar.isLetter {
            var i = lastIdx
            while i > 0, chars[i - 1].isLetter {
                i -= 1
            }
            return i
        }

        return lastIdx
    }

    // MARK: - Export

    func exportLatex() -> String {
        if mode == .freeform {
            return currentLatex
        }
        return mode.render(values: templateValues)
    }

    /// Returns the LaTeX with a visible cursor marker injected at `cursorIndex`.
    /// Use only for rendering — never for sending.
    func latexWithCursorMarker() -> String {
        let marker = "\\textcolor{#EC4899}{\\,\\rule[-0.05em]{0.06em}{0.9em}\\,}"
        let pos = clampedCursor()
        let idx = currentLatex.index(currentLatex.startIndex, offsetBy: pos)
        var copy = currentLatex
        copy.insert(contentsOf: marker, at: idx)
        return copy
    }

    /// Returns the raw LaTeX with a `|` at the cursor position. Used by the
    /// debug strip so the user can see exactly where new input will go.
    func rawWithCursor() -> String {
        let pos = clampedCursor()
        let idx = currentLatex.index(currentLatex.startIndex, offsetBy: pos)
        var copy = currentLatex
        copy.insert("|", at: idx)
        return copy
    }

    // MARK: - Templates

    func setTemplateValue(_ value: String, for key: String) {
        templateValues[key] = value
    }

    func templateValue(for key: String) -> String {
        templateValues[key] ?? ""
    }

    func switchMode(_ newMode: MathTemplate) {
        mode = newMode
        if newMode == .freeform {
            return
        }
        templateValues = [:]
    }

    // MARK: - Helpers

    func clampedCursor() -> Int {
        min(max(0, cursorIndex), currentLatex.count)
    }

    func charAt(_ offset: Int) -> Character {
        currentLatex[currentLatex.index(currentLatex.startIndex, offsetBy: offset)]
    }

    func removeRange(from offset: Int, length: Int) {
        let start = currentLatex.index(currentLatex.startIndex, offsetBy: offset)
        let end = currentLatex.index(start, offsetBy: length)
        currentLatex.removeSubrange(start..<end)
    }
}
