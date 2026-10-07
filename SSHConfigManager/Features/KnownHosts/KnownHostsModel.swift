import Foundation
import Observation
import SSHConfigKit

/// One table row: an entry or an unparsable line of the known_hosts file.
struct KnownHostRow: Identifiable, Equatable {
    /// Line index in the document it was built from.
    let id: Int
    let hosts: String
    let ports: String
    let keyType: String
    let fingerprint: String
    let marker: String
    let comment: String
    let isHashed: Bool
    let isUnparsable: Bool
    /// The entry's names (plain and hashed), for host-like queries.
    let names: [KnownHostName]
}

@MainActor
@Observable
final class KnownHostsModel {
    let app: AppModel
    var searchText = ""
    var errorMessage: String?
    /// Rows waiting for the user to confirm deletion, and the store revision they belong to.
    private(set) var pendingRemoval: [KnownHostRow]?
    @ObservationIgnored private var pendingRevision = 0
    @ObservationIgnored private weak var pendingStore: KnownHostsStore?

    /// Row ids are line indices of one document: a selection is only valid in the revision of the
    /// store it was made in. After a reload or a store swap it reads as empty.
    private var storedSelection: Set<Int> = []
    private var selectionRevision = 0
    @ObservationIgnored private weak var selectionStore: KnownHostsStore?

    init(app: AppModel) {
        self.app = app
    }

    var selection: Set<Int> {
        get {
            let store = app.knownHosts
            guard selectionStore === store, selectionRevision == store.revision else { return [] }
            return storedSelection
        }
        set {
            storedSelection = newValue
            selectionRevision = app.knownHosts.revision
            selectionStore = app.knownHosts
        }
    }

    var allRows: [KnownHostRow] {
        let document = app.knownHosts.document
        return document.lines.enumerated().compactMap { index, line in
            switch line.kind {
            case .entry(let entry): Self.row(for: entry)
            case .unparsable:
                KnownHostRow(id: index, hosts: KnownHostsDocument.content(of: line.raw), ports: "", keyType: "",
                             fingerprint: "", marker: "", comment: "", isHashed: false, isUnparsable: true, names: [])
            case .blank, .comment: nil
            }
        }
    }

    var rows: [KnownHostRow] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allRows }
        let needle = query.lowercased()
        let lookup = HostMatcher.lookupName(forQuery: query)
        return allRows.filter { row in
            // ssh's own form (`host`, `[host]:port`) finds hashed and plain names alike.
            if let lookup, row.names.contains(where: { HostMatcher.matches($0, lookupName: lookup) }) { return true }
            if row.isHashed { return false }
            return [row.hosts, row.keyType, row.fingerprint, row.comment, row.marker]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    /// Only rows that are both selected and visible: a row hidden by the search is never deleted.
    func requestRemoveSelection() {
        let selected = selection
        let chosen = rows.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        pendingRevision = selectionRevision
        pendingStore = app.knownHosts
        pendingRemoval = chosen
    }

    /// The confirmation's list: each entry's hosts and key type, one per line.
    var pendingSummary: String {
        guard let rows = pendingRemoval else { return "" }
        let limit = 15
        var lines = rows.prefix(limit).map { row in
            row.keyType.isEmpty ? row.hosts : "\(row.hosts)  \(row.keyType)"
        }
        if rows.count > limit { lines.append("…") }
        return lines.joined(separator: "\n")
    }

    func confirmRemoval() {
        guard let rows = pendingRemoval else { return }
        pendingRemoval = nil
        // switchKnownHosts() builds a fresh store whose revision restarts: indices would hit another file.
        guard let store = pendingStore, store === app.knownHosts else {
            errorMessage = Messages.text(for: KnownHostsStoreError.staleSelection)
            selection = []
            return
        }
        do {
            try store.remove(lines: Set(rows.map(\.id)), ifRevision: pendingRevision)
            errorMessage = nil
        } catch {
            AppLog.error(.knownHosts, error)
            errorMessage = Messages.text(for: error)
        }
        selection = []
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    private static func row(for entry: KnownHostEntry) -> KnownHostRow {
        var hosts: [String] = []
        var ports: [Int] = []
        var isHashed = false
        for name in entry.names {
            switch name {
            case .plain(let address):
                hosts.append(address.host)
                if !ports.contains(address.port) { ports.append(address.port) }
            case .hashed:
                isHashed = true
            }
        }
        return KnownHostRow(
            id: entry.lineIndex,
            hosts: isHashed ? String(localized: "knownHosts.hashed") : hosts.joined(separator: ", "),
            ports: ports.sorted().map(String.init).joined(separator: ", "),
            keyType: entry.keyType,
            fingerprint: Fingerprint.sha256(base64Key: entry.keyBase64) ?? "",
            marker: entry.marker?.rawValue ?? "",
            comment: entry.comment ?? "",
            isHashed: isHashed,
            isUnparsable: false,
            names: entry.names)
    }
}
