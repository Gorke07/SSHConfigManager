import Foundation

public enum HostIssue: Equatable, Sendable {
    /// The IdentityFile value as written.
    case missingIdentityFile(String)
    /// Several blocks name this alias; ssh uses the first block's values and later ones only add what is missing.
    case duplicateAlias(alias: String, isFirst: Bool)
    case unencryptedKey(String)
}

/// Problems a person would want to see next to a host. File access is injected so tests never
/// touch the disk; the app passes FileManager and KeyFileInspector.
public struct HostLint: Sendable {
    private let home: URL
    private let fileExists: @Sendable (URL) -> Bool
    private let encryption: @Sendable (URL) -> KeyEncryption

    public init(home: URL, fileExists: @escaping @Sendable (URL) -> Bool, encryption: @escaping @Sendable (URL) -> KeyEncryption) {
        self.home = home
        self.fileExists = fileExists
        self.encryption = encryption
    }

    private static func plainNames(of entry: HostEntry) -> [String] {
        entry.patterns.filter { !$0.hasPrefix("!") && !$0.contains("*") && !$0.contains("?") }
    }

    /// Non-pattern names (ASCII-lowercased) that appear in more than one Host block.
    public static func duplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in document.hosts + included.map(\.entry) {
            for name in Set(plainNames(of: entry).map(\.asciiLowercased)) { counts[name, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }
    }

    /// For each ASCII-lowercased non-wildcard name, the `headerLine` of the first root-file block naming it.
    public static func firstBlocks(document: ConfigDocument) -> [String: Int] {
        var first: [String: Int] = [:]
        for entry in document.hosts {
            for name in plainNames(of: entry).map(\.asciiLowercased) where first[name] == nil {
                first[name] = entry.headerLine
            }
        }
        return first
    }

    /// `entry` must be a root-file block; `firstBlocks` comes from `firstBlocks(document:)`.
    public func issues(for entry: HostEntry, duplicates: [String: Int], firstBlocks: [String: Int]) -> [HostIssue] {
        var result: [HostIssue] = []
        var seen: Set<String> = []
        for name in Self.plainNames(of: entry) {
            let key = name.asciiLowercased
            guard duplicates[key] != nil, seen.insert(key).inserted else { continue }
            result.append(.duplicateAlias(alias: name, isFirst: firstBlocks[key] == entry.headerLine))
        }
        for value in entry.values(for: "IdentityFile") {
            if value.asciiLowercased == "none" { continue }
            guard let url = KeyUsage.resolve(value, home: home) else { continue }
            if !fileExists(url) {
                result.append(.missingIdentityFile(value))
            } else if encryption(url) == .unencrypted {
                result.append(.unencryptedKey(value))
            }
        }
        return result
    }
}
