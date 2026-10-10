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
    /// The store the entries were read from; a switched known_hosts file is a different store
    /// (compared by identity, never by address: a freed store's address can be reused).
    weak var store: KnownHostsStore?
    /// ssh -G reported `checkhostip yes`: the host's IP entries are not part of this lookup.
    var checkHostIP = false
    /// ssh's first UserKnownHostsFile when none of them is the file this app manages.
    var otherKnownHostsFile: String?

    /// Secondary notes shown in the sheet.
    var notes: [String] {
        var notes: [String] = []
        if checkHostIP { notes.append(String(localized: "hostKeyRemoval.checkHostIPNote")) }
        if let file = otherKnownHostsFile { notes.append(String(localized: "hostKeyRemoval.otherFileNote \(file)")) }
        return notes
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.alias == rhs.alias && lhs.phase == rhs.phase && lhs.revision == rhs.revision
            && lhs.store === rhs.store && lhs.checkHostIP == rhs.checkHostIP && lhs.otherKnownHostsFile == rhs.otherKnownHostsFile
    }
}

extension AppModel {
    /// Starts the flow in a task the model owns, so `cancelHostKeyRemoval` can stop `ssh -G`.
    func startHostKeyRemoval(alias: String) {
        hostKeyRemovalTask?.cancel()
        hostKeyRemovalTask = Task { await requestHostKeyRemoval(alias: alias) }
    }

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
        var store: KnownHostsStore?
        var checkHostIP = false
        var otherFile: String?
        do {
            let host = try await resolver.resolve(alias: alias)
            revision = knownHosts.revision
            store = knownHosts
            checkHostIP = host.checkHostIP
            otherFile = otherKnownHostsFile(sshReads: host.userKnownHostsFiles, candidates: host.userKnownHostsFileCandidates)
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
            AppLog.error(.knownHosts, error)
            phase = .failed(Messages.text(for: error))
        }
        // Cancelled or replaced while ssh -G was running: drop the late answer.
        guard hostKeyRemoval?.id == request.id else { return }
        hostKeyRemoval?.phase = phase
        hostKeyRemoval?.revision = revision
        hostKeyRemoval?.store = store
        hostKeyRemoval?.checkHostIP = checkHostIP
        hostKeyRemoval?.otherKnownHostsFile = otherFile
    }

    /// ssh's first UserKnownHostsFile when none of them is the known_hosts file this app manages; nil
    /// when one is, or when ssh printed none. `ssh -G` prints expanded, unquoted, space-joined paths, so
    /// a path with spaces arrives split: `candidates` also holds the joined runs. `~` and `%d` expand
    /// against the settings' home, and symlinks are resolved on both sides before comparing.
    func otherKnownHostsFile(sshReads files: [String], candidates: [String]? = nil) -> String? {
        guard let first = files.first else { return nil }
        let managed = knownHosts.fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let reads = (candidates ?? files).contains { path in
            expandedKnownHostsPath(path).resolvingSymlinksInPath().standardizedFileURL.path == managed
        }
        return reads ? nil : first
    }

    private func expandedKnownHostsPath(_ path: String) -> URL {
        let home = settings.homeDirectory
        let withHome = path.replacingOccurrences(of: "%d", with: home.path)
        return AppSettings.expand(withHome, home: home)
    }

    func confirmHostKeyRemoval() {
        guard let removal = hostKeyRemoval, case .confirm(let entries) = removal.phase else { return }
        hostKeyRemoval = nil
        guard let store = removal.store, store === knownHosts else {
            errorMessage = Messages.text(for: KnownHostsStoreError.staleSelection)
            return
        }
        do {
            try store.remove(lines: Set(entries.map(\.lineIndex)), ifRevision: removal.revision)
            connectionTests.dropResult(for: removal.alias)
        } catch {
            AppLog.error(.knownHosts, error)
            errorMessage = Messages.text(for: error)
        }
    }

    func cancelHostKeyRemoval() {
        hostKeyRemovalTask?.cancel()
        hostKeyRemovalTask = nil
        hostKeyRemoval = nil
    }
}
