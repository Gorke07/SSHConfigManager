import Foundation
import SSHConfigKit

struct HostKeyRemoval: Equatable, Identifiable {
    enum Phase: Equatable {
        case resolving
        case confirm([KnownHostEntry])
        /// The lookup names that were tried.
        case nothingFound([String])
        case failed(String)
    }

    let id = UUID()
    let alias: String
    var phase: Phase
    /// Store revision the matched entries belong to.
    var revision = 0
    /// The store the entries were read from; a switched known_hosts file is a different store.
    var store: ObjectIdentifier?
}

extension AppModel {
    /// ssh -G → real host name, port and HostKeyAlias → matching entries (hashed included, patterns
    /// and marker lines never) → confirmation.
    func requestHostKeyRemoval(alias requested: String) async {
        guard let alias = savedAlias(requested) else {
            errorMessage = String(localized: "connect.notSaved")
            return
        }
        let request = HostKeyRemoval(alias: alias, phase: .resolving)
        hostKeyRemoval = request
        let resolver = HostResolver(commandBuilder: commandBuilder, runner: processRunner)
        let phase: HostKeyRemoval.Phase
        var revision = 0
        var store: ObjectIdentifier?
        do {
            let host = try await resolver.resolve(alias: alias)
            revision = knownHosts.revision
            store = ObjectIdentifier(knownHosts)
            switch knownHosts.loadState {
            case .notUTF8, .unreadable:
                // An unreadable file has an empty document: "nothing found" would be a lie.
                phase = .failed(Messages.knownHostsLoadText(for: knownHosts.loadState) ?? "")
            case .loaded, .missing:
                let entries = HostMatcher.entries(in: knownHosts.document, matchingAny: host.lookupNames)
                phase = entries.isEmpty ? .nothingFound(host.lookupNames) : .confirm(entries)
            }
        } catch is CancellationError {
            if hostKeyRemoval?.id == request.id { hostKeyRemoval = nil }
            return
        } catch {
            phase = .failed(Messages.text(for: error))
        }
        // Cancelled or replaced while ssh -G was running: drop the late answer.
        guard hostKeyRemoval?.id == request.id else { return }
        hostKeyRemoval?.phase = phase
        hostKeyRemoval?.revision = revision
        hostKeyRemoval?.store = store
    }

    func confirmHostKeyRemoval() {
        guard let removal = hostKeyRemoval, case .confirm(let entries) = removal.phase else { return }
        hostKeyRemoval = nil
        guard removal.store == ObjectIdentifier(knownHosts) else {
            errorMessage = Messages.text(for: KnownHostsStoreError.staleSelection)
            return
        }
        do {
            try knownHosts.remove(lines: Set(entries.map(\.lineIndex)), ifRevision: removal.revision)
            connectionTests.dropResult(for: removal.alias)
        } catch {
            errorMessage = Messages.text(for: error)
        }
    }

    func cancelHostKeyRemoval() {
        hostKeyRemoval = nil
    }
}
