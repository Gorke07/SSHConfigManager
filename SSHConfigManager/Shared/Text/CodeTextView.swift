import AppKit
import SSHConfigKit
import SwiftUI

/// Read-only, line-numbered, highlighted view of config lines.
struct CodeTextView: View {
    let lines: [ConfigLine]

    init(lines: [ConfigLine]) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "text.copyAll")) {
                    let text = lines.map(\.raw).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
            }
            .padding(6)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let flagged = CodeHighlighter.isFlagged(line)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: String(index + 1))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32, alignment: .trailing)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .opacity(flagged ? 1 : 0)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(Self.attributed(CodeHighlighter.spans(for: line)))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .modifier(UnknownLineAccessibility(label: flagged ? Self.unknownLabel(number: index + 1, line: line) : nil))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private static func unknownLabel(number: Int, line: ConfigLine) -> String {
        let n = String(number)
        let text = CodeHighlighter.spans(for: line).map(\.text).joined()
        return String(localized: "code.a11y.unknown \(n) \(text)")
    }

    static func attributed(_ spans: [HighlightSpan]) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            var part = AttributedString(span.text)
            switch span.role {
            case .comment: part.foregroundColor = .secondary
            case .keyword: part.foregroundColor = .accentColor
            case .key: part.font = .system(.body, design: .monospaced).weight(.semibold)
            case .unknown: part.foregroundColor = .orange
            case .value, .plain: break
            }
            result += part
        }
        return result
    }
}

private struct UnknownLineAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            content
        }
    }
}
