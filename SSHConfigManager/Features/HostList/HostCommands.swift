import Foundation
import SSHConfigKit

@MainActor
enum HostCommands {
    /// `base`, or `base-2`, `base-3` … — compared case-insensitively like ssh does.
    static func uniqueAlias(_ base: String, in document: ConfigDocument) -> String {
        let taken = Set(document.hosts.flatMap(\.patterns).map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)".lowercased()) { counter += 1 }
        return "\(base)-\(counter)"
    }

    static func addHost(to store: ConfigStore) throws -> SidebarItem {
        var header = 0
        let alias = uniqueAlias("new-host", in: store.document)
        try store.apply { header = try $0.addHost(HostDraft(patterns: [alias])) }
        return SidebarBuilder.item(forHeader: header, in: store.document) ?? .host(alias: alias, occurrence: 0)
    }

    static func duplicate(_ item: SidebarItem, in store: ConfigStore) throws -> SidebarItem? {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return nil }
        let alias = uniqueAlias(entry.alias + "-copy", in: store.document)
        var header = 0
        try store.apply { header = try $0.duplicateHost(at: entry.headerLine, newAlias: alias) }
        return SidebarBuilder.item(forHeader: header, in: store.document)
    }

    static func delete(_ item: SidebarItem, in store: ConfigStore) throws {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return }
        try store.apply { try $0.removeHost(at: entry.headerLine) }
    }

    static func sshCommand(for item: SidebarItem, document: ConfigDocument, builder: SSHCommandBuilder) -> String? {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: document), !entry.isPattern else { return nil }
        return builder.shellCommand(alias: entry.alias)
    }
}
