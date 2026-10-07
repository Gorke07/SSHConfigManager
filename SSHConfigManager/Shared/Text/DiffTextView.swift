import AppKit
import SSHConfigKit
import SwiftUI

/// Read-only unified diff with old/new line numbers and added/removed backgrounds.
struct DiffTextView: View {
    let hunks: [DiffHunk]

    init(hunks: [DiffHunk]) {
        self.hunks = hunks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "text.copyAll")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiffPresenter.unifiedText(for: hunks), forType: .string)
                }
                .buttonStyle(.borderless)
                .disabled(hunks.isEmpty)
            }
            .padding(6)
            if hunks.isEmpty {
                Text(String(localized: "diff.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Rows fill the widest row (or the viewport, when wider) so the added/removed
                // backgrounds end at the same edge.
                GeometryReader { viewport in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(DiffPresenter.rows(for: hunks)) { row in
                                DiffRowView(row: row)
                            }
                        }
                        .frame(minWidth: viewport.size.width, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct DiffRowView: View {
    let row: DiffRow

    var body: some View {
        HStack(spacing: 8) {
            number(row.oldNumber)
            number(row.newNumber)
            Text(verbatim: marker)
                .foregroundStyle(.secondary)
            Text(verbatim: row.text)
                .italic(row.kind == .noNewline)
                .foregroundStyle(row.kind == .header || row.kind == .noNewline ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var marker: String {
        switch row.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .header, .noNewline: ""
        }
    }

    private var background: Color {
        switch row.kind {
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        case .header: .secondary.opacity(0.08)
        case .context, .noNewline: .clear
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 32, alignment: .trailing)
    }
}
