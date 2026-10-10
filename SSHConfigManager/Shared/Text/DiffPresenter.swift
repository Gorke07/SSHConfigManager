import AppKit
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

/// The one monospaced font the diff rows draw with, and the measurements that use it.
@MainActor
enum DiffMetrics {
    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// Narrowest line-number column.
    static let minGutter: CGFloat = 32
    /// Marker column plus the three 8pt spacings and the 8pt padding on both sides.
    private static let fixedChrome: CGFloat = 8 + 24 + 16
    /// How many of the longest rows are measured (by character count and by UTF-16 length).
    private static let candidateCount = 5

    static func width(of text: String) -> CGFloat {
        // Tabs are measured as 8 spaces, which is never narrower than how the row draws them.
        let expanded = text.replacingOccurrences(of: "\t", with: String(repeating: " ", count: 8))
        return NSAttributedString(string: expanded, attributes: [.font: font]).size().width
    }

    static func gutterWidth(maxNumber: Int) -> CGFloat {
        max(minGutter, ceil(width(of: String(maxNumber))))
    }

    /// Minimum width every row needs: two gutters, the marker column and the widest text.
    static func minWidth(for rows: [DiffRow]) -> CGFloat {
        let byCount = rows.sorted { $0.text.count > $1.text.count }.prefix(candidateCount)
        let byUTF16 = rows.sorted { $0.text.utf16.count > $1.text.utf16.count }.prefix(candidateCount)
        var seen = Set<Int>()
        var widest: CGFloat = 0
        for row in byCount + byUTF16 where seen.insert(row.id).inserted {
            widest = max(widest, ceil(width(of: row.text)))
        }
        let maxNumber = rows.reduce(0) { max($0, $1.oldNumber ?? 0, $1.newNumber ?? 0) }
        return 2 * gutterWidth(maxNumber: maxNumber) + fixedChrome + widest
    }
}

/// Rows for a diff plus the width every row needs.
struct DiffContent: Equatable {
    let rows: [DiffRow]
    let minWidth: CGFloat
}

/// Builds `DiffContent` (rows and measured width) once per distinct `hunks` value instead of on every draw.
@MainActor
final class DiffRowsCache {
    private var hunks: [DiffHunk]?
    private var cached = DiffContent(rows: [], minWidth: 0)
    private(set) var buildCount = 0

    func content(for hunks: [DiffHunk]) -> DiffContent {
        if self.hunks == hunks { return cached }
        let rows = DiffPresenter.rows(for: hunks)
        cached = DiffContent(rows: rows, minWidth: DiffMetrics.minWidth(for: rows))
        self.hunks = hunks
        buildCount += 1
        return cached
    }
}
