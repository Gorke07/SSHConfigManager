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

    @ObservationIgnored private var writer: SafeFileWriter
    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    @ObservationIgnored private var watcher: FileWatcherGroup?

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        watchForChanges: Bool = true,
        backupKind: String = "known_hosts"
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.backupKind = backupKind
        load()
        if watchForChanges { startWatching() }
    }

    public var backupKeep: Int? { writer.backups?.keep }

    public func setBackupKeep(_ keep: Int) {
        guard var backups = writer.backups else { return }
        backups.keep = max(keep, 1)
        writer = SafeFileWriter(backups: backups)
    }

    public func load() {
        revision += 1
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            reset(.missing)
            return
        } catch {
            reset(.unreadable(error.localizedDescription))
            return
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            reset(.notUTF8, fingerprint: FileFingerprint(data: data))
            return
        }
        document = KnownHostsDocument(parsing: text)
        diskFingerprint = FileFingerprint(data: data)
        loadState = .loaded
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

    func fileDidChange() {
        watcher?.refresh()   // the symlink or its target directory may have moved
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
