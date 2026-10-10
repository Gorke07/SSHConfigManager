import Foundation

public enum OptionSource: Equatable, Sendable {
    /// The target host's own block.
    case thisBlock
    /// Another `Host` block of the root file (e.g. `Host *`).
    case otherHost(patterns: [String])
    /// Before the first Host/Match line of the root file.
    case global
    /// A line in an included file (patterns of its Host block; empty outside any block).
    case include(file: URL, patterns: [String])
}

public struct ResolvedValue: Equatable, Sendable {
    public let value: String
    public let source: OptionSource

    public init(value: String, source: OptionSource) {
        self.value = value
        self.source = source
    }
}

public struct ResolvedConfig: Equatable, Sendable {
    /// ASCII-lowercased keys; single-valued options have one entry, multi-valued ones accumulate.
    public var options: [String: [ResolvedValue]] = [:]
    /// Match blocks are not evaluated; their options may still apply at run time.
    public var hasMatchBlocks = false

    public init() {}

    public func first(_ key: String) -> ResolvedValue? { options[key.asciiLowercased]?.first }
}

/// Applies ssh_config(5)'s rule for one host: lines are read in order (Includes in place), a
/// `Host` line starts a block that applies when its patterns match, and for each option the first
/// obtained value is used — except options that may be given several times, which accumulate.
public enum ConfigResolver {
    public static let multiValueKeys: Set<String> = [
        "identityfile", "certificatefile", "localforward", "remoteforward", "dynamicforward", "sendenv", "setenv",
    ]

    /// `*` and `?` wildcards, ASCII case-insensitive (ssh lowercases host names).
    public static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.asciiLowercased.unicodeScalars)
        let t = Array(text.asciiLowercased.unicodeScalars)
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count && (p[pi] == "?" || p[pi] == t[ti]) {
                pi += 1; ti += 1
            } else if pi < p.count && p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// A Host line matches when a positive pattern matches and no `!` pattern does.
    public static func hostLineMatches(_ patterns: [String], alias: String) -> Bool {
        var positive = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if wildcardMatch(String(pattern.dropFirst()), alias) { return false }
            } else if wildcardMatch(pattern, alias) {
                positive = true
            }
        }
        return positive
    }

    public static func resolve(
        alias: String,
        document: ConfigDocument,
        targetHeader: Int?,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)]
    ) -> ResolvedConfig {
        var result = ResolvedConfig()
        walk(document, file: nil, depth: 0, alias: alias, targetHeader: targetHeader,
             active: true, blockSource: .global, includes: includes, into: &result)
        return result
    }

    private static func walk(
        _ document: ConfigDocument, file: URL?, depth: Int, alias: String, targetHeader: Int?,
        active startActive: Bool, blockSource startSource: OptionSource,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)],
        into result: inout ResolvedConfig
    ) {
        guard depth < 16 else { return }
        var active = startActive
        var source = startSource
        for (index, line) in document.lines.enumerated() {
            switch line.kind {
            case .hostStart(let patterns):
                active = hostLineMatches(patterns, alias: alias)
                if let file {
                    source = .include(file: file, patterns: patterns)
                } else {
                    source = index == targetHeader ? .thisBlock : .otherHost(patterns: patterns)
                }
            case .matchStart:
                result.hasMatchBlocks = true
                active = false
            case .include(let paths):
                guard active else { continue }
                for (includedFile, included) in includes(IncludeDirective(line: index, paths: paths)) {
                    walk(included, file: includedFile, depth: depth + 1, alias: alias, targetHeader: nil,
                         active: true, blockSource: .include(file: includedFile, patterns: []),
                         includes: includes, into: &result)
                }
            case .directive(let key, let rawValue):
                guard active else { continue }
                let lower = key.asciiLowercased
                let value = ResolvedValue(value: ValueFormatter.display(key: key, rawValue: rawValue), source: source)
                if multiValueKeys.contains(lower) {
                    result.options[lower, default: []].append(value)
                } else if result.options[lower] == nil {
                    result.options[lower] = [value]
                }
            case .blank, .comment, .unknown:
                continue
            }
        }
    }
}
