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
    public private(set) var document: ConfigDocument = .empty
    public private(set) var diskText = ""
    public private(set) var loadState: ConfigLoadState = .missing
    public private(set) var includedHosts: [IncludedHost] = []
    public private(set) var externalChangePending = false
    public private(set) var isSaving = false
    /// True iff the FileWatcher was created.
    public private(set) var isWatching = false

    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    @ObservationIgnored private let writer: SafeFileWriter
    @ObservationIgnored private let validator: ConfigValidator
    @ObservationIgnored private let includeResolver: IncludeResolver
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var loadGeneration = 0

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        validator: ConfigValidator = ConfigValidator(),
        includeResolver: IncludeResolver = IncludeResolver(),
        watchForChanges: Bool = true
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.validator = validator
        self.includeResolver = includeResolver
        load()
        if watchForChanges { startWatching() }
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
            reset(state: .notUTF8)
            return
        }
        document = ConfigDocument(parsing: text)
        diskText = text
        diskFingerprint = FileFingerprint(data: data)
        loadState = .loaded
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
    }

    public func createFile() throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
            }
        }
        load()
    }

    /// Applies an edit atomically: if `edit` throws, `document` is unchanged.
    public func apply(_ edit: (inout ConfigDocument) throws -> Void) throws {
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        var copy = document
        try edit(&copy)
        document = copy
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
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
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        guard !isSaving else { throw ConfigStoreError.saveInProgress }
        guard hasUnsavedChanges || overwritingExternalChanges else { return }
        isSaving = true
        defer { isSaving = false }

        let text = document.render()
        let expected = diskFingerprint   // captured before the await: an external edit during validation must conflict
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
                             ignoreConflict: overwritingExternalChanges, backupKind: "config")
        } catch SafeFileWriterError.conflict {
            externalChangePending = true
            throw ConfigStoreError.conflict
        } catch let error as SafeFileWriterError {
            throw ConfigStoreError.writeFailed(error)
        }

        diskText = text
        diskFingerprint = FileFingerprint(data: Data(text.utf8))
        externalChangePending = false
        includedHosts = includeResolver.includedHosts(of: ConfigDocument(parsing: text), rootFile: fileURL)
    }

    func fileDidChange() {
        let current = try? FileFingerprint.of(fileAt: fileURL)
        guard current != diskFingerprint else { return }
        if hasUnsavedChanges {
            externalChangePending = true
        } else {
            load()
        }
    }

    private func validate(_ text: String, probeAlias: String?) async -> ValidationOutcome {
        let alias = probeAlias ?? document.hosts.first(where: { !$0.isPattern })?.alias ?? "localhost"
        do {
            return try await validator.validate(text, probeAlias: alias)
        } catch {
            return .validatorUnavailable(String(describing: error))
        }
    }

    private func reset(state: ConfigLoadState) {
        document = .empty
        diskText = ""
        diskFingerprint = nil
        includedHosts = []
        loadState = state
    }

    private func startWatching() {
        let directory = fileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let weakStore = WeakStore(self)   // store → watcher → closure must not retain the store
        watcher = FileWatcher(directory: directory) {
            Task { @MainActor in weakStore.value?.fileDidChange() }
        }
        isWatching = watcher != nil
    }
}

private final class WeakStore: @unchecked Sendable {
    weak var value: ConfigStore?
    init(_ value: ConfigStore) { self.value = value }
}
