import Foundation
import Observation
import SSHConfigKit

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

    var selected: Backup? { backups.first { $0.url == selectedURL } }

    func refresh() {
        do {
            backups = try model.backupManager.list(kind: model.store.backupKind)
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
        return LineDiff.hunks(old: model.store.document.render(), new: contents)
    }

    /// Loads the backup into the editor; the normal Save flow (diff, ssh -G, backup) writes it.
    func restore(_ backup: Backup) throws {
        let contents = try model.backupManager.contents(of: backup)
        try model.store.apply { $0 = ConfigDocument(parsing: contents) }
        model.resetEditor()
    }
}
