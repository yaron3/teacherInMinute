//
//  MathFormulaRenderer.swift
//  teacher-minute
//
//  Cross-platform abstraction for rendering LaTeX. On iOS we host a
//  WKWebView with KaTeX. On other platforms we fall back to the raw string.
//

import SwiftUI

struct MathFormulaView: View {
    let latex: String
    var displayMode: Bool = true
    /// Space the renderer keeps to the left and right of the formula. Zero lets
    /// a caller line the formula up with text of its own that sits above or
    /// below it, which a list row needs and a chat bubble does not.
    var horizontalInset: CGFloat = 8

    var body: some View {
        MathFormulaRenderer(latex: latex, displayMode: displayMode, horizontalInset: horizontalInset)
            .environment(\.layoutDirection, .leftToRight)
    }
}

#if canImport(WebKit) && canImport(UIKit)
import WebKit

struct MathFormulaRenderer: View {
    let latex: String
    let displayMode: Bool
    var horizontalInset: CGFloat = 8
    @Environment(\.colorScheme) var colorScheme

    private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    var body: some View {
        if Self.isPreview {
            plainTextFallback
        } else {
            KaTeXWebView(latex: latex, displayMode: displayMode, colorScheme: colorScheme, horizontalInset: horizontalInset)
        }
    }

    private var plainTextFallback: some View {
        let theme = AppTheme(colorScheme: colorScheme)
        let display = LatexPlainText.format(latex)
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(display.isEmpty ? "Empty equation" : display)
                .font(.system(size: 16))
                .foregroundStyle(display.isEmpty ? theme.secondaryText : theme.primaryText)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 8)
        }
    }
}

struct KaTeXWebView: UIViewRepresentable {
    let latex: String
    let displayMode: Bool
    let colorScheme: ColorScheme
    var horizontalInset: CGFloat = 8

    class Coordinator {
        var loadedKey: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = "\(colorScheme == .dark ? "d" : "l")|\(displayMode ? "1" : "0")|\(latex)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        webView.loadHTMLString(html(for: latex), baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    func html(for latex: String) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "</", with: "<\\/")
        let textColor = colorScheme == .dark ? "#F3F4F6" : "#111827"
        let bgColor = "transparent"
        let displayJS = displayMode ? "true" : "false"
        return """
        <!doctype html>
        <html dir="ltr" lang="en"><head><meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css" />
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <style>
          html, body { margin:0; padding:0; background:\(bgColor); color:\(textColor);
                       font-family:-apple-system,Helvetica,Arial,sans-serif;
                       direction:ltr; text-align:left; unicode-bidi:embed; }
          body { display:flex; align-items:center; justify-content:flex-start;
                 min-height:0; padding:4px \(Int(horizontalInset))px; }
          #host { font-size: 16px; max-width:100%; overflow-x:auto; text-align:left; white-space:nowrap; }
          .katex { color:\(textColor); direction:ltr; }
          .placeholder { color:#9CA3AF; font-style:italic; }
        </style></head>
        <body dir="ltr">
        <div id="host" dir="ltr"><span class="placeholder">Empty equation</span></div>
        <script>
          window.addEventListener('load', function(){
            try {
              var src = `\(escaped)`;
              if (src && src.trim().length > 0) {
                katex.render(src, document.getElementById('host'), {
                  throwOnError: false,
                  displayMode: \(displayJS)
                });
              }
            } catch (e) {
              document.getElementById('host').innerText = String(e);
            }
          });
        </script>
        </body></html>
        """
    }
}
#else
struct MathFormulaRenderer: View {
    let latex: String
    let displayMode: Bool
    var horizontalInset: CGFloat = 8
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = AppTheme(colorScheme: colorScheme)
        let display = LatexPlainText.format(latex)
        ScrollView(.horizontal, showsIndicators: false) {
            Text(display.isEmpty ? "Empty equation" : display)
                .font(.system(size: 16))
                .foregroundStyle(display.isEmpty ? theme.secondaryText : theme.primaryText)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 8)
        }
    }
}
#endif

// Renders LaTeX to a best-effort plain-text approximation. Used on platforms
// without a KaTeX/MathJax WebView (Android via Skip). It is not a full LaTeX
// parser — it handles the tokens emitted by our math keyboard.
enum LatexPlainText {
    static func format(_ latex: String) -> String {
        guard !latex.isEmpty else { return "" }
        var s = latex

        // Preserve the editor cursor when the iOS KaTeX marker reaches the
        // plain-text renderer.
        s = replacePattern(s, command: "\\textcolor", argCount: 2, replacement: "|")

        // Single-token replacements.
        let symbols: [(String, String)] = [
            ("\\pi", "π"),
            ("\\int", "∫"),
            ("\\sum", "Σ"),
            ("\\times", "×"),
            ("\\div", "÷"),
            ("\\cdot", "·"),
            ("\\leq", "≤"),
            ("\\geq", "≥"),
            ("\\neq", "≠"),
            ("\\approx", "≈"),
            ("\\infty", "∞"),
        ]
        for (from, to) in symbols {
            // The space after `\div` is only there to keep the command name
            // from running into what follows. Once the symbol replaces it the
            // space is a stray gap, so it goes with the command.
            s = s.replacingOccurrences(of: from + " ", with: to)
            s = s.replacingOccurrences(of: from, with: to)
        }

        // \frac{A}{B} → A/B, \sqrt{A} → √(A). Repeat to handle nesting.
        for _ in 0..<8 {
            let next = collapseTwoArg(collapseOneArg(s, command: "\\sqrt", wrap: { "√(\($0.isEmpty ? emptySlot : $0))" }),
                                      command: "\\frac",
                                      wrap: { a, b in "\(fractionSide(a))/\(fractionSide(b))" })
            if next == s { break }
            s = next
        }

        // `^{23}` is x-to-the-23, so the whole run lifts: `²³`. Anything that
        // is not plain digits keeps brackets, because `x^{3/2}` flattened to
        // `x^3/2` says x-cubed-over-two — a different number entirely.
        s = collapseOneArg(s, command: "^", wrap: { scriptText($0, digits: superscriptDigits, marker: "^") })
        s = collapseOneArg(s, command: "_", wrap: { scriptText($0, digits: subscriptDigits, marker: "_") })

        return s
    }

    /// Stands in for a slot the student has not filled in yet, so an
    /// unfinished fraction reads as `3/□` rather than trailing off into `3/`.
    static let emptySlot = "□"

    static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
    ]

    static let subscriptDigits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
    ]

    /// One side of a fraction. A bare number, a bare name or a group already
    /// inside its own parentheses reads fine as it is — `3/2`, not `(3)/(2)` —
    /// but anything holding an operator needs the brackets to keep its meaning.
    static func fractionSide(_ arg: String) -> String {
        if arg.isEmpty { return emptySlot }
        if arg.count == 1 { return arg }
        if isSingleParenGroup(arg) { return arg }
        // Only an operator can be read the wrong way once the bar becomes a
        // slash: `1+2` over 3 has to keep its brackets, but `x²` over 2 is
        // `x²/2` and bracketing it only adds noise.
        let operators = "+-−×÷·/= "
        let hasOperator = arg.contains { operators.contains($0) }
        return hasOperator ? "(\(arg))" : arg
    }

    /// Whether the string is one parenthesised group — `(1+2)` is, `(1)+(2)`
    /// only looks like one from its two ends. A root sign in front comes along,
    /// so `√(9)` over 2 stays `√(9)/2` rather than gaining a second pair.
    static func isSingleParenGroup(_ arg: String) -> Bool {
        var arg = arg
        if arg.hasPrefix("√") { arg = String(arg.dropFirst()) }
        guard arg.hasPrefix("("), arg.hasSuffix(")") else { return false }
        let chars = Array(arg)
        var depth = 0
        for i in 0..<chars.count {
            if chars[i] == "(" { depth += 1 }
            else if chars[i] == ")" {
                depth -= 1
                if depth == 0 { return i == chars.count - 1 }
            }
        }
        return false
    }

    static func scriptText(_ arg: String, digits: [Character: Character], marker: String) -> String {
        if arg.isEmpty { return "\(marker)\(emptySlot)" }
        var lifted = ""
        var allDigits = true
        for ch in arg {
            if let mapped = digits[ch] {
                lifted.append(mapped)
            } else {
                allDigits = false
                break
            }
        }
        if allDigits { return lifted }
        if arg.count == 1 { return "\(marker)\(arg)" }
        return "\(marker)(\(arg))"
    }

    // Finds `command{ARG}` and replaces with `wrap(ARG)`. ARG cannot contain
    // nested braces — call this in a loop to handle nesting.
    static func collapseOneArg(_ source: String, command: String, wrap: (String) -> String) -> String {
        var s = source
        while let range = s.range(of: command + "{") {
            let afterBrace = range.upperBound
            guard let close = balancedClose(s, from: afterBrace) else { break }
            let arg = String(s[afterBrace..<close])
            let replacement = wrap(arg)
            let afterClose = s.index(after: close)
            s.replaceSubrange(range.lowerBound..<afterClose, with: replacement)
        }
        return s
    }

    // Finds `command{A}{B}` and replaces with `wrap(A, B)`.
    static func collapseTwoArg(_ source: String, command: String, wrap: (String, String) -> String) -> String {
        var s = source
        while let range = s.range(of: command + "{") {
            let afterFirstBrace = range.upperBound
            guard let firstClose = balancedClose(s, from: afterFirstBrace) else { break }
            let afterFirstClose = s.index(after: firstClose)
            guard afterFirstClose < s.endIndex, s[afterFirstClose] == "{" else { break }
            let afterSecondBrace = s.index(after: afterFirstClose)
            guard let secondClose = balancedClose(s, from: afterSecondBrace) else { break }
            let a = String(s[afterFirstBrace..<firstClose])
            let b = String(s[afterSecondBrace..<secondClose])
            let replacement = wrap(a, b)
            let endIdx = s.index(after: secondClose)
            s.replaceSubrange(range.lowerBound..<endIdx, with: replacement)
        }
        return s
    }

    // Returns the index of the `}` that balances the most recent `{` before
    // `start`. Walks forward from `start` tracking depth.
    static func balancedClose(_ s: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    // Replaces `\command{...}{...}` with a compact marker.
    static func replacePattern(_ source: String, command: String, argCount: Int, replacement: String) -> String {
        var s = source
        while let range = s.range(of: command + "{") {
            var cursor = range.upperBound
            var ok = true
            for arg in 0..<argCount {
                guard let close = balancedClose(s, from: cursor) else { ok = false; break }
                cursor = s.index(after: close)
                if arg < argCount - 1 {
                    guard cursor < s.endIndex, s[cursor] == "{" else { ok = false; break }
                    cursor = s.index(after: cursor)
                }
            }
            if !ok { break }
            s.replaceSubrange(range.lowerBound..<cursor, with: replacement)
        }
        return s
    }
}

#if os(iOS)
#Preview("formula") {
    VStack(spacing: 20) {
        MathFormulaView(latex: "\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", displayMode: true)
            .frame(height: 80)
        MathFormulaView(latex: "x^2 + 5x + 6 = 0", displayMode: true)
            .frame(height: 60)
    }
    .padding()
}
#endif
