import Foundation
import SSHConfigKit

enum EffectiveSettingSource: Equatable {
    case thisBlock
    case otherHost([String])
    case global
    case include(file: String, patterns: [String])
    case defaultValue
    case uncertain
}

struct EffectiveSettingRow: Identifiable, Equatable {
    let key: String
    let values: [String]
    let source: EffectiveSettingSource
    var id: String { key }
}

/// Spec v1.1 §5: values from ssh -G (what ssh will use), sources from the resolver.
enum EffectiveSettingsBuilder {
    static let primaryKeys = [
        "hostname", "user", "port", "identityfile", "proxyjump", "proxycommand", "forwardagent", "identitiesonly",
        "localforward", "remoteforward", "dynamicforward", "serveraliveinterval", "stricthostkeychecking",
        "userknownhostsfile", "controlmaster", "controlpath",
    ]

    static func rows(alias: String, options: EffectiveOptions, resolved: ResolvedConfig, home: URL, showAll: Bool) -> [EffectiveSettingRow] {
        var keys = primaryKeys.filter { options.values[$0] != nil }
        if showAll {
            keys += options.values.keys.filter { !primaryKeys.contains($0) }.sorted()
        }
        return keys.map { key in
            let values = options.values[key] ?? []
            return EffectiveSettingRow(key: key, values: values, source: source(key: key, sshValues: values, resolved: resolved, home: home))
        }
    }

    private static func normalize(_ value: String, key: String, home: URL) -> String {
        var text = value
        if key == "identityfile" || key == "certificatefile" || key == "userknownhostsfile" {
            if text.hasPrefix("~/") { text = home.path + text.dropFirst(1) }
            text = URL(filePath: text).standardizedFileURL.path
        }
        // ssh -G lowercases some values (host names, yes/no): compare ASCII case-insensitively.
        return EffectiveConfigCache.key(text)
    }

    private static func source(key: String, sshValues: [String], resolved: ResolvedConfig, home: URL) -> EffectiveSettingSource {
        guard let first = resolved.options[key]?.first else {
            return resolved.hasMatchBlocks ? .uncertain : .defaultValue
        }
        let sshFirst = sshValues.first.map { normalize($0, key: key, home: home) }
        guard sshFirst == normalize(first.value, key: key, home: home) else { return .uncertain }
        switch first.source {
        case .thisBlock: return .thisBlock
        case .otherHost(let patterns): return .otherHost(patterns)
        case .global: return .global
        case .include(let file, let patterns): return .include(file: file.lastPathComponent, patterns: patterns)
        }
    }
}
