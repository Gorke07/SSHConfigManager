/// Lossless pieces of a keyed config line: `indent + key + separator + value + trailing == raw`.
struct LineParts: Equatable, Sendable {
    var indent: String
    var key: String
    var separator: String
    var value: String
    /// Whitespace, trailing comment and a trailing "\r", if any.
    var trailing: String

    var raw: String { indent + key + separator + value + trailing }
}

enum LineTokenizer {
    enum Classification: Equatable, Sendable {
        case blank
        case comment
        case keyed(LineParts)
        case unknown

        var parts: LineParts? {
            if case .keyed(let parts) = self { return parts }
            return nil
        }
    }

    /// Works on Unicode scalars, never Characters: "\r\n" and combining marks
    /// form single Characters and would hide boundaries.
    static func classify(_ raw: String) -> Classification {
        let s = Array(raw.unicodeScalars)
        var end = s.count
        if end > 0 && s[end - 1] == "\r" { end -= 1 }

        var i = 0
        while i < end && isSpace(s[i]) { i += 1 }
        if i == end { return .blank }
        if s[i] == "#" { return .comment }

        let indentEnd = i
        while i < end && !isSpace(s[i]) && s[i] != "=" { i += 1 }
        let keyEnd = i
        guard keyEnd > indentEnd, s[indentEnd..<keyEnd].allSatisfy(isKeyScalar) else { return .unknown }

        while i < end && isSpace(s[i]) { i += 1 }
        if i < end && s[i] == "=" {
            i += 1
            while i < end && isSpace(s[i]) { i += 1 }
        }
        let valueStart = i

        var valueEnd = i
        var j = i
        var inQuote = false
        while j < end {
            if !inQuote && isSpace(s[j]) { j += 1; continue }
            if !inQuote && s[j] == "#" { break }
            while j < end && (inQuote || !isSpace(s[j])) {
                if s[j] == "\"" { inQuote.toggle() }
                j += 1
            }
            valueEnd = j
        }

        return .keyed(LineParts(
            indent: string(s[0..<indentEnd]),
            key: string(s[indentEnd..<keyEnd]),
            separator: string(s[keyEnd..<valueStart]),
            value: string(s[valueStart..<valueEnd]),
            trailing: string(s[valueEnd..<s.count])
        ))
    }

    /// Splits a value into arguments; double quotes group and are removed.
    static func arguments(of value: String) -> [String] {
        var args: [String] = []
        var current = String.UnicodeScalarView()
        var inQuote = false
        var hasToken = false
        for c in value.unicodeScalars {
            if c == "\"" {
                inQuote.toggle()
                hasToken = true
                continue
            }
            if !inQuote && isSpace(c) {
                if hasToken {
                    args.append(String(current))
                    current = String.UnicodeScalarView()
                    hasToken = false
                }
                continue
            }
            current.append(c)
            hasToken = true
        }
        if hasToken { args.append(String(current)) }
        return args
    }

    /// Rebuilds a line with a new value while keeping indent, separator, comment and line ending.
    static func replacingValue(in parts: LineParts, with newValue: String) -> String {
        let separator = parts.separator.isEmpty ? " " : parts.separator
        var trailing = parts.trailing
        if trailing.unicodeScalars.first == "#" { trailing = " " + trailing }
        return parts.indent + parts.key + separator + newValue + trailing
    }

    static func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }

    private static func isKeyScalar(_ c: Unicode.Scalar) -> Bool {
        (65...90).contains(c.value) || (97...122).contains(c.value) || (48...57).contains(c.value)
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }
}
