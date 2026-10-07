import Foundation
import Observation
import SSHConfigKit

@MainActor
@Observable
final class AppModel {
    typealias StoreFactory = @MainActor (URL, BackupManager) -> ConfigStore

    enum SwitchResult: Equatable { case switched, needsConfirmation, unchanged, invalid }

    let settings: AppSettings
    private(set) var store: ConfigStore
    private(set) var backupManager: BackupManager
    var selection: SidebarItem?
    /// Changes when the user picks another row (or the document is reloaded); the editor view
    /// is keyed by it so renaming a host in place does not rebuild the form.
    private(set) var editorToken = UUID()
    var searchText = ""
    var errorMessage: String?
    /// The form for the current selection. Owned here (not by the view) so edits that validation
    /// blocked survive closing the window; dropped when the selection or document is reset.
    @ObservationIgnored private(set) var activeEditor: HostEditorModel?
    @ObservationIgnored private var activeEditorToken: UUID?
    /// A selection waiting for the user to confirm discarding blocked form edits.
    var pendingSelection: SidebarItem?

    @ObservationIgnored private let makeStore: StoreFactory

    init(settings: AppSettings, backupRoot: URL = BackupManager.defaultRoot, makeStore: @escaping StoreFactory = AppModel.liveStore) {
        self.settings = settings
        let backups = BackupManager(rootDirectory: backupRoot, keep: settings.backupCount)
        self.backupManager = backups
        self.makeStore = makeStore
        self.store = makeStore(settings.configURL, backups)
    }

    static func liveStore(url: URL, backups: BackupManager) -> ConfigStore {
        ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups))
    }

    var commandBuilder: SSHCommandBuilder {
        SSHCommandBuilder(configFile: store.fileURL, homeDirectory: settings.homeDirectory)
    }

    func select(_ item: SidebarItem?) {
        selection = item
        editorToken = UUID()
        activeEditor = nil
        activeEditorToken = nil
    }

    /// The editor for the selected host: the existing one while the token is unchanged, else a new one.
    func editor(for item: SidebarItem) -> HostEditorModel? {
        if let activeEditor, activeEditorToken == editorToken, activeEditor.item == item {
            return activeEditor
        }
        let created = HostEditorModel(item: item, store: store, homeDirectory: settings.homeDirectory)
        created?.onItemChange = { [weak self] in self?.followRename(to: $0) }
        activeEditor = created
        activeEditorToken = created == nil ? nil : editorToken
        return created
    }

    var hasPendingFormEdits: Bool { activeEditor?.hasPendingChanges ?? false }

    /// Selects `item`, unless the form holds edits that were never applied; then asks first.
    func requestSelect(_ item: SidebarItem?) {
        if hasPendingFormEdits, item != nil {
            pendingSelection = item
        } else {
            select(item)
        }
    }

    func confirmPendingSelection() {
        let item = pendingSelection
        pendingSelection = nil
        select(item)
    }

    func cancelPendingSelection() {
        pendingSelection = nil
    }

    /// Called by the editor after it renamed the selected host.
    func followRename(to item: SidebarItem) {
        selection = item
    }

    func resetEditor() {
        editorToken = UUID()
        activeEditor = nil
        activeEditorToken = nil
    }

    func switchConfig(to path: String, discardingUnsavedChanges: Bool = false) -> SwitchResult {
        guard AppSettings.isValidConfigPath(path) else { return .invalid }
        let url = AppSettings.expand(path, home: settings.homeDirectory)
        if url.standardizedFileURL == store.fileURL.standardizedFileURL {
            settings.setConfigPath(path)
            return .unchanged
        }
        if store.hasUnsavedChanges && !discardingUnsavedChanges { return .needsConfirmation }
        settings.setConfigPath(path)
        store = makeStore(url, backupManager)
        select(nil)
        return .switched
    }

    func setBackupCount(_ count: Int) {
        settings.setBackupCount(count)
        backupManager.keep = settings.backupCount
        store.setBackupKeep(settings.backupCount)
    }
}
