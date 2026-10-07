import SSHConfigKit

enum HighlightRole: Equatable, Sendable { case comment, keyword, key, value, unknown, plain }

struct HighlightSpan: Equatable, Sendable {
    let text: String
    let role: HighlightRole
}

/// Colors follow the parser's own classification, so what is shown is what was understood.
enum CodeHighlighter {
    /// Lines ssh does not understand get a non-color marker too.
    static func isFlagged(_ line: ConfigLine) -> Bool { line.kind == .unknown }

    static func spans(for line: ConfigLine) -> [HighlightSpan] {
        var raw = line.raw
        if raw.unicodeScalars.last == "\r" { raw = String(raw.unicodeScalars.dropLast()) }
        guard !raw.isEmpty else { return [] }

        switch line.kind {
        case .blank:
            return [HighlightSpan(text: raw, role: .plain)]
        case .comment:
            return [HighlightSpan(text: raw, role: .comment)]
        case .unknown:
            return [HighlightSpan(text: raw, role: .unknown)]
        case .hostStart, .matchStart, .include:
            return split(raw, keyRole: .keyword)
        case .directive:
            return split(raw, keyRole: .key)
        }
    }

    /// indent (plain) + first token (keyRole) + rest (value)
    private static func split(_ raw: String, keyRole: HighlightRole) -> [HighlightSpan] {
        let scalars = Array(raw.unicodeScalars)
        var i = 0
        while i < scalars.count && (scalars[i] == " " || scalars[i] == "\t") { i += 1 }
        let indentEnd = i
        while i < scalars.count && scalars[i] != " " && scalars[i] != "\t" && scalars[i] != "=" { i += 1 }
        let keyEnd = i

        var spans: [HighlightSpan] = []
        if indentEnd > 0 { spans.append(HighlightSpan(text: string(scalars[0..<indentEnd]), role: .plain)) }
        spans.append(HighlightSpan(text: string(scalars[indentEnd..<keyEnd]), role: keyRole))
        if keyEnd < scalars.count { spans.append(HighlightSpan(text: string(scalars[keyEnd...]), role: .value)) }
        return spans
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }
}
