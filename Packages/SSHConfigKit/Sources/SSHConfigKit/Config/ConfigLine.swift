public enum LineKind: Equatable, Sendable {
    case blank
    case comment
    /// `value` is the raw value text: quotes kept, trailing comment removed.
    case directive(key: String, value: String)
    case hostStart(patterns: [String])
    case matchStart(criteria: String)
    case include(paths: [String])
    /// A line we cannot interpret; it is preserved verbatim.
    case unknown

    var isHeader: Bool {
        switch self {
        case .hostStart, .matchStart: true
        default: false
        }
    }
}

public struct ConfigLine: Sendable {
    /// Exact original text without the "\n" separator (may end with "\r").
    public let raw: String
    public let kind: LineKind

    public init(raw: String) {
        self.raw = raw
        switch LineTokenizer.classify(raw) {
        case .blank: kind = .blank
        case .comment: kind = .comment
        case .unknown: kind = .unknown
        case .keyed(let parts):
            switch parts.key.asciiLowercased {
            case "host": kind = .hostStart(patterns: LineTokenizer.arguments(of: parts.value))
            case "match": kind = .matchStart(criteria: parts.value)
            case "include": kind = .include(paths: LineTokenizer.arguments(of: parts.value))
            default: kind = .directive(key: parts.key, value: parts.value)
            }
        }
    }

    var parts: LineParts? { LineTokenizer.classify(raw).parts }
}

extension ConfigLine: Equatable {
    public static func == (lhs: ConfigLine, rhs: ConfigLine) -> Bool {
        Array(lhs.raw.utf8).elementsEqual(Array(rhs.raw.utf8)) && lhs.kind == rhs.kind
    }
}
