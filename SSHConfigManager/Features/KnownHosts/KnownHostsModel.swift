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
    /// Hashed names, for host-like queries.
    let hashedNames: [KnownHostName]
}

@MainActor
@Observable
final class KnownHostsModel {
    let app: AppModel
    var searchText = ""
    var selection: Set<Int> = []
    var errorMessage: String?
    /// Rows waiting for the user to confirm deletion, and the store revision they belong to.
    private(set) var pendingRemoval: [KnownHostRow]?
    @ObservationIgnored private var pendingRevision = 0

    init(app: AppModel) {
        self.app = app
    }

    var allRows: [KnownHostRow] {
        let document = app.knownHosts.document
        return document.lines.enumerated().compactMap { index, line in
            switch line.kind {
            case .entry(let entry): Self.row(for: entry)
            case .unparsable:
                KnownHostRow(id: index, hosts: KnownHostsDocument.content(of: line.raw), ports: "", keyType: "",
                             fingerprint: "", marker: "", comment: "", isHashed: false, isUnparsable: true, hashedNames: [])
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
            if row.isHashed {
                guard let lookup else { return false }
                return row.hashedNames.contains { HostMatcher.matches($0, lookupName: lookup) }
            }
            return [row.hosts, row.keyType, row.fingerprint, row.comment, row.marker]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    func requestRemoveSelection() {
        let chosen = allRows.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        pendingRevision = app.knownHosts.revision
        pendingRemoval = chosen
    }

    func confirmRemoval() {
        guard let rows = pendingRemoval else { return }
        pendingRemoval = nil
        do {
            try app.knownHosts.remove(lines: Set(rows.map(\.id)), ifRevision: pendingRevision)
            errorMessage = nil
        } catch {
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
        var hashed: [KnownHostName] = []
        for name in entry.names {
            switch name {
            case .plain(let address):
                hosts.append(address.host)
                if !ports.contains(address.port) { ports.append(address.port) }
            case .hashed:
                hashed.append(name)
            }
        }
        let isHashed = !hashed.isEmpty
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
            hashedNames: hashed)
    }
}
