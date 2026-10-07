import CryptoKit
import Foundation
import Observation
import SSHConfigKit

@MainActor
@Observable
final class AppModel {
    typealias StoreFactory = @MainActor (URL, BackupManager, String) -> ConfigStore

    typealias KnownHostsStoreFactory = @MainActor (URL, BackupManager, String) -> KnownHostsStore

    enum SwitchResult: Equatable { case switched, needsConfirmation, unchanged, invalid }

    let settings: AppSettings
    private(set) var store: ConfigStore
    private(set) var knownHosts: KnownHostsStore
    private(set) var backupManager: BackupManager
    var selection: SidebarItem?
    /// Changes when the user picks another row (or the document is reloaded); the editor view
    /// is keyed by it so renaming a host in place does not rebuild the form.
    private(set) var editorToken = UUID()
    var searchText = ""
    var errorMessage: String?
    /// The "Delete known_hosts entry…" flow for one alias; drives `HostKeyRemovalSheet`.
    var hostKeyRemoval: HostKeyRemoval?
    /// Informational: the chosen terminal was unavailable and the connection opened in Terminal.
    var fallbackNotice: String?
    /// The form for the current selection. Owned here (not by the view) so edits that validation
    /// blocked survive closing the window; dropped when the selection or document is reset.
    @ObservationIgnored private(set) var activeEditor: HostEditorModel?
    @ObservationIgnored private var activeEditorToken: UUID?
    /// A selection waiting for the user to confirm discarding blocked form edits.
    var pendingSelection: SidebarItem?

    @ObservationIgnored private let makeStore: StoreFactory
    @ObservationIgnored private let makeKnownHostsStore: KnownHostsStoreFactory
    @ObservationIgnored let processRunner: any ProcessRunning
    @ObservationIgnored private let launcherFactory: @MainActor (TerminalChoice) -> any TerminalLaunching
    @ObservationIgnored private let terminalInstalled: @MainActor (TerminalChoice) -> Bool
    /// Set when macOS denied Automation access; the main window explains how to allow it.
    var automationDenied = false
    /// Session-only connection test results; cleared when the saved file changes or another one is opened.
    let connectionTests: ConnectionTestsModel
    let keys: KeysModel

    init(settings: AppSettings,
         backupRoot: URL = BackupManager.defaultRoot,
         processRunner: any ProcessRunning = ProcessRunner(),
         launcherFactory: @escaping @MainActor (TerminalChoice) -> any TerminalLaunching = LiveTerminals.launcher(for:),
         isTerminalInstalled: @escaping @MainActor (TerminalChoice) -> Bool = LiveTerminals.isInstalled,
         keyTools: KeyTools = .live,
         makeStore: @escaping StoreFactory = AppModel.liveStore,
         makeKnownHostsStore: @escaping KnownHostsStoreFactory = AppModel.liveKnownHostsStore) {
        self.settings = settings
        self.processRunner = processRunner
        self.connectionTests = ConnectionTestsModel(runner: processRunner)
        self.launcherFactory = launcherFactory
        self.terminalInstalled = isTerminalInstalled
        self.keys = KeysModel(tools: keyTools)
        let backups = BackupManager(rootDirectory: backupRoot, keep: settings.backupCount)
        self.backupManager = backups
        self.makeStore = makeStore
        self.store = makeStore(settings.configURL, backups, Self.backupKind(for: settings.configURL, home: settings.homeDirectory))
        self.makeKnownHostsStore = makeKnownHostsStore
        self.knownHosts = makeKnownHostsStore(
            settings.knownHostsURL, backups, Self.knownHostsBackupKind(for: settings.knownHostsURL, home: settings.homeDirectory))
        keys.app = self
        observeSavedState()
    }

    /// The saved file changed (save, reload, external change): results measured against the old
    /// file are stale and the connectable hosts must be rebuilt.
    private func observeSavedState() {
        store.onDiskStateChange = { [weak self] in self?.savedStateDidChange() }
    }

    private func savedStateDidChange() {
        savedHostsCache = nil
        connectionTests.clear()
    }

    static func liveStore(url: URL, backups: BackupManager, backupKind: String) -> ConfigStore {
        ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups), backupKind: backupKind)
    }

    static func liveKnownHostsStore(url: URL, backups: BackupManager, backupKind: String) -> KnownHostsStore {
        KnownHostsStore(fileURL: url, writer: SafeFileWriter(backups: backups), backupKind: backupKind)
    }

    /// "config" for ~/.ssh/config; otherwise a stable per-path kind so backups of different files never mix.
    static func backupKind(for url: URL, home: URL) -> String {
        backupKind(for: url, defaultPath: home.appending(path: ".ssh/config"), prefix: "config")
    }

    /// "known_hosts" for ~/.ssh/known_hosts; otherwise a stable per-path kind.
    static func knownHostsBackupKind(for url: URL, home: URL) -> String {
        backupKind(for: url, defaultPath: home.appending(path: ".ssh/known_hosts"), prefix: "known_hosts")
    }

    private static func backupKind(for url: URL, defaultPath: URL, prefix: String) -> String {
        let path = url.standardizedFileURL.path
        if path == defaultPath.standardizedFileURL.path { return prefix }
        let digest = SHA256.hash(data: Data(path.utf8))
        return prefix + "-" + digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    }

    /// Opens another known_hosts file. There are no drafts, so nothing needs confirming.
    @discardableResult
    func switchKnownHosts(to path: String) -> Bool {
        guard AppSettings.isValidConfigPath(path) else { return false }
        settings.setKnownHostsPath(path)
        let url = settings.knownHostsURL
        knownHosts = makeKnownHostsStore(url, backupManager, Self.knownHostsBackupKind(for: url, home: settings.homeDirectory))
        return true
    }

    var commandBuilder: SSHCommandBuilder {
        SSHCommandBuilder(configFile: store.fileURL, homeDirectory: settings.homeDirectory)
    }

    func isTerminalInstalled(_ choice: TerminalChoice) -> Bool { terminalInstalled(choice) }

    /// One connectable host of the saved file (or its saved Include files).
    struct SavedHost: Equatable {
        let entry: HostEntry
        let isIncluded: Bool
    }

    /// Connect and Test act on the saved file (that is what ssh reads), so only hosts in it are offered.
    private struct SavedHosts {
        let store: ObjectIdentifier
        let hosts: [SavedHost]
        /// Lowercased alias → alias as written in the saved file (ssh matches aliases case-insensitively).
        let aliases: [String: String]
    }
    @ObservationIgnored private var savedHostsCache: SavedHosts?

    /// Rebuilt only after the store was loaded or saved (`savedStateDidChange`), not on every view update.
    private var savedHosts: SavedHosts {
        let id = ObjectIdentifier(store)
        // Register observation of the saved state so views update after a save or reload.
        _ = store.savedDocument
        _ = store.savedIncludedHosts
        if let cache = savedHostsCache, cache.store == id { return cache }
        var aliases: [String: String] = [:]
        var hosts: [SavedHost] = []
        let candidates = store.savedDocument.hosts.map { SavedHost(entry: $0, isIncluded: false) }
            + store.savedIncludedHosts.map { SavedHost(entry: $0.entry, isIncluded: true) }
        for host in candidates where !host.entry.isPattern {
            let key = host.entry.alias.lowercased()
            guard aliases[key] == nil else { continue }
            aliases[key] = host.entry.alias
            hosts.append(host)
        }
        let built = SavedHosts(store: id, hosts: hosts, aliases: aliases)
        savedHostsCache = built
        return built
    }

    /// Every connectable host of the saved file once (case-insensitive, like ssh), file hosts first.
    var savedConnectableHosts: [SavedHost] { savedHosts.hosts }

    /// An editable, non-pattern host that is not in the saved file yet (new or renamed):
    /// Connect and Test are off until it is saved.
    func isUnsavedHost(_ item: SidebarItem) -> Bool {
        guard case .host = item,
              let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return false }
        return savedAlias(entry.alias) == nil
    }

    /// `alias` as written in the saved file, or nil when the saved file has no such (non-pattern) host.
    func savedAlias(_ alias: String) -> String? {
        savedHosts.aliases[alias.lowercased()]
    }

    /// The alias to connect to for a sidebar item: nil for patterns, Match blocks, missing hosts
    /// and hosts that are not in the saved file yet.
    func connectableAlias(for item: SidebarItem) -> String? {
        switch item {
        case .host:
            guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return nil }
            return savedAlias(entry.alias)
        case .included:
            guard let host = SidebarBuilder.includedHost(for: item, in: store.includedHosts), !host.entry.isPattern else { return nil }
            return savedAlias(host.entry.alias)
        case .match:
            return nil
        }
    }

    /// Every connectable alias of the saved file once, file hosts first, then included ones.
    var connectableAliases: [String] {
        savedHosts.hosts.map(\.entry.alias)
    }

    @discardableResult
    func connect(alias requested: String) -> Connector.Outcome {
        guard let alias = savedAlias(requested) else {
            errorMessage = String(localized: "connect.notSaved")
            return .failed(.failed("not in the saved file"))
        }
        let builder = commandBuilder
        let request = LaunchRequest(sshArguments: builder.sshArguments(alias: alias), shellCommand: builder.shellCommand(alias: alias))
        guard !request.shellCommand.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            errorMessage = String(localized: "connect.invalidCommand")
            return .failed(.failed("control character"))
        }
        return launch(request)
    }

    /// "Upload to Server…": `ssh-copy-id -i <pub> [-F <config>] -- <alias>` in the chosen terminal (interactive).
    @discardableResult
    func uploadKey(publicKey: URL, alias requested: String) -> Connector.Outcome {
        guard let alias = savedAlias(requested) else {
            errorMessage = String(localized: "connect.notSaved")
            return .failed(.failed("not in the saved file"))
        }
        let arguments = ["-i", publicKey.path] + commandBuilder.configArguments + ["--", alias]
        let shellCommand = (["ssh-copy-id"] + arguments.map(SSHCommandBuilder.shellQuote)).joined(separator: " ")
        guard !shellCommand.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            errorMessage = String(localized: "connect.invalidCommand")
            return .failed(.failed("control character"))
        }
        return launch(LaunchRequest(sshArguments: arguments, shellCommand: shellCommand, program: "/usr/bin/ssh-copy-id"))
    }

    private func launch(_ request: LaunchRequest) -> Connector.Outcome {
        let outcome = Connector(choice: settings.terminal, isInstalled: terminalInstalled, makeLauncher: launcherFactory).connect(request)
        switch outcome {
        case .launched:
            errorMessage = nil
            fallbackNotice = nil
        case .fellBack(let from):
            let name = from.displayName
            errorMessage = nil
            fallbackNotice = String(localized: "connect.fellBack \(name)")
        case .failed(.automationDenied):
            AppLog.error(.connect, LaunchError.automationDenied)
            automationDenied = true
        case .failed(.failed(let detail)):
            AppLog.error(.connect, LaunchError.failed(detail))
            errorMessage = String(localized: "connect.failed \(detail)")
        }
        return outcome
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

    var sshDirectory: URL { settings.homeDirectory.appending(path: ".ssh") }

    /// ~/.ssh and the active config file's directory (spec §8.1), each once.
    var keyDirectories: [URL] {
        let configDirectory = store.fileURL.deletingLastPathComponent()
        return configDirectory.standardizedFileURL == sshDirectory.standardizedFileURL ? [sshDirectory] : [sshDirectory, configDirectory]
    }

    /// Host blocks of the saved file and its saved Include files: what ssh reads.
    var savedHostEntries: [HostEntry] {
        store.savedDocument.hosts + store.savedIncludedHosts.map(\.entry)
    }

    /// Editable, non-pattern hosts of the document (included files are read-only).
    var assignableAliases: [String] {
        var seen: Set<String> = []
        return store.document.hosts.filter { !$0.isPattern }.map(\.alias).filter { seen.insert($0).inserted }
    }

    /// Throws unless `alias` can be edited right now without dropping the open form's edits.
    func validateAssignment(toAlias alias: String) throws {
        guard store.loadState == .loaded, assignableAliases.contains(alias) else {
            throw KeyAssignmentError.hostNotFound(alias)
        }
        if hasPendingFormEdits { throw KeyAssignmentError.pendingFormEdits }
    }

    /// Adds `IdentityFile <~/path>` to the host as an unsaved edit (the normal Save flow writes it).
    func assignIdentityFile(_ url: URL, toAlias alias: String) throws {
        try validateAssignment(toAlias: alias)
        guard let entry = store.document.hosts.first(where: { !$0.isPattern && $0.alias == alias }) else {
            throw KeyAssignmentError.hostNotFound(alias)
        }
        let path = settings.displayPath(for: url)
        guard !entry.values(for: "IdentityFile").contains(path) else { return }
        var draft = HostDraft(entry)
        draft.directives.append(DraftDirective(key: "IdentityFile", value: path))
        try store.apply { try $0.updateHost(at: entry.headerLine, to: draft) }
        resetEditor()
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
        if (store.hasUnsavedChanges || hasPendingFormEdits) && !discardingUnsavedChanges { return .needsConfirmation }
        settings.setConfigPath(path)
        store.onDiskStateChange = nil
        store = makeStore(url, backupManager, Self.backupKind(for: url, home: settings.homeDirectory))
        observeSavedState()
        savedHostsCache = nil
        select(nil)
        connectionTests.clear()
        searchText = ""
        errorMessage = nil
        return .switched
    }

    func setBackupCount(_ count: Int) {
        settings.setBackupCount(count)
        backupManager.keep = settings.backupCount
        store.setBackupKeep(settings.backupCount)
        knownHosts.setBackupKeep(settings.backupCount)
    }
}

enum KeyAssignmentError: Error, Equatable {
    case hostNotFound(String)
    case pendingFormEdits
}
