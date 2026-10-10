public enum DraftIssue: Equatable, Sendable {
    case controlCharacter(String)
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

        if draft.patterns.isEmpty || draft.patterns.contains(where: \.isEmpty) {
            issues.append(.emptyAlias)
        } else if draft.patterns.contains(where: { $0.unicodeScalars.contains(where: LineTokenizer.isSpace) }) {
            issues.append(.aliasHasWhitespace)
        } else {
            // ssh matches Host patterns case-sensitively; a new alias that differs from an existing one only in
            // ASCII case is still rejected as a likely mistake (spec §8 lint policy), not because ssh folds case.
            let taken = Set(document.hosts
                .filter { $0.headerLine != header && !$0.isPattern }
                .flatMap(\.patterns)
                .map(\.asciiLowercased))

            // Check for duplicates within the draft itself (case-insensitive)
            var seenLower = Set<String>()
            for pattern in draft.patterns where !HostEntry(headerLine: 0, patterns: [pattern], directives: []).isPattern {
                let lower = pattern.asciiLowercased
                if seenLower.contains(lower) {
                    issues.append(.duplicateAlias(pattern))
                } else if taken.contains(lower) {
                    issues.append(.duplicateAlias(pattern))
                } else {
                    seenLower.insert(lower)
                }
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
            if key == "port" {
                // Port must be ASCII digits only and in range 1-65535
                let isValidPort = !directive.value.isEmpty &&
                    directive.value.unicodeScalars.allSatisfy { (48...57).contains($0.value) } &&
                    (Int(directive.value).map { (1...65535).contains($0) } ?? false)
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
