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
          MathFormulaView(latex: message.text, displayMode: true)
            .frame(minWidth: 160, maxWidth: 300, minHeight: Self.formulaHeight(message.text))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(theme.appCardBackground)
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(message.isMine ? theme.appPink : theme.appBorder.opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
          formattedContent
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(message.isMine ? theme.appPink : theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }

        Text(timeText)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
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
      background: message.isMine ? theme.appPurpleSoft : theme.appGreenSoft,
      tint: message.isMine ? theme.appPurple : theme.appGreen
    )
  }

  private var formattedContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Self.messageSegments(from: Self.readableText(message.text))) { segment in
        if segment.isFormula {
          MathFormulaView(latex: segment.text, displayMode: true)
            .frame(minWidth: 220, maxWidth: 300, minHeight: Self.formulaHeight(segment.text))
            .environment(\.layoutDirection, .leftToRight)
        } else {
          Self.formattedText(segment.text)
            .font(.system(size: 14))
            .foregroundStyle(message.isMine ? theme.appCardBackground: theme.appPrimaryText)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
        }
      }
    }
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
    var readable = text
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\t", with: "  ")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    while readable.contains("\n\n\n") {
      readable = readable.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    return readable
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

  private static func messageSegments(from text: String) -> [ChatMessageSegment] {
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
}
