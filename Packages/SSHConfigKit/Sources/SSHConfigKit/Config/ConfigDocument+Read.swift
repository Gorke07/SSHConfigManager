public struct HostDirective: Equatable, Sendable {
    public let line: Int
    public let key: String
    /// Display value (see `ValueFormatter.display`).
    public let value: String

    public init(line: Int, key: String, value: String) {
        self.line = line
        self.key = key
        self.value = value
    }
}

public struct HostEntry: Identifiable, Equatable, Sendable {
    /// Index of the `Host` line. Valid only for the document version it came from.
    public let headerLine: Int
    public let patterns: [String]
    public let directives: [HostDirective]

    public init(headerLine: Int, patterns: [String], directives: [HostDirective]) {
        self.headerLine = headerLine
        self.patterns = patterns
        self.directives = directives
    }

    public var id: Int { headerLine }
    public var alias: String { patterns.first ?? "" }

    /// Wildcard / negated / empty blocks cannot be connected to.
    public var isPattern: Bool {
        patterns.isEmpty || patterns.contains { $0.contains("*") || $0.contains("?") || $0.hasPrefix("!") }
    }

    public func values(for key: String) -> [String] {
        let wanted = key.asciiLowercased
        return directives.filter { $0.key.asciiLowercased == wanted }.map(\.value)
    }

    public func value(for key: String) -> String? { values(for: key).first }
}

public struct MatchEntry: Equatable, Sendable {
    public let headerLine: Int
    public let criteria: String
    /// Raw text of the block (header through its last owned non-blank line).
    public let text: String

    public init(headerLine: Int, criteria: String, text: String) {
        self.headerLine = headerLine
        self.criteria = criteria
        self.text = text
    }
}

public struct IncludeDirective: Equatable, Sendable {
    public let line: Int
    public let paths: [String]
}

extension ConfigDocument {
    var headerIndices: [Int] { lines.indices.filter { lines[$0].kind.isHeader } }

    /// Index of the next header after `header`, or `lines.count`.
    func blockEnd(after header: Int) -> Int {
        var i = header + 1
        while i < lines.count && !lines[i].kind.isHeader { i += 1 }
        return i
    }

    /// Like `blockEnd`, but comment lines glued to the next header belong to that header.
    /// At EOF, trailing comments are owned only if contiguous with the block's content (no blank line).
    func ownedEnd(of header: Int) -> Int {
        let end = blockEnd(after: header)
        guard end < lines.count else {
            // No next header (EOF). Find last non-blank, non-comment line.
            var c = header
            for i in (header + 1)..<lines.count {
                if lines[i].kind != .blank && lines[i].kind != .comment {
                    c = i
                }
            }
            // Extend over directly following comments
            var e = c + 1
            while e < lines.count && lines[e].kind == .comment {
                e += 1
            }
            return e
        }

        // There IS a next header. Remove comments that belong to next header.
        var e = end
        while e - 1 > header && lines[e - 1].kind == .comment { e -= 1 }
        return e
    }

    public func hostEntry(at header: Int) -> HostEntry? {
        guard lines.indices.contains(header), case .hostStart(let patterns) = lines[header].kind else {
            return nil
        }
        let end = blockEnd(after: header)
        return HostEntry(headerLine: header, patterns: patterns, directives: directives(in: (header + 1)..<end))
    }

    public var hosts: [HostEntry] { headerIndices.compactMap(hostEntry(at:)) }

    public var matches: [MatchEntry] {
        headerIndices.compactMap { header in
            guard case .matchStart(let criteria) = lines[header].kind else { return nil }
            var end = ownedEnd(of: header)
            while end - 1 > header && lines[end - 1].kind == .blank { end -= 1 }
            let text = lines[header..<end].map(\.raw).joined(separator: "\n")
            return MatchEntry(headerLine: header, criteria: criteria, text: text)
        }
    }

    public var includes: [IncludeDirective] {
        lines.indices.compactMap { i in
            guard case .include(let paths) = lines[i].kind else { return nil }
            return IncludeDirective(line: i, paths: paths)
        }
    }

    public var globalDirectives: [HostDirective] {
        directives(in: 0..<(headerIndices.first ?? lines.count))
    }

    private func directives(in range: Range<Int>) -> [HostDirective] {
        range.compactMap { i in
            guard case .directive(let key, let value) = lines[i].kind else { return nil }
            return HostDirective(line: i, key: key, value: ValueFormatter.display(key: key, rawValue: value))
        }
    }
}
