import Foundation
import Observation
import SSHConfigKit

/// Drives the Save sheet: diff + `ssh -G` review, then save, with conflict resolution.
@MainActor
@Observable
final class SaveFlowModel: Identifiable {
    enum Phase: Equatable {
        case preparing
        case review(SavePreparation)
        case saving
        case conflict
        case failed(String)
        case done
    }

    let id = UUID()
    let store: ConfigStore
    private(set) var phase: Phase = .preparing
    /// The alias `ssh -G` probes (the host being edited); nil lets the store pick the first host.
    let probeAlias: String?
    /// nil when the disk version is unreadable or not UTF-8.
    private(set) var conflictDiskText: String?
    /// Why the disk version cannot be compared (nil when it can): shown instead of a diff.
    private(set) var conflictUnreadableMessage: String?
    private(set) var conflictDiff: [DiffHunk] = []
    /// The text the review (or the conflict diff) showed; a document changed since (another window) is reviewed again.
    @ObservationIgnored private var reviewedText: String?
    /// Fingerprint of `conflictDiskText` (nil: no file), the only disk state Overwrite may replace.
    @ObservationIgnored private var conflictFingerprint: FileFingerprint?

    init(store: ConfigStore, probeAlias: String? = nil) {
        self.store = store
        self.probeAlias = probeAlias
    }

    var canConfirm: Bool {
        if case .review(let preparation) = phase { return preparation.validation == .valid }
        return false
    }

    func prepare() async {
        phase = .preparing
        reviewedText = store.document.render()
        phase = .review(await store.prepareSave(probeAlias: probeAlias))
    }

    func confirm() async {
        guard canConfirm else { return }
        // The document changed while the sheet was open: show the new diff instead of saving unseen changes.
        guard store.document.render() == reviewedText else {
            await prepare()
            return
        }
        await save(overwriting: false)
    }

    func overwrite() async {
        guard phase == .conflict else { return }
        // Only overwrite the disk version the user actually reviewed.
        let read = Self.readDisk(store)
        guard let current = read.text else {
            phase = .failed(read.message ?? "")
            return
        }
        if current != conflictDiskText || store.document.render() != reviewedText {
            snapshotConflict()
            return
        }
        await save(overwriting: true)
    }

    /// Discards the in-memory edits and loads what is on disk now.
    func loadDiskVersion() {
        guard phase == .conflict else { return }
        store.discardChanges()
        phase = .done
    }

    /// Disk version (old) → my version (new), for the conflict view.
    func conflictHunks() -> [DiffHunk] {
        conflictDiff
    }

    static func diskVersusMemory(_ store: ConfigStore) -> [DiffHunk] {
        LineDiff.hunks(old: readDisk(store).text ?? "", new: store.document.render())
    }

    /// The disk text (a missing file counts as empty), or why it cannot be read: not valid UTF-8, or the read error.
    /// `fingerprint` is that of the bytes read (nil: no file).
    private static func readDisk(_ store: ConfigStore) -> (text: String?, message: String?, fingerprint: FileFingerprint?) {
        guard FileManager.default.fileExists(atPath: store.fileURL.path) else { return ("", nil, nil) }
        let data: Data
        do { data = try Data(contentsOf: store.fileURL) } catch {
            return (nil, Messages.text(for: ConfigLoadState.unreadable(error.localizedDescription)), nil)
        }
        let fingerprint = FileFingerprint(data: data)
        guard let text = String(validating: data, as: UTF8.self) else {
            return (nil, Messages.text(for: ConfigLoadState.notUTF8), fingerprint)
        }
        return (text, nil, fingerprint)
    }

    private func snapshotConflict() {
        let read = Self.readDisk(store)
        let mine = store.document.render()
        conflictDiskText = read.text
        conflictFingerprint = read.fingerprint
        conflictUnreadableMessage = read.message
        reviewedText = mine
        conflictDiff = read.text == nil ? [] : LineDiff.hunks(old: read.text ?? "", new: mine)
    }

    private func save(overwriting: Bool) async {
        phase = .saving
        do {
            if overwriting {
                // Overwrite only the disk version the user reviewed, even if it changes while ssh -G validates.
                try await store.save(overwritingDiskVersion: conflictFingerprint, probeAlias: probeAlias)
            } else {
                try await store.save(probeAlias: probeAlias)
            }
            phase = .done
        } catch ConfigStoreError.conflict {
            snapshotConflict()
            phase = .conflict
        } catch {
            AppLog.error(.save, error)
            phase = .failed(Messages.text(for: error))
        }
    }
}
