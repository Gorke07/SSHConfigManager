import Foundation
import Observation
import SSHConfigKit

enum BackupFileKind: CaseIterable {
    case config, knownHosts
}

@MainActor
@Observable
final class BackupsModel {
    let model: AppModel
    private(set) var backups: [Backup] = []
    var selectedURL: URL?
    private(set) var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        refresh()
    }

    var fileKind: BackupFileKind = .config {
        didSet { if oldValue != fileKind { selectedURL = nil; refresh() } }
    }

    private var backupKind: String {
        switch fileKind {
        case .config: model.store.backupKind
        case .knownHosts: model.knownHosts.backupKind
        }
    }

    private var currentText: String {
        switch fileKind {
        case .config: model.store.document.render()
        case .knownHosts: model.knownHosts.document.render()
        }
    }

    var selected: Backup? { backups.first { $0.url == selectedURL } }

    /// The backup kind the current list was built for.
    @ObservationIgnored private var listedKind: String?

    func refresh() {
        listedKind = backupKind
        do {
            backups = try model.backupManager.list(kind: backupKind)
            errorMessage = nil
        } catch {
            backups = []
            errorMessage = Messages.text(for: error)
        }
        if let selectedURL, !backups.contains(where: { $0.url == selectedURL }) { self.selectedURL = nil }
    }

    /// Current document (old) → backup (new): what restoring would change.
    func hunks(for backup: Backup) -> [DiffHunk] {
        let contents = (try? model.backupManager.contents(of: backup)) ?? ""
        return LineDiff.hunks(old: currentText, new: contents)
    }

    /// The known_hosts file as the user saw it when a restore confirmation opened.
    struct KnownHostsSnapshot {
        let revision: Int
        weak var store: KnownHostsStore?
    }

    func knownHostsSnapshot() -> KnownHostsSnapshot {
        KnownHostsSnapshot(revision: model.knownHosts.revision, store: model.knownHosts)
    }

    /// Config: loads the backup into the editor (the Save flow writes it).
    /// known_hosts: no drafts, so it is written now (the current file is backed up first). `seen` is
    /// the file the confirmation was shown for: a reload or a switched file since then refuses.
    func restore(_ backup: Backup, seen: KnownHostsSnapshot? = nil) throws {
        let contents = try model.backupManager.contents(of: backup)
        switch fileKind {
        case .config:
            try model.store.apply { $0 = ConfigDocument(parsing: contents) }
            model.resetEditor()
        case .knownHosts:
            // Switched file (the backup belongs to another file), a backup no longer listed, or a reload
            // since the confirmation opened (the user approved another diff): nothing is written.
            guard listedKind == model.knownHosts.backupKind, backups.contains(where: { $0.url == backup.url }),
                  let seen, let store = seen.store,
                  store === model.knownHosts, seen.revision == store.revision else {
                refresh()
                throw KnownHostsStoreError.staleSelection
            }
            try model.knownHosts.restore(text: contents)
            refresh()
        }
    }
}
