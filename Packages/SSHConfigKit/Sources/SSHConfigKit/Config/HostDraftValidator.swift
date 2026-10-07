public enum DraftIssue: Equatable, Sendable {
    case emptyAlias
    case aliasHasWhitespace
    case duplicateAlias(String)
    case invalidPort(String)
    case invalidDirectiveKey(String)
    case forbiddenDirectiveKey(String)
    case emptyDirectiveValue(String)
    case identityFileMissing(String)

    /// Blocking issues prevent applying the draft; warnings do not.
    public var isBlocking: Bool {
        if case .identityFileMissing = self { return false }
        return true
    }
}

public struct HostDraftValidator: Sendable {
    private let fileExists: @Sendable (String) -> Bool

    /// - Parameter fileExists: receives the IdentityFile value as typed (may start with "~").
    public init(fileExists: @escaping @Sendable (String) -> Bool) {
        self.fileExists = fileExists
    }

    public func issues(for draft: HostDraft, in document: ConfigDocument, editing header: Int?) -> [DraftIssue] {
        var issues: [DraftIssue] = []

        if draft.patterns.isEmpty || draft.patterns.contains(where: \.isEmpty) {
            issues.append(.emptyAlias)
        } else if draft.patterns.contains(where: { $0.unicodeScalars.contains(where: LineTokenizer.isSpace) }) {
            issues.append(.aliasHasWhitespace)
        } else {
            // ssh lowercases host names before matching, so duplicates are case-insensitive.
            let taken = Set(document.hosts
                .filter { $0.headerLine != header && !$0.isPattern }
                .flatMap(\.patterns)
                .map(\.asciiLowercased))
            for pattern in draft.patterns where !HostEntry(headerLine: 0, patterns: [pattern], directives: []).isPattern {
                if taken.contains(pattern.asciiLowercased) { issues.append(.duplicateAlias(pattern)) }
            }
        }

        for directive in draft.directives {
            let key = directive.key.asciiLowercased
            let isValidKey = !directive.key.isEmpty && directive.key.unicodeScalars.allSatisfy {
                (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value)
            }
            if !isValidKey {
                issues.append(.invalidDirectiveKey(directive.key))
                continue
            }
            if ["host", "match", "include"].contains(key) {
                issues.append(.forbiddenDirectiveKey(directive.key))
                continue
            }
            if key == "port" {
                let isValidPort = Int(directive.value).map { (1...65535).contains($0) } ?? false
                if !isValidPort { issues.append(.invalidPort(directive.value)) }
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
        return issues
    }
}
