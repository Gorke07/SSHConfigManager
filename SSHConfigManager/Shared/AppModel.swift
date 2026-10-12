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
    /// Narrows the sidebar to hosts whose last connection test fell in this category.
    var statusFilter: StatusCategory?
    /// A host waiting for the user to confirm its deletion (menu, context menu or the delete key).
    var pendingDelete: SidebarItem?
    /// True while a main window is the key window. Host menu items are disabled otherwise so their
    /// shortcuts (⌘↩, ⌘T, ⌘D, ⌘⇧C) stay available to the Quick Connect panel and the other windows.
    var mainWindowIsKey = false
    /// The "Delete known_hosts entry…" flow for one alias; drives `HostKeyRemovalSheet`.
    var hostKeyRemoval: HostKeyRemoval?
    /// The running `ssh -G` lookup of that flow; cancelling the flow cancels it (and so ssh).
    @ObservationIgnored var hostKeyRemovalTask: Task<Void, Never>?
    /// Informational: the chosen terminal was unavailable and the connection opened in Terminal.
    var fallbackNotice: String?
    /// The form for the current selection. Owned here (not by the view) so edits that validation
    /// blocked survive closing the window; dropped when the selection or document is reset.
    @ObservationIgnored private(set) var activeEditor: HostEditorModel?
    @ObservationIgnored private var activeEditorToken: UUID?
    /// A selection waiting for the user to confirm discarding blocked form edits.
    var pendingSelection: SidebarItem?
    /// The group field's text while it differs from what the selected host has (nil: not edited).
    /// Lives here, not in the view, so an unapplied draft counts as a pending edit.
    var groupDraft: String?
    /// Reads a private key's head for the lint; tests count calls through it.
    @ObservationIgnored var keyEncryptionReader: @Sendable (URL) -> KeyEncryption = { url in
        (try? KeyFileInspector.readHead(of: url)).map(KeyFileInspector.encryption(ofPrivateKeyHead:)) ?? .unknown
    }
    @ObservationIgnored private var lintCache: LintCache?
    /// Effective Settings disclosure state; lives for the session, across host switches and editor rebuilds.
    var effectiveSettingsExpanded = false
    var effectiveSettingsShowAll = false

    @ObservationIgnored private let makeStore: StoreFactory
    @ObservationIgnored private let makeKnownHostsStore: KnownHostsStoreFactory
    @ObservationIgnored let processRunner: any ProcessRunning
    @ObservationIgnored private let launcherFactory: @MainActor (TerminalChoice) -> any TerminalLaunching
    @ObservationIgnored private let terminalInstalled: @MainActor (TerminalChoice) -> Bool
    /// Set when macOS denied Automation access; the main window explains how to allow it.
    var automationDenied = false
    private(set) var memory: HostMemory

    static func memoryKey(for url: URL, home: URL) -> String {
        "hostMemory." + backupKind(for: url, home: home)
    }

    /// Session-only connection test results; cleared when the saved file changes or another one is opened.
    let connectionTests: ConnectionTestsModel
    /// `ssh -G` results per alias; cleared with the connection tests.
    let effectiveConfig: EffectiveConfigCache
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
        self.effectiveConfig = EffectiveConfigCache(runner: processRunner)
        self.launcherFactory = launcherFactory
        self.terminalInstalled = isTerminalInstalled
        self.keys = KeysModel(tools: keyTools)
        let backups = BackupManager(rootDirectory: backupRoot, keep: settings.backupCount)
        self.backupManager = backups
        self.makeStore = makeStore
        let configKind = Self.backupKind(for: settings.configURL, home: settings.homeDirectory)
        let knownHostsKind = Self.knownHostsBackupKind(for: settings.knownHostsURL, home: settings.homeDirectory)
        self.store = makeStore(settings.configURL, backups, configKind)
        self.makeKnownHostsStore = makeKnownHostsStore
        self.knownHosts = makeKnownHostsStore(settings.knownHostsURL, backups, knownHostsKind)
        self.memory = Self.makeMemory(for: settings.configURL, settings: settings)
        migrateLegacyKeys(for: settings.configURL, kind: configKind, prefix: "config")
        migrateLegacyKeys(for: settings.knownHostsURL, kind: knownHostsKind, prefix: "known_hosts")
        keys.app = self
        observeSavedState()
    }

    /// The saved file changed (save, reload, external change): results measured against the old
    /// file are stale and the connectable hosts must be rebuilt.
    private func observeSavedState() {
        lastLoadRevision = store.loadRevision
        store.onDiskStateChange = { [weak self] in self?.savedStateDidChange() }
    }

    private func savedStateDidChange() {
        savedHostsCache = nil
        connectionTests.clear()
        effectiveConfig.clear()
        statusFilter = nil
        pendingDelete = nil
        // Only an actual reload from disk resets the draft; a save applied it already and change notices keep it.
        if store.loadRevision != lastLoadRevision {
            lastLoadRevision = store.loadRevision
            groupDraft = nil
            // Rebuild the form from the reloaded file here, not in a view: the main window may be closed
            // (menu bar only) and would otherwise reopen on the old values. Blocked edits stay (stale guard).
            if !hasBlockedFormEdits { resetEditor() }
        }
        invalidateLint()
    }

    @ObservationIgnored private var lastLoadRevision = 0
    /// Bumped by `invalidateLint()`; read by `lintIssueMap()` so views re-render after key files changed.
    private(set) var lintRevision = 0

    /// Drops the memoized lint (key files can change without the document changing).
    func invalidateLint() {
        lintCache = nil
        lintRevision += 1
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
        if url.standardizedFileURL.path == defaultPath.standardizedFileURL.path
            || url.resolvingSymlinksInPath().path == defaultPath.resolvingSymlinksInPath().path { return prefix }
        return hashedKind(for: url, prefix: prefix)
    }

    /// The per-path key used before symlinks were resolved: the hash of the standardized path (also the key of
    /// any other file; only a symlink to the default file moved from it to the plain prefix).
    private static func hashedKind(for url: URL, prefix: String) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return prefix + "-" + digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    }

    /// Backups (and favorites/recents) that were saved under the old hashed key of a path that now resolves to the
    /// default file move to its key, so nothing disappears from the list. A failure is logged and leaves them in place.
    private func migrateLegacyKeys(for url: URL, kind: String, prefix: String) {
        let legacy = Self.hashedKind(for: url, prefix: prefix)
        guard legacy != kind else { return }
        do { try backupManager.migrate(from: legacy, to: kind) } catch { AppLog.error(.backups, error) }
    }

    /// Moves the memory saved under the old hashed key to `key`. When both exist the new entries come first,
    /// then the old ones, exact duplicates removed and each list capped; the old key is removed either way.
    static func mergeLegacyMemory(defaults: UserDefaults, key: String, legacyKey: String) {
        guard legacyKey != key, let old = defaults.object(forKey: legacyKey) else { return }
        defer { defaults.removeObject(forKey: legacyKey) }
        guard let current = defaults.object(forKey: key) else {
            defaults.set(old, forKey: key)
            return
        }
        let new = current as? [String: Any] ?? [:]
        let previous = old as? [String: Any] ?? [:]
        func merged(_ field: String, cap: Int) -> [String] {
            var seen = Set<String>()
            var result: [String] = []
            for value in ((new[field] as? [Any]) ?? []) + ((previous[field] as? [Any]) ?? []) {
                guard let alias = value as? String, !alias.isEmpty, seen.insert(alias).inserted else { continue }
                result.append(alias)
            }
            return Array(result.prefix(cap))
        }
        defaults.set(["favorites": merged("favorites", cap: HostMemory.maxFavorites),
                      "recents": merged("recents", cap: HostMemory.maxRecents)], forKey: key)
    }

    private static func makeMemory(for url: URL, settings: AppSettings) -> HostMemory {
        let home = settings.homeDirectory
        let key = memoryKey(for: url, home: home)
        let legacyKey = "hostMemory." + hashedKind(for: url, prefix: "config")
        mergeLegacyMemory(defaults: settings.userDefaults, key: key, legacyKey: legacyKey)
        return HostMemory(defaults: settings.userDefaults, key: key)
    }

    /// Opens another known_hosts file. There are no drafts, so nothing needs confirming.
    @discardableResult
    func switchKnownHosts(to path: String) -> Bool {
        guard AppSettings.isValidConfigPath(path) else { return false }
        settings.setKnownHostsPath(path)
        let url = settings.knownHostsURL
        let kind = Self.knownHostsBackupKind(for: url, home: settings.homeDirectory)
        migrateLegacyKeys(for: url, kind: kind, prefix: "known_hosts")
        knownHosts = makeKnownHostsStore(url, backupManager, kind)
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
        /// Exact alias → alias as written in the saved file (ssh matches Host patterns case-sensitively).
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
            let key = host.entry.alias
            guard aliases[key] == nil else { continue }
            aliases[key] = host.entry.alias
            hosts.append(host)
        }
        let built = SavedHosts(store: id, hosts: hosts, aliases: aliases)
        savedHostsCache = built
        return built
    }

    /// Every connectable host of the saved file once (exact, case-sensitive like ssh; the first block of a repeated alias wins), file hosts first.
    var savedConnectableHosts: [SavedHost] { savedHosts.hosts }

    /// An editable, non-pattern host that is not in the saved file yet (new or renamed):
    /// Connect and Test are off until it is saved. Not while the file changed on disk: the banner
    /// explains that, and Save would only hit the conflict sheet.
    func isUnsavedHost(_ item: SidebarItem) -> Bool {
        guard !store.externalChangePending, case .host = item,
              let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return false }
        return savedAlias(entry.alias) == nil
    }

    /// `alias` as written in the saved file, or nil when the saved file has no such (non-pattern) host.
    func savedAlias(_ alias: String) -> String? {
        savedHosts.aliases[alias]
    }

    /// Resolver result for a host of the saved file (Includes followed in place, with the store's own resolver).
    func resolvedConfig(forSavedAlias alias: String) -> ResolvedConfig? {
        guard let saved = savedAlias(alias) else { return nil }
        let document = store.savedDocument
        let resolver = store.includeResolver
        let includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)] = { resolver.includedDocuments(for: $0) }
        // The root block is the target even when an earlier Include defines the same alias: it is the block the
        // sidebar shows and the user edits; the included block's rows still show `.include(...)`.
        if let header = document.hosts.first(where: { !$0.isPattern && $0.alias == saved })?.headerLine {
            return ConfigResolver.resolve(alias: saved, document: document, targetHeader: header, includes: includes)
        }
        // The first block of this alias lives in an Include file: that block is "this block".
        let included = store.savedIncludedHosts.first { !$0.entry.isPattern && $0.entry.alias == saved }
        return ConfigResolver.resolve(alias: saved, document: document, targetHeader: included?.entry.headerLine,
                                      targetFile: included?.file, includes: includes)
    }

    /// Re-reads the Include files (they can change without the root file changing). When the saved
    /// view's included hosts changed, the effective settings are dropped and reloaded. Connection
    /// tests stay: they are per alias, and every other host is unaffected.
    func refreshIncludes() {
        let includesChanged = store.refreshIncludes()
        if includesChanged {
            savedHostsCache = nil
            effectiveConfig.clear()
        }
        // Key files can change while the app is in the background: compare the stamps of the files the last lint
        // pass looked at, so an activation with nothing changed leaves the memoized lint alone.
        if includesChanged || keyFilesChangedSinceLint() { invalidateLint() }
    }

    /// (inode, size, mtime) of a key file the lint looked at; nil when it does not exist.
    private struct KeyStamp: Equatable {
        let inode: UInt64
        let size: Int64
        let mtimeSeconds: Int
        let mtimeNanos: Int

        init?(path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            mtimeSeconds = Int(info.st_mtimespec.tv_sec)
            mtimeNanos = Int(info.st_mtimespec.tv_nsec)
        }
    }

    @ObservationIgnored private var lintKeyStamps: [String: KeyStamp?]?

    private func keyFilesChangedSinceLint() -> Bool {
        guard let stamps = lintKeyStamps else { return false }
        return stamps.contains { KeyStamp(path: $0.key) != $0.value }
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

    /// Connects in the chosen terminal. Returns nil, doing nothing, while another launch is still in flight
    /// (a double click or a repeated shortcut must not open two windows).
    @discardableResult
    func connect(alias requested: String) async -> Connector.Outcome? {
        guard !launchInFlight else { return nil }
        guard let alias = savedAlias(requested) else {
            AppLog.info(.connect, LaunchError.notSaved)
            errorMessage = String(localized: "connect.notSaved")
            return .failed(.notSaved)
        }
        let builder = commandBuilder
        let request = LaunchRequest(sshArguments: builder.sshArguments(alias: alias), shellCommand: builder.shellCommand(alias: alias))
        guard !request.shellCommand.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            AppLog.info(.connect, LaunchError.invalidCommand)
            errorMessage = String(localized: "connect.invalidCommand")
            return .failed(.invalidCommand)
        }
        guard let outcome = await runLaunch(request) else { return nil }
        report(outcome)
        switch outcome {
        case .launched, .fellBack: memory.recordConnection(alias)
        default: break
        }
        return outcome
    }

    /// Tests the saved file's host (exact alias, as `connect` does); an unsaved or edited alias is not tested.
    func test(alias requested: String) async {
        guard let alias = savedAlias(requested) else {
            errorMessage = String(localized: "connect.notSaved")
            return
        }
        await connectionTests.test(alias, using: commandBuilder)
    }

    /// Favorites that are hosts of the saved file, as written there.
    var favoriteAliases: [String] { memory.favorites.compactMap(savedAlias) }

    /// Recently connected saved hosts, most recent first.
    var recentAliases: [String] { memory.recents.compactMap(savedAlias) }

    var statusCounts: [StatusCategory: Int] {
        var counts: [StatusCategory: Int] = [:]
        for alias in connectableAliases {
            if let status = connectionTests.results[alias]?.status { counts[StatusCategory.of(status), default: 0] += 1 }
        }
        return counts
    }

    /// Rows without a connectable alias (patterns, includes of patterns, Match) have no status and are hidden by a filter.
    func passesStatusFilter(_ item: SidebarItem) -> Bool {
        guard let filter = statusFilter else { return true }
        guard let alias = connectableAlias(for: item), let status = connectionTests.results[alias]?.status else { return false }
        return StatusCategory.of(status) == filter
    }

    func requestDelete(_ item: SidebarItem) {
        guard SidebarBuilder.hostEntry(for: item, in: store.document) != nil else { return }
        pendingDelete = item
    }

    func confirmPendingDelete() {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        do {
            try HostCommands.delete(item, in: store)
            if selection == item {
                select(nil)
            } else if case .host(let alias, let removed) = item,
                      case .host(let selectedAlias, let m)? = selection, selectedAlias == alias, m > removed {
                // Later blocks of the same alias moved up by one; the selection follows its block.
                let moved = SidebarItem.host(alias: alias, occurrence: m - 1)
                selection = moved
                activeEditor?.follow(to: moved)
            }
        } catch {
            errorMessage = Messages.text(for: error)
        }
    }

    func copySSHCommand(_ item: SidebarItem, copy: (String) -> Void) {
        if let command = HostCommands.sshCommand(for: item, document: store.document, builder: commandBuilder) { copy(command) }
    }

    func toggleFavorite(_ alias: String) {
        var existing = Set(savedConnectableHosts.map(\.entry.alias))
        for host in store.document.hosts where !host.isPattern { existing.insert(host.alias) }
        let target = savedAlias(alias) ?? alias
        if !memory.toggleFavorite(target, existing: existing) {
            let limit = String(HostMemory.maxFavorites)
            errorMessage = String(localized: "favorite.limit \(limit)")
        }
    }

    /// "Upload to Server…": `ssh-copy-id -i <pub> [-F <config>] -- <alias>` in the chosen terminal (interactive).
    /// Returns the raw outcome and never touches the main window's alerts (the Keys window reports it).
    /// Nil, doing nothing, while another launch is in flight.
    @discardableResult
    func uploadKey(publicKey: URL, alias requested: String) async -> Connector.Outcome? {
        guard !launchInFlight else { return nil }
        guard let alias = savedAlias(requested) else {
            AppLog.info(.connect, LaunchError.notSaved)
            return .failed(.notSaved)
        }
        let arguments = ["-i", publicKey.path] + commandBuilder.configArguments + ["--", alias]
        let shellCommand = (["ssh-copy-id"] + arguments.map(SSHCommandBuilder.shellQuote)).joined(separator: " ")
        guard !shellCommand.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            AppLog.info(.connect, LaunchError.invalidCommand)
            return .failed(.invalidCommand)
        }
        return await runLaunch(LaunchRequest(sshArguments: arguments, shellCommand: shellCommand, program: "/usr/bin/ssh-copy-id"))
    }

    /// True from the moment a launch starts until its outcome is known (observed by the Connect buttons).
    private(set) var launchInFlight = false

    /// Launches and logs; reports nothing to the UI. Nil, doing nothing, while another launch is in flight.
    private func runLaunch(_ request: LaunchRequest) async -> Connector.Outcome? {
        guard !launchInFlight else { return nil }
        launchInFlight = true
        defer { launchInFlight = false }
        let outcome = await Connector(choice: settings.terminal, isInstalled: terminalInstalled, makeLauncher: launcherFactory).connect(request)
        if case .failed(let error) = outcome { AppLog.error(.connect, error) }
        return outcome
    }

    /// Main-window reporting of a connect outcome.
    private func report(_ outcome: Connector.Outcome) {
        switch outcome {
        case .launched:
            errorMessage = nil
            fallbackNotice = nil
        case .fellBack(let from):
            let name = from.displayName
            errorMessage = nil
            fallbackNotice = String(localized: "connect.fellBack \(name)")
        case .failed(.automationDenied):
            automationDenied = true
        case .failed(let error):
            let detail = error.userMessage ?? ""
            errorMessage = String(localized: "connect.failed \(detail)")
        }
    }

    func select(_ item: SidebarItem?) {
        selection = item
        groupDraft = nil
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

    /// Sets or (nil/blank) removes the host's `# group:` line as an unsaved edit. The open editor
    /// keeps its fields: it finds its block by alias and occurrence and compares only directives.
    func setGroup(_ item: SidebarItem, to name: String?) {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else {
            groupDraft = nil   // the host is gone: nothing to apply the draft to
            return
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.apply { try $0.setGroup(ofHostAt: entry.headerLine, to: trimmed?.isEmpty == false ? trimmed : nil) }
            groupDraft = nil
        } catch {
            errorMessage = Messages.text(for: error)
        }
    }

    /// Group names used in the document, for suggestions.
    var existingGroups: [String] {
        let document = store.document
        let names = Set(document.hosts.compactMap { document.group(ofHostAt: $0.headerLine) })
        return names.sorted(by: SidebarBuilder.groupNameOrder)
    }

    private struct LintCache {
        let store: ObjectIdentifier
        let document: ConfigDocument
        let included: [IncludedHost]
        let map: [SidebarItem: [HostIssue]]
    }

    /// Lint of every root-file Host block in the document being edited (so fixes show at once),
    /// keyed by sidebar item. Computed once and reused while the document and the included hosts
    /// are unchanged (the detail pane and the sidebar share it). One pass: duplicates and first
    /// blocks are computed once, and each key file is read at most once. Pattern blocks get the
    /// IdentityFile checks only.
    func lintIssueMap() -> [SidebarItem: [HostIssue]] {
        _ = lintRevision
        let document = store.document
        let included = store.includedHosts
        let id = ObjectIdentifier(store)
        if let cache = lintCache, cache.store == id, cache.document == document, cache.included == included { return cache.map }
        let map = computeLintIssueMap(document: document, included: included)
        // Writing the revision here would re-trigger observers; the cache is plain state.
        lintCache = LintCache(store: id, document: document, included: included, map: map)
        return map
    }

    private func computeLintIssueMap(document: ConfigDocument, included: [IncludedHost]) -> [SidebarItem: [HostIssue]] {
        let reads = KeyReadMemo(reader: keyEncryptionReader)
        defer { lintKeyStamps = Dictionary(uniqueKeysWithValues: reads.touchedPaths.map { ($0, KeyStamp(path: $0)) }) }
        let lint = HostLint(
            home: settings.homeDirectory,
            fileExists: { reads.exists($0) },
            encryption: { reads.encryption(of: $0) })
        let duplicates = HostLint.duplicateCounts(document: document, included: included)
        let exactDuplicates = HostLint.exactDuplicateCounts(document: document, included: included)
        var firstBlocks = HostLint.firstBlocks(document: document)
        applyIncludeOrder(to: &firstBlocks, document: document)
        var seen: [String: Int] = [:]
        var map: [SidebarItem: [HostIssue]] = [:]
        for entry in document.hosts {
            let occurrence = seen[entry.alias, default: 0]
            seen[entry.alias] = occurrence + 1
            var issues = lint.issues(for: entry, duplicates: duplicates, exactDuplicates: exactDuplicates, firstBlocks: firstBlocks)
            if entry.isPattern {
                issues.removeAll {
                    switch $0 {
                    case .duplicateAlias, .duplicateAliasCaseOnly: true
                    default: false
                    }
                }
            }
            if !issues.isEmpty { map[.host(alias: entry.alias, occurrence: occurrence)] = issues }
        }
        return map
    }

    /// ssh reads an Include where it stands. A root block is no longer the first for a name when an
    /// Include above it that ssh applies to that name (top-level, or inside a Host block whose
    /// patterns match it) resolves to a file defining the name. Names compare exactly: ssh matches Host patterns
    /// case-sensitively, so a file defining only a case variant does not come first.
    private func applyIncludeOrder(to firstBlocks: inout [String: Int], document: ConfigDocument) {
        let directives = document.includes
        guard !directives.isEmpty, let lastHeader = firstBlocks.values.max() else { return }
        let resolver = store.includeResolver
        let hostHeaders = Dictionary(uniqueKeysWithValues: document.hosts.map { ($0.headerLine, $0) })
        let matchHeaders = Set(document.matches.map(\.headerLine))
        // `Match all` always applies (verified with ssh -G), so an Include in it counts as top-level.
        // Other criteria are conditional and unknown here: those Includes are ignored.
        let matchAll = Set(document.matches.filter {
            $0.criteria.trimmingCharacters(in: .whitespaces).asciiLowercased == "all"
        }.map(\.headerLine))
        // The block an Include line sits in: the nearest header above it.
        func scope(of line: Int) -> HostEntry?? {
            let nearest = (Array(hostHeaders.keys) + Array(matchHeaders)).filter { $0 < line }.max()
            guard let nearest else { return .some(nil) }       // top level
            if let host = hostHeaders[nearest] { return .some(host) }
            if matchAll.contains(nearest) { return .some(nil) }
            return nil                                          // inside a Match block: condition unknown, ignored
        }
        for directive in directives where directive.line < lastHeader {
            guard let blockScope = scope(of: directive.line) else { continue }
            var defined: Set<String> = []
            var visited: Set<String> = []
            collectNames(of: directive, resolver: resolver, depth: 0, visited: &visited, into: &defined)
            for key in defined {
                guard let header = firstBlocks[key], header > directive.line, header != -1 else { continue }
                if let host = blockScope {
                    guard ConfigResolver.hostLineMatches(host.patterns, alias: key) else { continue }
                }
                firstBlocks[key] = -1
            }
        }
    }

    private func collectNames(of directive: IncludeDirective, resolver: IncludeResolver, depth: Int,
                              visited: inout Set<String>, into names: inout Set<String>) {
        guard depth < 16 else { return }
        for (file, included) in resolver.includedDocuments(for: directive) {
            // Each file once, like IncludeResolver: includes that name each other must not multiply reads.
            guard visited.insert(file.resolvingSymlinksInPath().path).inserted else { continue }
            for entry in included.hosts {
                for name in entry.patterns where !name.hasPrefix("!") && !name.contains("*") && !name.contains("?") {
                    names.insert(name)
                }
            }
            for nested in included.includes { collectNames(of: nested, resolver: resolver, depth: depth + 1, visited: &visited, into: &names) }
        }
    }

    func lintIssues(for item: SidebarItem) -> [HostIssue] {
        guard case .host = item else { return [] }
        return lintIssueMap()[item] ?? []
    }

    /// IdentityFile values (as written) of this host that name a private key without a passphrase.
    /// The editor marks those rows; the sidebar and the detail header leave this hint out.
    func unencryptedIdentityFiles(for item: SidebarItem) -> Set<String> {
        Set(lintIssues(for: item).compactMap {
            if case .unencryptedKey(let path) = $0 { path } else { nil }
        })
    }

    /// The group the selected host's block has in the document.
    func savedGroup(for item: SidebarItem) -> String {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return "" }
        return store.document.group(ofHostAt: entry.headerLine) ?? ""
    }

    /// Writes a pending group draft into the document (an unsaved edit), like pending form edits survive a save.
    func applyPendingGroupDraft() {
        guard let item = selection else { groupDraft = nil; return }
        guard hasPendingGroupDraft else {
            if SidebarBuilder.hostEntry(for: item, in: store.document) == nil { groupDraft = nil }
            return
        }
        setGroup(item, to: groupDraft)
    }

    /// Edits the form could not apply (validation or write failure); an unapplied group draft is not one.
    var hasBlockedFormEdits: Bool { activeEditor?.hasPendingChanges ?? false }

    var hasPendingGroupDraft: Bool {
        guard let draft = groupDraft, let item = selection,
              SidebarBuilder.hostEntry(for: item, in: store.document) != nil else { return false }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines) != savedGroup(for: item)
    }

    var hasPendingFormEdits: Bool { hasBlockedFormEdits || hasPendingGroupDraft }

    /// A host creation waiting for the user to confirm discarding blocked form edits.
    enum HostCreation: Equatable {
        case new
        case duplicate(SidebarItem)
    }

    /// Set while the discard confirmation for an Add/Duplicate is showing; nothing was created yet.
    var pendingCreation: HostCreation?

    /// Adds a new host and selects it. With unapplied form edits it asks first and creates nothing until confirmed.
    func addHost() { requestCreation(.new) }

    /// Duplicates `item` and selects the copy (asks first like `addHost`).
    func duplicateHost(_ item: SidebarItem) { requestCreation(.duplicate(item)) }

    private func requestCreation(_ creation: HostCreation) {
        if hasPendingFormEdits {
            pendingSelection = nil
            pendingCreation = creation
        } else {
            performCreation(creation)
        }
    }

    /// A failure is logged and shown.
    private func performCreation(_ creation: HostCreation) {
        do {
            switch creation {
            case .new: select(try HostCommands.addHost(to: store))
            case .duplicate(let item): if let copy = try HostCommands.duplicate(item, in: store) { select(copy) }
            }
        } catch {
            AppLog.error(.edit, error)
            errorMessage = Messages.text(for: error)
        }
    }

    /// True while a discard confirmation (a selection or a host creation) is showing.
    var hasPendingDiscardConfirmation: Bool { pendingSelection != nil || pendingCreation != nil }

    /// Selects `item`, unless the form holds edits that were never applied; then asks first.
    func requestSelect(_ item: SidebarItem?) {
        if hasPendingFormEdits, item != nil {
            pendingCreation = nil
            pendingSelection = item
        } else {
            select(item)
        }
    }

    func confirmPendingSelection() {
        if let creation = pendingCreation {
            pendingCreation = nil
            performCreation(creation)
            return
        }
        let item = pendingSelection
        pendingSelection = nil
        select(item)
    }

    func cancelPendingSelection() {
        pendingSelection = nil
        pendingCreation = nil
    }

    /// The alias `ssh -G` probes when saving: the selected host as it is now in the document (a rename counts).
    var probeAlias: String? {
        guard let item = selection, let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return nil }
        return entry.alias
    }

    func makeSaveFlow() -> SaveFlowModel {
        SaveFlowModel(store: store, probeAlias: probeAlias)
    }

    /// Called by the editor after it renamed the selected host.
    func followRename(to item: SidebarItem) {
        selection = item
    }

    var sshDirectory: URL { settings.homeDirectory.appending(path: ".ssh") }

    /// ~/.ssh and the active config file's directory (spec §8.1), each once.
    var keyDirectories: [URL] {
        let configDirectory = store.fileURL.deletingLastPathComponent()
        return KeyUsage.sameFile(configDirectory, sshDirectory) ? [sshDirectory] : [sshDirectory, configDirectory]
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
        let home = settings.homeDirectory
        // Already assigned, however it is spelled (~/…, absolute, through a symlink or `..`).
        guard !entry.values(for: "IdentityFile").contains(where: { value in
            value == path || KeyUsage.resolve(value, home: home).map { KeyUsage.sameFile($0, url) } ?? false
        }) else { return }
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
        let kind = Self.backupKind(for: url, home: settings.homeDirectory)
        migrateLegacyKeys(for: url, kind: kind, prefix: "config")
        store = makeStore(url, backupManager, kind)
        memory = Self.makeMemory(for: url, settings: settings)
        observeSavedState()
        savedHostsCache = nil
        select(nil)
        connectionTests.clear()
        effectiveConfig.clear()
        statusFilter = nil
        pendingDelete = nil
        pendingSelection = nil
        pendingCreation = nil
        searchText = ""
        errorMessage = nil
        return .switched
    }

    enum SaveSwitchResult: Equatable { case switched, invalid, failed(String) }

    /// Saves the unsaved changes (validation included), then opens `path`. Nothing is switched unless the save succeeded.
    func saveThenSwitchConfig(to path: String) async -> SaveSwitchResult {
        // Blocked form edits cannot be saved, and switching would silently drop them: stay and say so.
        if hasBlockedFormEdits { return .failed(String(localized: "discardForm.message")) }
        applyPendingGroupDraft()
        if hasPendingGroupDraft { return .failed(errorMessage ?? "") }
        if store.hasUnsavedChanges {
            let flow = makeSaveFlow()
            await flow.prepare()
            await flow.confirm()
            switch flow.phase {
            case .done: break
            case .review(let preparation): return .failed(Messages.text(for: preparation.validation))
            case .conflict: return .failed(Messages.text(for: ConfigStoreError.conflict))
            case .failed(let message): return .failed(message)
            case .preparing, .saving: return .failed(Messages.text(for: ConfigStoreError.saveInProgress))
            }
        }
        return switchConfig(to: path, discardingUnsavedChanges: true) == .invalid ? .invalid : .switched
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

/// Reads each private key's head at most once per lint pass, and remembers every path the pass looked at.
private final class KeyReadMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [URL: KeyEncryption] = [:]
    private var touched: Set<String> = []
    private let reader: @Sendable (URL) -> KeyEncryption

    init(reader: @escaping @Sendable (URL) -> KeyEncryption) { self.reader = reader }

    var touchedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(touched)
    }

    func exists(_ url: URL) -> Bool {
        lock.lock()
        touched.insert(url.path)
        lock.unlock()
        return FileManager.default.fileExists(atPath: url.path)
    }

    func encryption(of url: URL) -> KeyEncryption {
        lock.lock()
        defer { lock.unlock() }
        touched.insert(url.path)
        if let known = cache[url] { return known }
        let value = reader(url)
        cache[url] = value
        return value
    }
}

extension HostIssue {
    /// A host-level warning (sidebar badge, detail header). A key without a passphrase is a hint on its
    /// IdentityFile row instead: the host itself works, and the same key would otherwise warn on every host using it.
    var isHostWarning: Bool {
        if case .unencryptedKey = self { false } else { true }
    }
}
