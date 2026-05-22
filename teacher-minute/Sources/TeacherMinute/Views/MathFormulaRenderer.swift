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

    var body: some View {
        MathFormulaRenderer(latex: latex, displayMode: displayMode)
            .environment(\.layoutDirection, .leftToRight)
    }
}

#if canImport(WebKit) && canImport(UIKit)
import WebKit

struct MathFormulaRenderer: View {
    let latex: String
    let displayMode: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        KaTeXWebView(latex: latex, displayMode: displayMode, colorScheme: colorScheme)
    }
}

struct KaTeXWebView: UIViewRepresentable {
    let latex: String
    let displayMode: Bool
    let colorScheme: ColorScheme

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
                 min-height:0; padding:4px 8px; }
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = AppTheme(colorScheme: colorScheme)
        let display = LatexPlainText.format(latex)
        ScrollView(.horizontal, showsIndicators: false) {
            Text(display.isEmpty ? "Empty equation" : display)
                .font(.system(size: 16))
                .foregroundStyle(display.isEmpty ? theme.appSecondaryText : theme.appPrimaryText)
                .padding(.horizontal, 10)
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
            s = s.replacingOccurrences(of: from, with: to)
        }

        // \frac{A}{B} → (A)/(B), \sqrt{A} → √(A). Repeat to handle nesting.
        for _ in 0..<8 {
            let next = collapseTwoArg(collapseOneArg(s, command: "\\sqrt", wrap: { "√(\($0))" }),
                                      command: "\\frac",
                                      wrap: { a, b in "(\(a))/(\(b))" })
            if next == s { break }
            s = next
        }

        // Cursor placeholder `|` survives as-is.
        // ^{N} for single digit → Unicode superscript.
        let supers: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        for (digit, sup) in supers {
            s = s.replacingOccurrences(of: "^{\(digit)}", with: String(sup))
        }
        // _{N} for single digit → Unicode subscript.
        let subs: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
        ]
        for (digit, sub) in subs {
            s = s.replacingOccurrences(of: "_{\(digit)}", with: String(sub))
        }

        // Generic ^{...} / _{...} → ^... / _...
        s = collapseOneArg(s, command: "^", wrap: { "^\($0)" })
        s = collapseOneArg(s, command: "_", wrap: { "_\($0)" })

        return s
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
