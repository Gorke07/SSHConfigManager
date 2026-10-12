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
    /// Why the list could not be read.
    private(set) var errorMessage: String?
    /// Why the last restore failed (shown in the Backups window, not the main window).
    var restoreFailure: String?

    /// A list error the user already dismissed; the same error is not shown again on every refresh.
    @ObservationIgnored private var dismissedListError: String?

    /// What the Backups window's alert shows (a restore failure, else a list error not yet dismissed).
    var alertMessage: String? {
        get { restoreFailure ?? (errorMessage == dismissedListError ? nil : errorMessage) }
        set { if newValue == nil { restoreFailure = nil; dismissedListError = errorMessage } }
    }

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
        hunksCache = nil
        listedKind = backupKind
        do {
            backups = try model.backupManager.list(kind: backupKind)
            errorMessage = nil
            dismissedListError = nil
        } catch {
            backups = []
            AppLog.error(.backups, error)
            errorMessage = Messages.text(for: error)
        }
        if let selectedURL, !backups.contains(where: { $0.url == selectedURL }) { self.selectedURL = nil }
    }

    /// Current document (old) → backup (new): what restoring would change.
    /// Cached per backup and current text, so a body pass does not re-read the file and re-diff.
    func hunks(for backup: Backup) -> [DiffHunk] {
        let current = currentText
        if let cached = hunksCache, cached.url == backup.url, cached.current == current { return cached.hunks }
        let read = try? model.backupManager.contents(of: backup)
        let hunks = LineDiff.hunks(old: current, new: read ?? "")
        hunksComputationCount += 1
        // A failed read is not cached: the next pass tries the file again.
        if read != nil { hunksCache = (backup.url, current, hunks) }
        return hunks
    }

    @ObservationIgnored private var hunksCache: (url: URL, current: String, hunks: [DiffHunk])?
    /// How many times a diff was actually computed (tests).
    @ObservationIgnored private(set) var hunksComputationCount = 0

    /// The known_hosts file as the user saw it when a restore confirmation opened.
    struct KnownHostsSnapshot {
        let revision: Int
        weak var store: KnownHostsStore?
    }

    func knownHostsSnapshot() -> KnownHostsSnapshot {
        KnownHostsSnapshot(revision: model.knownHosts.revision, store: model.knownHosts)
    }

    /// Restores and records a failure for the Backups window's alert.
    func performRestore(_ backup: Backup, seen: KnownHostsSnapshot? = nil) {
        do { try restore(backup, seen: seen) } catch {
            AppLog.error(.backups, error)
            restoreFailure = Messages.text(for: error)
        }
    }

    /// Config: loads the backup into the editor (the Save flow writes it). When the config file is missing it is created first (empty), then the backup is loaded.
    /// known_hosts: no drafts, so it is written now (the current file is backed up first). `seen` is
    /// the file the confirmation was shown for: a reload or a switched file since then refuses.
    func restore(_ backup: Backup, seen: KnownHostsSnapshot? = nil) throws {
        let contents = try model.backupManager.contents(of: backup)
        switch fileKind {
        case .config:
            // A missing config file is created first (empty); if the restore then fails, the empty file is removed again.
            let created = model.store.loadState == .missing
            if created { try model.store.createFile() }
            do {
                try model.store.apply { $0 = ConfigDocument(parsing: contents) }
            } catch {
                if created, (try? Data(contentsOf: model.store.fileURL))?.isEmpty == true {
                    try? FileManager.default.removeItem(at: model.store.fileURL)
                    model.store.discardChanges()
                }
                throw error
            }
            // The user agreed to discard the form, so an unapplied group name goes too.
            model.groupDraft = nil
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
