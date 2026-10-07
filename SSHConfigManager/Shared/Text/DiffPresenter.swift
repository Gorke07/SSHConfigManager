import SSHConfigKit

struct DiffRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case header, context, added, removed, noNewline }
    let id: Int
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    let accessibilityLabel: String
}

enum DiffPresenter {
    static func rows(for hunks: [DiffHunk]) -> [DiffRow] {
        var rows: [DiffRow] = []
        func append(_ kind: DiffRow.Kind, _ old: Int?, _ new: Int?, _ text: String, _ label: String) {
            rows.append(DiffRow(id: rows.count, kind: kind, oldNumber: old, newNumber: new, text: text, accessibilityLabel: label))
        }
        for hunk in hunks {
            append(.header, nil, nil, hunk.header, hunk.header)
            for line in hunk.lines {
                let text = stripCR(line.text)
                switch line.kind {
                case .context:
                    let number = String(line.newNumber ?? 0)
                    append(.context, line.oldNumber, line.newNumber, text, String(localized: "diff.a11y.context \(number) \(text)"))
                case .added:
                    let number = String(line.newNumber ?? 0)
                    append(.added, nil, line.newNumber, text, String(localized: "diff.a11y.added \(number) \(text)"))
                case .removed:
                    let number = String(line.oldNumber ?? 0)
                    append(.removed, line.oldNumber, nil, text, String(localized: "diff.a11y.removed \(number) \(text)"))
                }
                if line.missingNewline {
                    let note = String(localized: "diff.noNewline")
                    append(.noNewline, nil, nil, note, note)
                }
            }
        }
        return rows
    }

    /// Standard unified diff (not localized) for the "Copy All" button.
    static func unifiedText(for hunks: [DiffHunk]) -> String {
        var out = ""
        for hunk in hunks {
            out += hunk.header + "\n"
            for line in hunk.lines {
                let prefix = switch line.kind {
                case .context: " "
                case .added: "+"
                case .removed: "-"
                }
                out += prefix + stripCR(line.text) + "\n"
                if line.missingNewline { out += "\\ No newline at end of file\n" }
            }
        }
        return out
    }

    private static func stripCR(_ text: String) -> String {
        text.unicodeScalars.last == "\r" ? String(text.unicodeScalars.dropLast()) : text
    }
}
