import Foundation
import Observation

public enum KnownHostsStoreError: Error, Equatable, Sendable {
    /// Not loaded (unreadable or not UTF-8): never rewritten.
    case notEditable
    /// The document changed since the user selected rows; nothing was written.
    case staleSelection
    /// The file changed on disk since it was loaded; it was reloaded and nothing was written.
    case conflict
    case writeFailed(SafeFileWriterError)
}

/// The known_hosts file. No drafts: removals and restores are written immediately
/// (conflict check → backup → atomic rename) and reloaded.
@MainActor
@Observable
public final class KnownHostsStore {
    public let fileURL: URL
    public let backupKind: String
    public private(set) var document: KnownHostsDocument = .empty
    public private(set) var loadState: ConfigLoadState = .missing
    /// Incremented on every load and write; selections are only valid for the revision they were made in.
    public private(set) var revision = 0
    public private(set) var isWatching = false
    /// A background read is running: `document` is still the previous one (empty before the first load).
    public private(set) var isLoading = false
    /// Initial loads and file-change reloads read and parse off the main actor (`reload()`).
    public let loadsInBackground: Bool

    @ObservationIgnored private var writer: SafeFileWriter
    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    @ObservationIgnored private var watcher: FileWatcherGroup?
    /// Bumped by every load; a background read publishes only if no newer load started meanwhile.
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReadIsFull = false

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        watchForChanges: Bool = true,
        backupKind: String = "known_hosts",
        loadsInBackground: Bool = false
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.backupKind = backupKind
        self.loadsInBackground = loadsInBackground
        if loadsInBackground { reload() } else { load() }
        if watchForChanges { startWatching() }
    }

    public var backupKeep: Int? { writer.backups?.keep }

    public func setBackupKeep(_ keep: Int) {
        guard var backups = writer.backups else { return }
        backups.keep = max(keep, 1)
        writer = SafeFileWriter(backups: backups)
    }

    /// Reads and parses on the calling (main) actor. Supersedes a background read still running.
    public func load() {
        loadGeneration += 1
        loadTask = nil
        isLoading = false
        apply(Self.read(fileURL))
    }

    /// Reads and parses off the main actor, then publishes like `load()`. A newer load of either kind
    /// wins: a stale read is dropped, so it never overwrites a newer document.
    /// `onlyIfChanged`: publish only when the file's bytes differ from the loaded ones (watcher events).
    public func reload(onlyIfChanged: Bool = false) {
        // Replacing a full read keeps it full: what it would have published must still be published.
        let onlyIfChanged = onlyIfChanged && !(loadTask != nil && pendingReadIsFull)
        pendingReadIsFull = !onlyIfChanged
        loadGeneration += 1
        let generation = loadGeneration
        let url = fileURL
        isLoading = true
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Self.read(url) }.value
            guard let self, generation == self.loadGeneration else { return }
            self.loadTask = nil
            self.isLoading = false
            if onlyIfChanged && result.fingerprint == self.diskFingerprint { return }
            self.apply(result)
        }
    }

    /// Returns once no background read is running (including any that replaced the one awaited).
    public func waitForLoad() async {
        while let task = loadTask { await task.value }
    }

    /// What one read of the file produced; built off the main actor by `reload()`.
    private enum ReadResult: Sendable {
        case loaded(KnownHostsDocument, FileFingerprint)
        /// `fingerprint` is kept for a file that exists but cannot be shown (not UTF-8).
        case failed(ConfigLoadState, fingerprint: FileFingerprint?)

        var fingerprint: FileFingerprint? {
            switch self {
            case .loaded(_, let fingerprint): fingerprint
            case .failed(_, let fingerprint): fingerprint
            }
        }
    }

    private nonisolated static func read(_ url: URL) -> ReadResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .failed(.missing, fingerprint: nil)
        } catch {
            return .failed(.unreadable(error.localizedDescription), fingerprint: nil)
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            return .failed(.notUTF8, fingerprint: FileFingerprint(data: data))
        }
        return .loaded(KnownHostsDocument(parsing: text), FileFingerprint(data: data))
    }

    private func apply(_ result: ReadResult) {
        revision += 1
        switch result {
        case .loaded(let parsed, let fingerprint):
            document = parsed
            diskFingerprint = fingerprint
            loadState = .loaded
        case .failed(let state, let fingerprint):
            reset(state, fingerprint: fingerprint)
        }
    }

    /// Removes lines of the document the user saw (`revision`). Refuses if it changed meanwhile.
    public func remove(lines: Set<Int>, ifRevision expected: Int) throws {
        guard loadState == .loaded else { throw KnownHostsStoreError.notEditable }
        guard expected == revision else { throw KnownHostsStoreError.staleSelection }
        var updated = document
        updated.remove(lines: lines)
        try write(updated.render())
    }

    /// Replaces the file with `text` (a backup's contents). Creates it (0600) when missing.
    public func restore(text: String) throws {
        guard loadState == .loaded || loadState == .missing else { throw KnownHostsStoreError.notEditable }
        try write(text)
    }

    private func write(_ text: String) throws {
        do {
            try writer.write(text, to: fileURL, expected: diskFingerprint, backupKind: backupKind)
        } catch SafeFileWriterError.conflict {
            load()
            throw KnownHostsStoreError.conflict
        } catch let error as SafeFileWriterError {
            throw KnownHostsStoreError.writeFailed(error)
        }
        load()
    }

    /// Directories currently watched (test visibility).
    var watchedDirectories: [String] { watcher?.watchedDirectories ?? [] }

    func fileDidChange() {
        watcher?.refresh()   // the symlink or its target directory may have moved
        if loadsInBackground {
            reload(onlyIfChanged: true)
            return
        }
        let current = try? FileFingerprint.of(fileAt: fileURL)
        guard current != diskFingerprint else { return }
        load()
    }

    /// `fingerprint` is kept for a file that exists but cannot be shown (not UTF-8), so the
    /// directory watcher does not reload it on every unrelated event.
    private func reset(_ state: ConfigLoadState, fingerprint: FileFingerprint? = nil) {
        document = .empty
        diskFingerprint = fingerprint
        loadState = state
    }

    private func startWatching() {
        let weakStore = WeakKnownHostsStore(self)
        watcher = FileWatcherGroup(file: fileURL) {
            Task { @MainActor in weakStore.value?.fileDidChange() }
        }
        isWatching = watcher != nil
    }
}

private final class WeakKnownHostsStore: @unchecked Sendable {
    weak var value: KnownHostsStore?
    init(_ value: KnownHostsStore) { self.value = value }
}
