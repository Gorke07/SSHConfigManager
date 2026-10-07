import Foundation
import Observation
import SSHConfigKit

@MainActor
@Observable
final class AppModel {
    typealias StoreFactory = @MainActor (URL, BackupManager) -> ConfigStore

    enum SwitchResult: Equatable { case switched, needsConfirmation, unchanged }

    let settings: AppSettings
    private(set) var store: ConfigStore
    private(set) var backupManager: BackupManager
    var selection: SidebarItem?
    /// Changes when the user picks another row (or the document is reloaded); the editor view
    /// is keyed by it so renaming a host in place does not rebuild the form.
    private(set) var editorToken = UUID()
    var searchText = ""
    var errorMessage: String?

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
    }

    /// Called by the editor after it renamed the selected host.
    func followRename(to item: SidebarItem) {
        selection = item
    }

    func resetEditor() {
        editorToken = UUID()
    }

    func switchConfig(to path: String, discardingUnsavedChanges: Bool = false) -> SwitchResult {
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
