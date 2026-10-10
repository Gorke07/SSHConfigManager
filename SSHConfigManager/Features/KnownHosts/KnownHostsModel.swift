import Foundation
import Observation
import SSHConfigKit

/// One table row: an entry or an unparsable line of the known_hosts file.
struct KnownHostRow: Identifiable, Equatable {
    /// Line index in the document it was built from.
    let id: Int
    /// Plain names, plus a "hashed" marker when some names are hashed.
    let hosts: String
    /// Plain names only (what a text search looks through).
    let plainHosts: String
    /// Names as written (`host`, `[host]:2222`), for the delete confirmation.
    let literalNames: String
    let ports: String
    let keyType: String
    let fingerprint: String
    let marker: String
    let comment: String
    /// Every name is hashed (no plain name to show or search).
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
                KnownHostRow(id: index, hosts: KnownHostsDocument.content(of: line.raw), plainHosts: "", literalNames: KnownHostsDocument.content(of: line.raw), ports: "", keyType: "",
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
            // Mixed lines are searched by their plain names; fully hashed ones only by the lookup form.
            if row.isHashed { return false }
            return [row.plainHosts, row.keyType, row.fingerprint, row.comment, row.marker]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    /// Only rows that are both selected and visible: a row hidden by the search is never deleted.
    var visibleSelectedRows: [KnownHostRow] {
        let selected = selection
        return rows.filter { selected.contains($0.id) }
    }

    /// Delete is possible: the file is loaded and a selected row is visible.
    var canRemoveSelection: Bool {
        app.knownHosts.loadState == .loaded && !visibleSelectedRows.isEmpty
    }

    func requestRemoveSelection() {
        guard app.knownHosts.loadState == .loaded else { return }
        let chosen = visibleSelectedRows
        guard !chosen.isEmpty else { return }
        pendingRevision = selectionRevision
        pendingStore = app.knownHosts
        pendingRemoval = chosen
    }

    /// The confirmation's list: each entry's names as written (port included), key type and a short
    /// fingerprint, one per line, so two hashed or same-host lines can be told apart.
    static func summary(of rows: [KnownHostRow]) -> String {
        let limit = 15
        var lines = rows.prefix(limit).map { row -> String in
            var parts = [row.isUnparsable ? row.hosts : row.literalNames]
            if !row.keyType.isEmpty { parts.append(row.keyType) }
            if !row.fingerprint.isEmpty { parts.append(String(row.fingerprint.prefix(19)) + "…") }
            return parts.joined(separator: "  ")
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

    static func row(for entry: KnownHostEntry) -> KnownHostRow {
        var plain: [String] = []
        var literals: [String] = []
        var ports: [Int] = []
        var hashedCount = 0
        for name in entry.names {
            switch name {
            case .plain(let address):
                plain.append(address.host)
                literals.append(address.literal)
                if !ports.contains(address.port) { ports.append(address.port) }
            case .hashed:
                hashedCount += 1
            }
        }
        let hashedLabel = String(localized: "knownHosts.hashed")
        let allHashed = plain.isEmpty && hashedCount > 0
        let shown: String
        if allHashed {
            shown = hashedLabel
        } else if hashedCount > 0 {
            shown = plain.joined(separator: ", ") + " " + String(localized: "knownHosts.hashedMore")
        } else {
            shown = plain.joined(separator: ", ")
        }
        let literalNames = hashedCount > 0 ? (literals + [hashedLabel]).joined(separator: ", ") : literals.joined(separator: ", ")
        return KnownHostRow(
            id: entry.lineIndex,
            hosts: shown,
            plainHosts: plain.joined(separator: ", "),
            literalNames: literalNames,
            ports: ports.sorted().map(String.init).joined(separator: ", "),
            keyType: entry.keyType,
            fingerprint: Fingerprint.sha256(base64Key: entry.keyBase64) ?? "",
            marker: entry.marker?.rawValue ?? "",
            comment: entry.comment ?? "",
            isHashed: allHashed,
            isUnparsable: false,
            names: entry.names)
    }
}
