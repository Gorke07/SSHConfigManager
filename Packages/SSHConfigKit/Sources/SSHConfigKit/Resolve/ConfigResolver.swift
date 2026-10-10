import Foundation

public enum OptionSource: Equatable, Sendable {
    /// The target host's own block.
    case thisBlock
    /// Another `Host` block of the root file (e.g. `Host *`).
    case otherHost(patterns: [String])
    /// Before the first Host/Match line of the root file.
    case global
    /// A line in an included file (patterns of the Host block it sits in; directives before the
    /// file's first Host line inherit the patterns of the block containing the Include, or [] outside any block).
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
        "identityfile", "certificatefile", "localforward", "remoteforward", "dynamicforward", "sendenv",
    ]

    /// `*` and `?` wildcards; comparison is exact and case-sensitive, as in OpenSSH.
    public static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.unicodeScalars)
        let t = Array(text.unicodeScalars)
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
        targetFile: URL? = nil,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)]
    ) -> ResolvedConfig {
        var result = ResolvedConfig()
        walk(document, file: nil, depth: 0, alias: alias, targetHeader: targetHeader,
             targetFile: targetFile.map(Self.normalized),
             active: true, blockSource: .global, parentPatterns: [], stack: [], includes: includes, into: &result)
        return result
    }

    /// Same normalization as the include-cycle key, so `/tmp` and `/private/tmp` compare equal.
    private static func normalized(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private static func walk(
        _ document: ConfigDocument, file: URL?, depth: Int, alias: String, targetHeader: Int?, targetFile: String?,
        active startActive: Bool, blockSource startSource: OptionSource,
        parentPatterns: [String], stack: Set<String>,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)],
        into result: inout ResolvedConfig
    ) {
        guard depth < 16 else { return }
        var active = startActive
        var source = startSource
        var blockPatterns = parentPatterns
        for (index, line) in document.lines.enumerated() {
            switch line.kind {
            case .hostStart(let patterns):
                active = hostLineMatches(patterns, alias: alias)
                blockPatterns = patterns
                // `targetFile == nil` means the target block is in the root document.
                let isTarget = index == targetHeader && file.map(Self.normalized) == targetFile
                if isTarget {
                    source = .thisBlock
                } else if let file {
                    source = .include(file: file, patterns: patterns)
                } else {
                    source = .otherHost(patterns: patterns)
                }
            case .matchStart:
                result.hasMatchBlocks = true
                active = false
            case .include(let paths):
                guard active else { continue }
                let current: [String]
                switch source {
                case .otherHost(let patterns), .include(_, let patterns): current = patterns
                case .thisBlock: current = blockPatterns
                case .global: current = []
                }
                for (includedFile, included) in includes(IncludeDirective(line: index, paths: paths)) {
                    let standardized = includedFile.standardizedFileURL
                    let key = standardized.resolvingSymlinksInPath().path
                    guard !stack.contains(key) else { continue }
                    walk(included, file: standardized, depth: depth + 1, alias: alias, targetHeader: targetHeader, targetFile: targetFile,
                         active: true, blockSource: .include(file: standardized, patterns: current),
                         parentPatterns: current, stack: stack.union([key]),
                         includes: includes, into: &result)
                }
            case .directive(let key, let rawValue):
                guard active else { continue }
                let lower = key.asciiLowercased
                if lower == "sendenv" {
                    // One value per whitespace-separated token; `-PATTERN` removes earlier entries that match
                    // it as a wildcard (verified with OpenSSH `ssh -G`), later tokens/lines may add them again.
                    // ssh rejects empty names and names containing `=`; backslash escapes are left as written.
                    for token in LineTokenizer.arguments(of: rawValue) {
                        if token.isEmpty || token.contains("=") { continue }
                        if token.hasPrefix("-") {
                            let pattern = String(token.dropFirst())
                            result.options[lower]?.removeAll { wildcardMatch(pattern, $0.value) }
                        } else {
                            result.options[lower, default: []].append(ResolvedValue(value: token, source: source))
                        }
                    }
                    continue
                }
                let value = ResolvedValue(value: ValueFormatter.display(key: key, rawValue: rawValue), source: source)
                if multiValueKeys.contains(lower) {
                    let dedupes = lower == "identityfile" || lower == "certificatefile"
                    if !(dedupes && result.options[lower]?.contains { $0.value == value.value } == true) {
                        result.options[lower, default: []].append(value)
                    }
                } else if result.options[lower] == nil {
                    result.options[lower] = [value]
                }
            case .blank, .comment, .unknown:
                continue
            }
        }
    }
}
