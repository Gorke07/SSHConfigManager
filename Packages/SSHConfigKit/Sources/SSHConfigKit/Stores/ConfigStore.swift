import Foundation
import Observation

public enum ConfigLoadState: Equatable, Sendable {
    case loaded
    case missing
    /// Not valid UTF-8: shown as an error; never rewritten.
    case notUTF8
    case unreadable(String)
}

public enum ConfigStoreError: Error, Equatable, Sendable {
    case notEditable
    case conflict
    case validationFailed(String)
    case validationTimedOut
    /// The writer's own error (conflicts map to `.conflict`), so backup failures stay distinguishable.
    case writeFailed(SafeFileWriterError)
    /// The user discarded or reloaded while the save was validating; nothing was written.
    case saveCancelled
    case saveInProgress
    /// ssh could not be launched to validate; the string is for diagnostics only.
    case validatorUnavailable(String)
}

public struct SavePreparation: Equatable, Sendable {
    public let hunks: [DiffHunk]
    public let validation: ValidationOutcome
}

/// Single source of UI state for the active config file. The file itself is the
/// source of truth; edits live in `document` until `save()`.
@MainActor
@Observable
public final class ConfigStore {
    public let fileURL: URL
    /// Backup directory name under the backup root; per config file so backups never mix.
    public let backupKind: String
    public private(set) var document: ConfigDocument = .empty
    public private(set) var diskText = ""
    /// `diskText` parsed: what ssh actually reads. Re-parsed only when the disk text changes.
    public private(set) var savedDocument: ConfigDocument = .empty
    /// Hosts from the Include files of the saved file (`includedHosts` follows unsaved Include edits).
    public private(set) var savedIncludedHosts: [IncludedHost] = []
    public private(set) var loadState: ConfigLoadState = .missing
    public private(set) var includedHosts: [IncludedHost] = []
    public private(set) var externalChangePending = false
    public private(set) var isSaving = false
    /// True iff the FileWatcher was created.
    public private(set) var isWatching = false

    /// Files and texts the saved document's Includes read, to tell whether `refreshIncludes()` saw a change.
    @ObservationIgnored private var savedIncludeStates: [IncludeFileState] = []
    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    /// The text `savedDocument` was built from (nil: no file); lets refreshes skip no-op notifications.
    @ObservationIgnored private var savedViewText: String?
    @ObservationIgnored private var writer: SafeFileWriter
    @ObservationIgnored private let watchForChanges: Bool
    @ObservationIgnored private let validator: ConfigValidator
    /// The resolver the store follows Includes with (read-only, so other readers resolve identically).
    @ObservationIgnored public let includeResolver: IncludeResolver
    @ObservationIgnored private var watcher: FileWatcherGroup?
    @ObservationIgnored private var loadGeneration = 0
    /// Counts loads from disk (initial, reload, discard, external change without unsaved edits); saves and change notices do not count.
    public var loadRevision: Int { loadGeneration }
    /// Called after the file was (re)loaded from disk or saved, i.e. whenever the saved state may have changed.
    @ObservationIgnored public var onDiskStateChange: (@MainActor () -> Void)?

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        validator: ConfigValidator = ConfigValidator(),
        includeResolver: IncludeResolver = IncludeResolver(),
        watchForChanges: Bool = true,
        backupKind: String = "config"
    ) {
        self.fileURL = fileURL
        self.backupKind = backupKind
        self.writer = writer
        self.watchForChanges = watchForChanges
        self.validator = validator
        self.includeResolver = includeResolver
        load()
        if watchForChanges { startWatching() }
    }

    /// Number of backups kept per save, or nil when the writer makes no backups.
    public var backupKeep: Int? { writer.backups?.keep }

    public func setBackupKeep(_ keep: Int) {
        guard var backups = writer.backups else { return }
        backups.keep = max(keep, 1)
        writer = SafeFileWriter(backups: backups)
    }

    public var hasUnsavedChanges: Bool {
        !document.render().utf8.elementsEqual(diskText.utf8)
    }

    public func load() {
        loadGeneration += 1
        externalChangePending = false
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            reset(state: .missing)
            return
        } catch {
            reset(state: .unreadable(error.localizedDescription))
            return
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            reset(state: .notUTF8, fingerprint: FileFingerprint(data: data))
            return
        }
        document = ConfigDocument(parsing: text)
        diskText = text
        savedViewText = text
        savedDocument = document
        diskFingerprint = FileFingerprint(data: data)
        loadState = .loaded
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
        savedIncludedHosts = includedHosts
        savedIncludeStates = includeResolver.includeFileStates(of: savedDocument, rootFile: fileURL)
        onDiskStateChange?()
    }

    public func createFile() throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // A dangling symlink (`config -> ~/dotfiles/ssh/config`, target missing) gets its target created; the
        // link stays. The target's directory is not created: a missing one is reported instead.
        let target = try SafeFileWriter.destination(of: fileURL)
        if !fm.fileExists(atPath: target.path) {
            let targetDirectory = target.deletingLastPathComponent()
            guard fm.fileExists(atPath: targetDirectory.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: targetDirectory.path])
            }
            guard fm.createFile(atPath: target.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
            }
        }
        load()
        if watchForChanges && !isWatching { startWatching() }
    }

    /// Applies an edit atomically: if `edit` throws, `document` is unchanged.
    public func apply(_ edit: (inout ConfigDocument) throws -> Void) throws {
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        var copy = document
        try edit(&copy)
        let includesChanged = copy.includes.map(\.paths) != document.includes.map(\.paths)
        document = copy
        if includesChanged {
            includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
        }
    }

    /// Re-reads the Include files of the working and the saved document, for edits made to an Include
    /// file alone (the root file, its text and its dirty state stay untouched). Assigns a property only
    /// when its value changed, so observers and equality-based caches see real changes only.
    /// Returns true when any file the saved document includes changed (what ssh reads).
    @discardableResult
    public func refreshIncludes() -> Bool {
        let savedWalk = includeResolver.traverse(savedDocument, rootFile: fileURL)
        // Same Include paths: the working document's chain is the saved one, so one walk serves both.
        let working = document.includes.map(\.paths) == savedDocument.includes.map(\.paths)
            ? savedWalk.hosts
            : includeResolver.includedHosts(of: document, rootFile: fileURL)
        if working != includedHosts { includedHosts = working }
        if savedWalk.hosts != savedIncludedHosts { savedIncludedHosts = savedWalk.hosts }
        // Global lines or Match blocks in an Include file change what ssh resolves without changing the hosts.
        guard savedWalk.states != savedIncludeStates else { return false }
        savedIncludeStates = savedWalk.states
        return true
    }

    /// Reloads from disk (also clears `externalChangePending`).
    public func discardChanges() {
        load()
    }

    public func prepareSave(probeAlias: String? = nil) async -> SavePreparation {
        let text = document.render()
        let hunks = LineDiff.hunks(old: diskText, new: text)
        return SavePreparation(hunks: hunks, validation: await validate(text, probeAlias: probeAlias))
    }

    /// Validates with `ssh -G`, then writes via `SafeFileWriter` (conflict check, backup, atomic rename).
    /// Does nothing when there is nothing to write.
    public func save(overwritingExternalChanges: Bool = false, probeAlias: String? = nil) async throws {
        try await save(overwriting: overwritingExternalChanges, reviewed: nil, probeAlias: probeAlias)
    }

    /// Like `save()`, but replaces an externally changed file, provided the file still matches `reviewed`:
    /// the fingerprint of the disk version the user saw (nil: the file did not exist). A newer external
    /// edit (even one made while `ssh -G` validates) throws `.conflict` instead of being overwritten.
    public func save(overwritingDiskVersion reviewed: FileFingerprint?, probeAlias: String? = nil) async throws {
        try await save(overwriting: true, reviewed: .some(reviewed), probeAlias: probeAlias)
    }

    /// `reviewed` nil: `overwriting` ignores the disk state; `.some`: the disk must match that fingerprint.
    private func save(overwriting: Bool, reviewed: FileFingerprint??, probeAlias: String?) async throws {
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        guard !isSaving else { throw ConfigStoreError.saveInProgress }
        guard hasUnsavedChanges || overwriting else { return }
        isSaving = true
        defer { isSaving = false }

        let text = document.render()
        // Captured before the await: an external edit during validation must conflict.
        let expected = reviewed ?? diskFingerprint
        let ignoreConflict = overwriting && reviewed == nil
        let generation = loadGeneration

        let outcome = await validate(text, probeAlias: probeAlias)
        guard generation == loadGeneration else { throw ConfigStoreError.saveCancelled }
        switch outcome {
        case .valid: break
        case .invalid(let message): throw ConfigStoreError.validationFailed(message)
        case .timedOut: throw ConfigStoreError.validationTimedOut
        case .validatorUnavailable(let message): throw ConfigStoreError.validatorUnavailable(message)
        }

        do {
            try writer.write(text, to: fileURL, expected: expected,
                             ignoreConflict: ignoreConflict, backupKind: backupKind)
        } catch SafeFileWriterError.conflict {
            externalChangePending = true
            throw ConfigStoreError.conflict
        } catch let error as SafeFileWriterError {
            throw ConfigStoreError.writeFailed(error)
        }

        diskText = text
        savedViewText = text
        savedDocument = ConfigDocument(parsing: text)
        diskFingerprint = FileFingerprint(data: Data(text.utf8))
        externalChangePending = false
        includedHosts = includeResolver.includedHosts(of: savedDocument, rootFile: fileURL)
        savedIncludedHosts = includedHosts
        savedIncludeStates = includeResolver.includeFileStates(of: savedDocument, rootFile: fileURL)
        onDiskStateChange?()
    }

    /// Directories currently watched (test visibility).
    var watchedDirectories: [String] { watcher?.watchedDirectories ?? [] }

    func fileDidChange() {
        watcher?.refresh()   // the symlink or its target directory may have moved
        let current = try? FileFingerprint.of(fileAt: fileURL)
        guard current != diskFingerprint else {
            // Reverted to what we loaded: the saved view returns to `diskText` and the conflict is gone.
            if externalChangePending {
                externalChangePending = false
                setSavedView(text: diskText)
            }
            return
        }
        if hasUnsavedChanges {
            externalChangePending = true
            refreshSavedView()
        } else {
            load()
        }
    }

    /// The file changed under unsaved edits: keep `diskText` and the fingerprint (so Save still
    /// detects the conflict) but show what ssh now reads, so Connect/Test never offer removed hosts.
    /// A missing file empties the view; any other read failure or invalid UTF-8 keeps the old one.
    private func refreshSavedView() {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(validating: data, as: UTF8.self) else { return }
            setSavedView(text: text)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            setSavedView(text: nil)
        } catch {
            return
        }
    }

    /// Rebuilds what ssh reads from `text` (nil: no file). Notifies only when that text changed.
    private func setSavedView(text: String?) {
        guard text != savedViewText else { return }
        savedViewText = text
        if let text {
            savedDocument = ConfigDocument(parsing: text)
            savedIncludedHosts = includeResolver.includedHosts(of: savedDocument, rootFile: fileURL)
            savedIncludeStates = includeResolver.includeFileStates(of: savedDocument, rootFile: fileURL)
        } else {
            savedDocument = .empty
            savedIncludedHosts = []
            savedIncludeStates = []
        }
        onDiskStateChange?()
    }

    private func validate(_ text: String, probeAlias: String?) async -> ValidationOutcome {
        let alias = probeAlias ?? document.hosts.first(where: { !$0.isPattern })?.alias ?? "localhost"
        do {
            return try await validator.validate(text, probeAlias: alias)
        } catch {
            return .validatorUnavailable(String(describing: error))
        }
    }

    /// `fingerprint` is kept for a file that exists but cannot be shown (not UTF-8), so the
    /// directory watcher does not reload it on every unrelated event.
    private func reset(state: ConfigLoadState, fingerprint: FileFingerprint? = nil) {
        document = .empty
        diskText = ""
        savedViewText = nil
        savedDocument = .empty
        diskFingerprint = fingerprint
        includedHosts = []
        savedIncludedHosts = []
        savedIncludeStates = []
        loadState = state
        onDiskStateChange?()
    }

    private func startWatching() {
        let weakStore = WeakStore(self)   // store → watcher → closure must not retain the store
        watcher = FileWatcherGroup(file: fileURL) {
            Task { @MainActor in weakStore.value?.fileDidChange() }
        }
        isWatching = watcher != nil
    }
}

private final class WeakStore: @unchecked Sendable {
    weak var value: ConfigStore?
    init(_ value: ConfigStore) { self.value = value }
}
