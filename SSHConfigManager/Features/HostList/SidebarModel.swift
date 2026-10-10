import Foundation
import SSHConfigKit

/// Stable identity of a sidebar row. Hosts are identified by alias + occurrence, not by line
/// number, so edits above a host do not change which row is selected.
enum SidebarItem: Hashable, Sendable {
    case host(alias: String, occurrence: Int)
    case included(id: String)
    case match(index: Int)
}

struct SidebarRow: Identifiable, Hashable, Sendable {
    let item: SidebarItem
    let title: String
    let subtitle: String
    var id: SidebarItem { item }
}

struct SidebarGroup: Equatable, Identifiable, Sendable {
    /// nil for hosts without a `# group:` line.
    let name: String?
    var rows: [SidebarRow]
    var id: String { name ?? "\u{0}ungrouped" }
}

struct SidebarSections: Equatable, Sendable {
    /// Named groups sorted by name, then the unnamed group; empty groups are omitted.
    var hostGroups: [SidebarGroup] = []
    var patterns: [SidebarRow] = []
    var included: [SidebarRow] = []
    var matches: [SidebarRow] = []
    var hosts: [SidebarRow] { hostGroups.flatMap(\.rows) }
}

enum SidebarBuilder {
    static func sections(document: ConfigDocument, included: [IncludedHost], search: String) -> SidebarSections {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = SidebarSections()

        var seen: [String: Int] = [:]
        var grouped: [String: [SidebarRow]] = [:]
        var ungrouped: [SidebarRow] = []
        for entry in document.hosts {
            let occurrence = seen[entry.alias, default: 0]
            seen[entry.alias] = occurrence + 1
            guard matches(entry, query: query) else { continue }
            let row = SidebarRow(
                item: .host(alias: entry.alias, occurrence: occurrence),
                title: entry.patterns.joined(separator: " "),
                subtitle: subtitle(for: entry))
            if entry.isPattern {
                result.patterns.append(row)
            } else {
                if let group = document.group(ofHostAt: entry.headerLine) {
                    grouped[group, default: []].append(row)
                } else {
                    ungrouped.append(row)
                }
            }
        }
        result.hostGroups = grouped.keys.sorted(by: groupNameOrder)
            .map { SidebarGroup(name: $0, rows: grouped[$0] ?? []) }
        if !ungrouped.isEmpty { result.hostGroups.append(SidebarGroup(name: nil, rows: ungrouped)) }

        for host in included where matches(host.entry, query: query) {
            result.included.append(SidebarRow(
                item: .included(id: host.id),
                title: host.entry.patterns.joined(separator: " "),
                subtitle: host.file.lastPathComponent))
        }

        for (index, match) in document.matches.enumerated()
        where query.isEmpty || match.criteria.localizedStandardContains(query) {
            // "Match" is an ssh keyword and is not translated.
            result.matches.append(SidebarRow(item: .match(index: index), title: "Match " + match.criteria, subtitle: ""))
        }
        return result
    }

    /// Natural order; names that compare equal (case-only variants) fall back to `<` so the order is stable.
    static func groupNameOrder(_ a: String, _ b: String) -> Bool {
        switch a.localizedStandardCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: a < b
        }
    }

    static func subtitle(for entry: HostEntry) -> String {
        let host = entry.value(for: "HostName") ?? ""
        if let user = entry.value(for: "User"), !user.isEmpty, !host.isEmpty { return "\(user)@\(host)" }
        return host
    }

    static func hostEntry(for item: SidebarItem, in document: ConfigDocument) -> HostEntry? {
        guard case .host(let alias, let occurrence) = item else { return nil }
        let candidates = document.hosts.filter { $0.alias == alias }
        return candidates.indices.contains(occurrence) ? candidates[occurrence] : nil
    }

    static func item(forHeader header: Int, in document: ConfigDocument) -> SidebarItem? {
        guard let entry = document.hostEntry(at: header) else { return nil }
        let occurrence = document.hosts.filter { $0.alias == entry.alias && $0.headerLine < header }.count
        return .host(alias: entry.alias, occurrence: occurrence)
    }

    static func includedHost(for item: SidebarItem, in included: [IncludedHost]) -> IncludedHost? {
        guard case .included(let id) = item else { return nil }
        return included.first { $0.id == id }
    }

    static func matchEntry(for item: SidebarItem, in document: ConfigDocument) -> MatchEntry? {
        guard case .match(let index) = item else { return nil }
        let matches = document.matches
        return matches.indices.contains(index) ? matches[index] : nil
    }

    private static func matches(_ entry: HostEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = entry.patterns + [entry.value(for: "HostName"), entry.value(for: "User")].compactMap { $0 }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
