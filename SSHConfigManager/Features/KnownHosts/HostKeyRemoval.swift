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
        do {
            let host = try await resolver.resolve(alias: alias)
            revision = knownHosts.revision
            let entries = HostMatcher.entries(in: knownHosts.document, matchingAny: host.lookupNames)
            phase = entries.isEmpty ? .nothingFound(host.lookupNames) : .confirm(entries)
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
    }

    func confirmHostKeyRemoval() {
        guard let removal = hostKeyRemoval, case .confirm(let entries) = removal.phase else { return }
        hostKeyRemoval = nil
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
