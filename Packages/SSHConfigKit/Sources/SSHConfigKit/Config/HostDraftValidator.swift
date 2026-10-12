public enum DraftIssue: Equatable, Sendable {
    case controlCharacter(String)
    case emptyAlias
    case aliasHasWhitespace
    /// Another Host block uses this alias exactly as written.
    case duplicateAlias(String)
    /// Another Host block uses this alias differing only in ASCII letter case (a warning: ssh sees different hosts).
    case duplicateAliasCaseOnly(String)
    case invalidPort(String)
    case invalidDirectiveKey(String)
    case forbiddenDirectiveKey(String)
    case emptyDirectiveValue(String)
    /// The value (of the directive with this key) has an unquoted `#` starting a word: ssh would read the rest as a comment.
    case valueStartsComment(String)
    case identityFileMissing(String)
    /// A single-value directive (HostName, User, Port, ProxyJump, ForwardAgent) appears more than once in the draft:
    /// ssh uses the first value and ignores the rest (a warning; the lines stay in the file).
    case duplicateFieldKey(String)

    /// Blocking issues prevent applying the draft; warnings do not.
    public var isBlocking: Bool {
        switch self {
        case .identityFileMissing, .duplicateAliasCaseOnly, .duplicateFieldKey: false
        default: true
        }
    }
}

/// Directive-key rules shared by `HostDraftValidator` and the `ConfigDocument` edit guards.
enum DirectiveKeyRules {
    static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy {
            (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value)
        }
    }

    static func isForbidden(_ key: String) -> Bool {
        ["host", "match", "include"].contains(key.asciiLowercased)
    }
}

public struct HostDraftValidator: Sendable {
    /// Directives for which ssh keeps only the first value it finds.
    public static let singleValueKeys = ["HostName", "User", "Port", "ProxyJump", "ForwardAgent"]

    private let fileExists: @Sendable (String) -> Bool

    /// - Parameter fileExists: receives the IdentityFile value as typed (may start with "~").
    public init(fileExists: @escaping @Sendable (String) -> Bool) {
        self.fileExists = fileExists
    }

    public func issues(for draft: HostDraft, in document: ConfigDocument, editing header: Int?) -> [DraftIssue] {
        var issues: [DraftIssue] = []

        // Check patterns for control characters FIRST
        for pattern in draft.patterns {
            if pattern.containsControlCharacter {
                issues.append(.controlCharacter(pattern))
            }
        }

        if !issues.isEmpty { return issues }

        // Patterns the block being edited already has (e.g. a quoted `Host "my host"`) never block editing.
        let own = Set(header.flatMap { line in document.hosts.first { $0.headerLine == line } }.map { HostDraft($0).patterns } ?? [])
        if draft.patterns.isEmpty || draft.patterns.contains(where: \.isEmpty) {
            issues.append(.emptyAlias)
        } else if draft.patterns.contains(where: { !own.contains($0) && $0.unicodeScalars.contains(where: LineTokenizer.isSpace) }) {
            issues.append(.aliasHasWhitespace)
        } else {
            // Only aliases the draft adds are checked: patterns already in the block being edited are skipped, so
            // existing duplicates never block editing. An added alias that exactly equals another block's (or a
            // repeat within the draft) is a blocking duplicate. One that differs only in ASCII case from another
            // block's is a non-blocking warning: ssh matches Host patterns case-sensitively, so it is allowed,
            // but flagged as a likely mistake (spec §8).
            let others = document.hosts.filter { $0.headerLine != header && !$0.isPattern }.flatMap(\.patterns)
            let takenExact = Set(others)
            let takenFolded = Set(others.map(\.asciiLowercased))

            var seenExact = Set<String>()
            var seenFolded = Set<String>()
            for pattern in draft.patterns where !HostEntry(headerLine: 0, patterns: [pattern], directives: []).isPattern {
                // Aliases the block already had are not checked against other blocks (editing must stay
                // possible), but repeats within the draft still are.
                let isOwn = own.contains(pattern)
                let folded = pattern.asciiLowercased
                if seenExact.contains(pattern) || (!isOwn && takenExact.contains(pattern)) {
                    issues.append(.duplicateAlias(pattern))
                } else if seenFolded.contains(folded) || (!isOwn && takenFolded.contains(folded)) {
                    issues.append(.duplicateAliasCaseOnly(pattern))
                }
                seenExact.insert(pattern)
                seenFolded.insert(folded)
            }
        }

        for directive in draft.directives {
            // Check directive key for control characters FIRST
            if directive.key.containsControlCharacter {
                issues.append(.controlCharacter(directive.key))
                continue
            }

            let key = directive.key.asciiLowercased
            if !DirectiveKeyRules.isValid(directive.key) {
                issues.append(.invalidDirectiveKey(directive.key))
                continue
            }
            if DirectiveKeyRules.isForbidden(directive.key) {
                issues.append(.forbiddenDirectiveKey(directive.key))
                continue
            }
            // Check value for control characters before port check
            if directive.value.containsControlCharacter {
                issues.append(.controlCharacter(directive.key))
                continue
            }
            if LineTokenizer.startsComment(ValueFormatter.encode(key: directive.key, value: directive.value)) {
                issues.append(.valueStartsComment(directive.key))
                continue
            }
            if key == "port" {
                if !Self.isValidPort(directive.value) { issues.append(.invalidPort(directive.value)) }
                continue
            }
            if directive.value.unicodeScalars.allSatisfy(LineTokenizer.isSpace) {
                issues.append(.emptyDirectiveValue(directive.key))
                continue
            }
            if key == "identityfile", !directive.value.contains("%"), !fileExists(directive.value) {
                issues.append(.identityFileMissing(directive.value))
            }
        }

        var counts: [String: Int] = [:]
        for directive in draft.directives { counts[directive.key.asciiLowercased, default: 0] += 1 }
        for key in Self.singleValueKeys where counts[key.asciiLowercased, default: 0] > 1 {
            issues.append(.duplicateFieldKey(key))
        }
        return issues
    }

    /// A number in 1...65535 (ASCII digits only), or a service name such as `ssh` (letters, digits, `-`, `_`,
    /// starting with a letter), which ssh looks up in /etc/services.
    static func isValidPort(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first else { return false }
        let isDigit = { (c: Unicode.Scalar) in (48...57).contains(c.value) }
        let isLetter = { (c: Unicode.Scalar) in (65...90).contains(c.value) || (97...122).contains(c.value) }
        if scalars.allSatisfy(isDigit) { return Int(value).map { (1...65535).contains($0) } ?? false }
        return isLetter(first) && scalars.allSatisfy { isLetter($0) || isDigit($0) || $0 == "-" || $0 == "_" }
    }
}
