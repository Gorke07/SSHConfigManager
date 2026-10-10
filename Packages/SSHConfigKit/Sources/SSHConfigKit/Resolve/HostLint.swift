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

    /// Non-pattern aliases (ASCII-lowercased) that appear in more than one Host block.
    public static func duplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in document.hosts + included.map(\.entry) {
            let names = Set(entry.patterns.filter { !$0.hasPrefix("!") && !$0.contains("*") && !$0.contains("?") }.map(\.asciiLowercased))
            for name in names { counts[name, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }
    }

    public func issues(for entry: HostEntry, duplicates: [String: Int], isFirstOccurrence: Bool = true) -> [HostIssue] {
        var result: [HostIssue] = []
        if !entry.isPattern, duplicates[entry.alias.asciiLowercased] != nil {
            result.append(.duplicateAlias(alias: entry.alias, isFirst: isFirstOccurrence))
        }
        for value in entry.values(for: "IdentityFile") {
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
