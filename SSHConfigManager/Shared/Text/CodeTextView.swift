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
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: String(index + 1))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32, alignment: .trailing)
                            Text(Self.attributed(CodeHighlighter.spans(for: line)))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
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
