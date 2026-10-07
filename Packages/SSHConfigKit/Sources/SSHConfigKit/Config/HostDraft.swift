public struct DraftDirective: Equatable, Sendable {
    public var key: String
    /// Display form; quoting is applied on write by `ValueFormatter.encode`.
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// The desired state of a Host block, as edited in the UI.
public struct HostDraft: Equatable, Sendable {
    public var patterns: [String]
    public var directives: [DraftDirective]

    public init(patterns: [String], directives: [DraftDirective] = []) {
        self.patterns = patterns
        self.directives = directives
    }

    public init(_ entry: HostEntry) {
        patterns = entry.patterns
        directives = entry.directives.map { DraftDirective(key: $0.key, value: $0.value) }
    }
}
