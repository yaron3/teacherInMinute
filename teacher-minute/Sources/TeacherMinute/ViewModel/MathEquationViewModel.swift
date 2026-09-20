//
//  MathEquationViewModel.swift
//  teacher-minute
//
//  Holds the LaTeX state for the math equation editor.
//

import Foundation
import Observation
import SkipFuse

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
        var pos = clampedCursor()
        var token = token

        // An exponent key pressed right after an exponent would give
        // `^{2}^{2}`, which LaTeX rejects as a double superscript. The slot the
        // student means is the one already there, so step inside it and write
        // the new exponent into it: `x²` twice reads `x^{22}`, and `xʸ` after
        // `x²` simply reopens the exponent for typing.
        if let marker = token.first, marker == "^" || marker == "_", token.count >= 3 {
            let chars = Array(currentLatex)
            // The caret sits just after an exponent: `x^{2}|`.
            if pos > 0, pos - 1 < chars.count, chars[pos - 1] == "}",
               let open = matchingOpenBrace(in: chars, closeAt: pos - 1),
               open > 0, chars[open - 1] == marker {
                pos -= 1
                cursorIndex = pos
                token = String(token.dropFirst(2).dropLast())
            } else if pos + 1 < chars.count, chars[pos] == marker, chars[pos + 1] == "{" {
                // Or just before one: `|^{2}`, reached by walking the caret
                // back over it.
                pos += 2
                cursorIndex = pos
                token = String(token.dropFirst(2).dropLast())
            }
        }

        guard !token.isEmpty else { return }
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
        let chars = Array(currentLatex)

        // The cursor sits at the head of a slot — `\frac{3}{|}`, `x^{|2}`,
        // `\sqrt{|}`. Backspace undoes the key that opened the construct and
        // keeps what its slots already hold, so `\frac{3}{|}` becomes `3|`.
        // Removing only the brace would leave `\frac{3}` behind, which no
        // renderer can draw.
        if chars[pos - 1] == "{", let close = matchingCloseBrace(in: chars, openAt: pos - 1) {
            deleteConstruct(slotOpeningAt: pos - 1, closingAt: close, in: chars)
            return
        }

        // The cursor sits after a finished group — `x^{2}|`, `\sqrt{9}|`,
        // `\frac{1}{2}|`. The whole term goes in one press; deleting just the
        // closing brace would split the group and produce LaTeX that cannot be
        // parsed at all.
        if chars[pos - 1] == "}" {
            let start = groupedTermStart(in: chars, closeAt: pos - 1)
            if start < pos - 1 {
                removeRange(from: start, length: pos - start)
                cursorIndex = start
                return
            }
        }

        // Drop a trailing LaTeX command (`\pi`, `\times `, ...) as one unit,
        // including the space that separates it from what follows.
        var scanEnd = pos
        if chars[pos - 1] == " " { scanEnd = pos - 1 }
        if scanEnd > 0, let bs = commandStart(in: chars, endingBefore: scanEnd) {
            removeRange(from: bs, length: pos - bs)
            cursorIndex = bs
            return
        }

        // Default: remove one character before the cursor.
        removeRange(from: pos - 1, length: 1)
        cursorIndex = pos - 1
        mergeAdjacentScripts()
    }

    /// Removes the construct that owns the slot spanning `open`...`closing`,
    /// splicing the contents of every one of its slots back in.
    func deleteConstruct(slotOpeningAt open: Int, closingAt closing: Int, in chars: [Character]) {
        var kept: [String] = [String(chars[(open + 1)..<closing])]

        // Slots written before this one (`\frac{3}{|}` keeps the 3).
        var groupStart = open
        while groupStart > 0, chars[groupStart - 1] == "}" {
            guard let prev = matchingOpenBrace(in: chars, closeAt: groupStart - 1) else { break }
            kept.insert(String(chars[(prev + 1)..<(groupStart - 1)]), at: 0)
            groupStart = prev
        }

        // Slots written after it (`\frac{|}{2}` keeps the 2).
        var constructEnd = closing + 1
        while constructEnd < chars.count, chars[constructEnd] == "{" {
            guard let close = matchingCloseBrace(in: chars, openAt: constructEnd) else { break }
            kept.append(String(chars[(constructEnd + 1)..<close]))
            constructEnd = close + 1
        }

        // The `\command` or the `^` / `_` that owns the slots.
        var constructStart = groupStart
        if let cmd = commandStart(in: chars, endingBefore: groupStart) {
            constructStart = cmd
        } else if groupStart > 0, chars[groupStart - 1] == "^" || chars[groupStart - 1] == "_" {
            constructStart = groupStart - 1
        }

        let replacement = kept.joined()
        removeRange(from: constructStart, length: constructEnd - constructStart)
        if !replacement.isEmpty {
            let idx = currentLatex.index(currentLatex.startIndex, offsetBy: constructStart)
            currentLatex.insert(contentsOf: replacement, at: idx)
        }
        cursorIndex = constructStart + replacement.count
    }

    func clear() {
        currentLatex = ""
        cursorIndex = 0
    }

    func moveCursorLeft() {
        cursorIndex = nearestInsertionPoint(from: max(0, clampedCursor() - 1), movingRight: false)
    }

    func moveCursorRight() {
        cursorIndex = nearestInsertionPoint(from: min(currentLatex.count, clampedCursor() + 1), movingRight: true)
    }

    /// Slides `index` off any position a keystroke cannot legally land on,
    /// carrying on the way the caret was already travelling. Stepping one
    /// character at a time would park it inside the word `sqrt` or between
    /// `\frac{1}` and `{2}`, and the next key pressed there writes `\sqrtx{}`
    /// — LaTeX with no such command. So ◀ crosses `\sqrt{` as one thing.
    func nearestInsertionPoint(from index: Int, movingRight: Bool) -> Int {
        let chars = Array(currentLatex)
        var i = min(max(0, index), chars.count)
        var steps = 0
        while steps <= chars.count, !isInsertionPoint(i, in: chars) {
            steps += 1
            i += movingRight ? 1 : -1
            if i <= 0 { return 0 }
            if i >= chars.count { return chars.count }
        }
        return i
    }

    /// Whether text typed at `i` would still be the LaTeX the student sees.
    func isInsertionPoint(_ i: Int, in chars: [Character]) -> Bool {
        guard i > 0, i < chars.count else { return true }

        // Inside a command name: `\pi` may be split at neither `\|pi` nor `\p|i`.
        if chars[i].isLetter {
            var j = i
            while j > 0, chars[j - 1].isLetter { j -= 1 }
            if j > 0, chars[j - 1] == "\\" { return false }
        }

        // On the space that terminates a command: `\div| 5` would give `\divx 5`.
        if chars[i] == " ", commandStart(in: chars, endingBefore: i) != nil { return false }

        // Between a construct and the argument braces it owns: `\sqrt|{9}`,
        // `x^|{2}`, `\frac{1}|{2}`.
        if chars[i] == "{" {
            if commandStart(in: chars, endingBefore: i) != nil { return false }
            if chars[i - 1] == "^" || chars[i - 1] == "_" || chars[i - 1] == "}" { return false }
        }

        return true
    }

    /// `3` → tap a⁄b → `2` should produce `\frac{3}{2}`. The atom just before
    /// the cursor becomes the numerator, the cursor lands in the empty
    /// denominator. When nothing wrappable precedes the cursor — the start of
    /// the field, or an operator like `+` — an empty `\frac{}{}` goes in with
    /// the cursor in the numerator instead.
    func wrapPreviousAsNumerator() {
        let pos = clampedCursor()
        let start = atomStart(endingBefore: pos)
        guard start < pos else {
            insertToken("\\frac{}{}")
            return
        }
        let numeratorRange = currentLatex.index(currentLatex.startIndex, offsetBy: start)
            ..< currentLatex.index(currentLatex.startIndex, offsetBy: pos)
        let numerator = String(currentLatex[numeratorRange])
        let replacement = "\\frac{\(numerator)}{}"
        currentLatex.replaceSubrange(numeratorRange, with: replacement)
        // `\frac{` = 6 chars + numerator + `}{` = 2 chars, then cursor sits
        // between `{` and `}` of the denominator.
        cursorIndex = start + 6 + numerator.count + 2
        mergeAdjacentScripts()
    }

    /// `x^{2}^{3}` is two exponents on one base, which LaTeX rejects outright.
    /// An edit can push two exponent groups together even when neither
    /// keystroke did — backspacing the `-` out of `x^{2}-^{3}` closes the gap —
    /// so wherever they end up touching they become the one group the student
    /// is looking at: `x^{23}`.
    func mergeAdjacentScripts() {
        var chars = Array(currentLatex)
        var i = 0
        while i < chars.count {
            if chars[i] == "}", i + 2 < chars.count,
               chars[i + 1] == "^" || chars[i + 1] == "_",
               chars[i + 2] == "{",
               let open = matchingOpenBrace(in: chars, closeAt: i),
               open > 0, chars[open - 1] == chars[i + 1] {
                // Dropping `}^{` welds the two groups; the second group's
                // closing brace now closes the merged one.
                chars.removeSubrange(i...(i + 2))
                if cursorIndex > i { cursorIndex = max(i, cursorIndex - 3) }
                continue
            }
            i += 1
        }
        currentLatex = String(chars)
        cursorIndex = min(cursorIndex, currentLatex.count)
    }

    /// Start offset of the atom immediately before `end` — the run a fraction
    /// bar should swallow whole. Returns `end` itself when there is nothing to
    /// wrap, which is how the caller learns to open an empty numerator.
    ///
    /// An atom is a term with its exponent (`x^{2}`, `\pi^{2}`) — the base
    /// comes along, because `x^{2}` over 3 is the fraction anyone typing that
    /// means, and taking only the `{2}` would tear the group in half.
    func atomStart(endingBefore end: Int) -> Int {
        guard end > 0 else { return end }
        let chars = Array(currentLatex)
        var start = operandStart(in: chars, endingBefore: end)
        guard start < end else { return end }
        while start > 0, chars[start] == "^" || chars[start] == "_" {
            let base = operandStart(in: chars, endingBefore: start)
            if base >= start { break }
            start = base
        }
        return start
    }

    /// One operand ending at `end`, without reaching past a `^` / `_` for its
    /// base. Returns `end` when the character before the cursor is an operator,
    /// a space or an unmatched brace — none of those is something to divide.
    func operandStart(in chars: [Character], endingBefore end: Int) -> Int {
        guard end > 0, end <= chars.count else { return end }
        let last = end - 1
        let lastChar = chars[last]

        // A finished brace group and everything that owns it: `\sqrt{9}`,
        // `\frac{1}{2}`, `^{2}`.
        if lastChar == "}" {
            return groupedTermStart(in: chars, closeAt: last)
        }

        if lastChar == ")" {
            var depth = 1
            var i = last - 1
            while i >= 0 {
                // The opening paren has to live in the same slot. Reaching a
                // brace first means `(` is outside it, and swallowing across
                // the boundary would tear the group open.
                if chars[i] == "{" || chars[i] == "}" { return end }
                if chars[i] == ")" { depth += 1 }
                else if chars[i] == "(" {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
            return end
        }

        if lastChar.isNumber || lastChar == "." {
            var i = last
            while i > 0, chars[i - 1].isNumber || chars[i - 1] == "." {
                i -= 1
            }
            return i
        }

        // The space that separates a command from what follows belongs to the
        // command: `\pi ` over 2 is `\frac{\pi }{2}`, not an empty numerator.
        if lastChar == " " {
            guard let cmd = commandStart(in: chars, endingBefore: last) else { return end }
            return isOperatorCommand(String(chars[cmd..<last])) ? end : cmd
        }

        if lastChar.isLetter {
            var i = last
            while i > 0, chars[i - 1].isLetter {
                i -= 1
            }
            // `\pi` is one symbol: the backslash is part of it, and leaving it
            // behind turns π over 2 into a line break followed by `pi/2`.
            if i > 0, chars[i - 1] == "\\" {
                return isOperatorCommand(String(chars[(i - 1)..<end])) ? end : i - 1
            }
            return i
        }

        return end
    }

    /// Commands that join two things rather than being a thing. A fraction bar
    /// started right after one wants an empty numerator: `5 × a⁄b` is `5 ×` a
    /// blank over a blank, never `5` times `×` over a blank.
    func isOperatorCommand(_ name: String) -> Bool {
        return name == "\\times" || name == "\\div" || name == "\\int"
            || name == "\\pm" || name == "\\cdot" || name == "\\sum"
    }

    /// Start of the term whose closing brace sits at `close`: the group, any
    /// sibling groups before it, and the `\command` or `^` / `_` that owns them.
    func groupedTermStart(in chars: [Character], closeAt close: Int) -> Int {
        guard let open = matchingOpenBrace(in: chars, closeAt: close) else { return close }
        var start = open
        while start > 0, chars[start - 1] == "}" {
            guard let prev = matchingOpenBrace(in: chars, closeAt: start - 1) else { break }
            start = prev
        }
        if let cmd = commandStart(in: chars, endingBefore: start) { return cmd }
        if start > 0, chars[start - 1] == "^" || chars[start - 1] == "_" { return start - 1 }
        return start
    }

    /// Offset of the backslash of the `\command` ending at `end`, or nil when
    /// the characters before `end` are not one.
    func commandStart(in chars: [Character], endingBefore end: Int) -> Int? {
        var i = end
        while i > 0, chars[i - 1].isLetter { i -= 1 }
        guard i < end, i > 0, chars[i - 1] == "\\" else { return nil }
        return i - 1
    }

    func matchingOpenBrace(in chars: [Character], closeAt close: Int) -> Int? {
        var depth = 1
        var i = close - 1
        while i >= 0 {
            if chars[i] == "}" { depth += 1 }
            else if chars[i] == "{" {
                depth -= 1
                if depth == 0 { return i }
            }
            i -= 1
        }
        return nil
    }

    func matchingCloseBrace(in chars: [Character], openAt open: Int) -> Int? {
        var depth = 1
        var i = open + 1
        while i < chars.count {
            if chars[i] == "{" { depth += 1 }
            else if chars[i] == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
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
