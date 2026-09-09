import SwiftUI

private struct ChatMessageSegment: Identifiable {
  let id: Int
  let text: String
  let isFormula: Bool
}

struct ChatBubble: View {
  let message: ChatMessage
  let timeText: String
  let avatarImageURL: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.isMine { Spacer(minLength: hasFormulaContent ? 0 : 54) }

      if !message.isMine {
        avatar
      }

      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 5) {
        if ChatBubble.isLatex(message.text) {
          MathFormulaView(latex: Self.latexContent(message.text), displayMode: true)
            .frame(minWidth: 160, maxWidth: 300, minHeight: Self.formulaHeight(Self.latexContent(message.text)))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(theme.cardBackground)
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(message.isMine ? theme.accent : theme.controlBorder.opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
          formattedContent
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(message.isMine ? theme.outgoingBubbleBackground : theme.incomingBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }

        Text(timeText)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(theme.secondaryText)
      }

      if message.isMine {
        avatar
      }

      if !message.isMine { Spacer(minLength: hasFormulaContent ? 0 : 54) }
    }
  }

  private var hasFormulaContent: Bool {
    Self.containsFormula(Self.readableText(message.text))
  }

  private var contentMaxWidth: CGFloat {
    hasFormulaContent ? 300 : 280
  }

  var avatar: some View {
    ProfileAvatarView(
      imageURL: avatarImageURL,
      size: 24,
      fallbackSystemImage: "person.crop.circle.fill",
      background: message.isMine ? theme.accentBackground : theme.positiveBackground,
      tint: message.isMine ? theme.accentStrong : theme.positive
    )
  }

  private var formattedContent: some View {
    FormulaAwareText(
      text: message.text,
      textColor: message.isMine ? theme.outgoingBubbleText : theme.incomingBubbleText
    )
  }

  static func formattedText(_ text: String) -> Text {
#if os(Android)
    return Text(Self.plainMarkdownText(text))
#else
    if let attributed = try? AttributedString(markdown: text) {
      return Text(attributed)
    }
    return Text(Self.plainMarkdownText(text))
#endif
  }

  static func readableText(_ text: String) -> String {
    var readable = unescapingOutsideFormulas(text)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    while readable.contains("\n\n\n") {
      readable = readable.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    return readable
  }

  /// Turns the escape sequences a backend may have serialised into real
  /// whitespace, but only in the prose between formulas.
  ///
  /// `\times` and `\neq` are LaTeX commands, not an escaped tab and an escaped
  /// newline. Unescaping the whole string ate their first letter and rendered
  /// `6\times0.5` as `6  imes0.5`, so what is inside `$...$` is left alone.
  static func unescapingOutsideFormulas(_ text: String) -> String {
    var out = ""
    var rest = text[...]

    while let dollar = rest.firstIndex(of: "$") {
      out += unescaped(String(rest[..<dollar]))

      let isDisplay = rest[rest.index(after: dollar)...].first == "$"
      let delimiter = isDisplay ? "$$" : "$"
      let contentStart = rest.index(dollar, offsetBy: delimiter.count)
      guard let close = rest[contentStart...].range(of: delimiter)?.lowerBound else {
        // An unclosed delimiter: the rest is not a formula, so it unescapes
        // like any other prose.
        out += unescaped(String(rest[dollar...]))
        return out
      }

      let end = rest.index(close, offsetBy: delimiter.count)
      out += String(rest[dollar..<end])
      rest = rest[end...]
    }

    return out + unescaped(String(rest))
  }

  private static func unescaped(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\t", with: "  ")
      .replacingOccurrences(of: "\r\n", with: "\n")
  }

  static func containsFormula(_ text: String) -> Bool {
    let readable = readableText(text)
    return readable.contains("$") || readable.contains("\\frac") || readable.contains("\\sqrt")
  }

  static func formulaHeight(_ latex: String) -> CGFloat {
    let fractionCount = latex.components(separatedBy: "\\frac").count - 1
    let tallDelimiterCount = latex.components(separatedBy: "\\left").count - 1
    let lineCount = max(1, latex.components(separatedBy: "\\\\").count)
    let lengthRows = max(0, latex.count / 42)
    let estimated = 54 + fractionCount * 18 + tallDelimiterCount * 10 + (lineCount - 1) * 24 + lengthRows * 14
    return CGFloat(min(max(estimated, 64), 180))
  }

  fileprivate static func messageSegments(from text: String) -> [ChatMessageSegment] {
    var segments: [ChatMessageSegment] = []
    var remaining = text[...]
    var index = 0

    while let dollar = remaining.firstIndex(of: "$") {
      let before = String(remaining[..<dollar]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !before.isEmpty {
        segments.append(ChatMessageSegment(id: index, text: before, isFormula: false))
        index += 1
      }

      let isDisplayFormula = remaining[remaining.index(after: dollar)...].first == "$"
      let delimiterLength = isDisplayFormula ? 2 : 1
      let contentStart = remaining.index(dollar, offsetBy: delimiterLength)
      let delimiter = isDisplayFormula ? "$$" : "$"
      guard let close = remaining[contentStart...].range(of: delimiter)?.lowerBound else {
        let tail = String(remaining[dollar...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
          segments.append(ChatMessageSegment(id: index, text: tail, isFormula: false))
        }
        return segments
      }

      let formula = String(remaining[contentStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !formula.isEmpty {
        segments.append(ChatMessageSegment(id: index, text: formula, isFormula: true))
        index += 1
      }

      remaining = remaining[remaining.index(close, offsetBy: delimiterLength)...]
    }

    let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty {
      segments.append(ChatMessageSegment(id: index, text: tail, isFormula: false))
    }
    return segments.isEmpty ? [ChatMessageSegment(id: 0, text: text, isFormula: false)] : segments
  }

  static func plainMarkdownText(_ text: String) -> String {
    text
      .components(separatedBy: "\n")
      .map { line in
        var readableLine = line
        for prefix in ["### ", "## ", "# "] {
          if readableLine.hasPrefix(prefix) {
            readableLine.removeFirst(prefix.count)
            break
          }
        }
        if readableLine.hasPrefix("- ") {
          readableLine = "• " + readableLine.dropFirst(2)
        }
        return readableLine
      }
      .joined(separator: "\n")
      .replacingOccurrences(of: "---", with: "")
      .replacingOccurrences(of: "$$", with: "")
      .replacingOccurrences(of: "$", with: "")
      .replacingOccurrences(of: "**", with: "")
      .replacingOccurrences(of: "__", with: "")
      .replacingOccurrences(of: "`", with: "")
  }

  static func isLatex(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.contains("\n") || trimmed.contains("\\n") {
      return false
    }
    if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") {
      return true
    }
    if trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]") {
      return true
    }
    if trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)") {
      return true
    }
    return trimmed.hasPrefix("\\frac") || trimmed.hasPrefix("\\sqrt")
  }

  static func latexContent(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$"), trimmed.count >= 4 {
      return String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]"), trimmed.count >= 4 {
      return String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)"), trimmed.count >= 4 {
      return String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
  }
}

/// Text that may carry `$$...$$` formulas, with each formula handed to the math
/// renderer instead of printed as markup.
///
/// Shared, so a formula a student writes reads the same wherever it is shown:
/// in the chat bubbles, and in the question preview the teacher accepts or
/// declines from. Splitting the two would mean the teacher deciding on raw
/// LaTeX while the student sees an equation.
struct FormulaAwareText: View {
  let text: String
  let textColor: Color
  var font: Font = .system(size: 14)
  var lineSpacing: CGFloat = 4
  var formulaMinWidth: CGFloat = 220
  var formulaMaxWidth: CGFloat = 300
  /// Lines allowed per text run. Zero means as many as it takes.
  var lineLimit: Int = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(ChatBubble.messageSegments(from: ChatBubble.readableText(text))) { segment in
        if segment.isFormula {
          MathFormulaView(latex: segment.text, displayMode: true)
            .frame(minWidth: formulaMinWidth, maxWidth: formulaMaxWidth, minHeight: ChatBubble.formulaHeight(segment.text))
            .environment(\.layoutDirection, .leftToRight)
        } else {
          textRun(segment.text)
        }
      }
    }
  }

  // `lineLimit` is applied through a builder rather than passed an optional,
  // matching how the rest of the app keeps conditional modifiers off Android's
  // transpiled path.
  @ViewBuilder
  private func textRun(_ run: String) -> some View {
    let styled = ChatBubble.formattedText(run)
      .font(font)
      .foregroundStyle(textColor)
      .lineSpacing(lineSpacing)
      .multilineTextAlignment(.leading)

    if lineLimit > 0 {
      styled.lineLimit(lineLimit)
    } else {
      styled
    }
  }
}

#if os(iOS)
#Preview("outgoing") {
    ChatBubble(
        message: ChatMessage(id: "1", text: "Hey! Can you help me with the quadratic formula?", senderUid: "me", senderRole: "student", createdAt: Date().timeIntervalSince1970 * 1000, isMine: true),
        timeText: "Just now",
        avatarImageURL: ""
    )
    .padding()
}

#Preview("incoming") {
    ChatBubble(
        message: ChatMessage(id: "2", text: "Sure! The formula is $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$. Let me walk you through it.", senderUid: "teacher", senderRole: "teacher", createdAt: Date().timeIntervalSince1970 * 1000, isMine: false),
        timeText: "1 min ago",
        avatarImageURL: ""
    )
    .padding()
}

#Preview("both") {
    VStack(spacing: 12) {
        ChatBubble(
            message: ChatMessage(id: "1", text: "Hey! Can you help me with the quadratic formula?", senderUid: "me", senderRole: "student", createdAt: Date().timeIntervalSince1970 * 1000, isMine: true),
            timeText: "2 min ago",
            avatarImageURL: ""
        )
        ChatBubble(
            message: ChatMessage(id: "2", text: "Sure! The formula is $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$.", senderUid: "teacher", senderRole: "teacher", createdAt: Date().timeIntervalSince1970 * 1000, isMine: false),
            timeText: "1 min ago",
            avatarImageURL: ""
        )
        ChatBubble(
            message: ChatMessage(id: "3", text: "Oh that makes sense, thank you!", senderUid: "me", senderRole: "student", createdAt: Date().timeIntervalSince1970 * 1000, isMine: true),
            timeText: "Just now",
            avatarImageURL: ""
        )
    }
    .padding()
}
#endif
