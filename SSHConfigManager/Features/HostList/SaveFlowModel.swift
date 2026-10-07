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
    /// nil when the disk version is unreadable or not UTF-8.
    private(set) var conflictDiskText: String?
    private(set) var conflictDiff: [DiffHunk] = []

    init(store: ConfigStore) {
        self.store = store
    }

    var canConfirm: Bool {
        if case .review(let preparation) = phase { return preparation.validation == .valid }
        return false
    }

    func prepare() async {
        phase = .preparing
        phase = .review(await store.prepareSave())
    }

    func confirm() async {
        guard canConfirm else { return }
        await save(overwriting: false)
    }

    func overwrite() async {
        guard phase == .conflict else { return }
        // Only overwrite the disk version the user actually reviewed.
        guard let current = Self.diskText(store) else {
            phase = .failed(Self.undecodableMessage(store))
            return
        }
        if current != conflictDiskText {
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
        LineDiff.hunks(old: diskText(store) ?? "", new: store.document.render())
    }

    /// nil when the file cannot be read or is not valid UTF-8; a missing file counts as empty.
    private static func diskText(_ store: ConfigStore) -> String? {
        guard FileManager.default.fileExists(atPath: store.fileURL.path) else { return "" }
        guard let data = try? Data(contentsOf: store.fileURL) else { return nil }
        return String(validating: data, as: UTF8.self)
    }

    private static func undecodableMessage(_ store: ConfigStore) -> String {
        let readable = (try? Data(contentsOf: store.fileURL)) != nil
        let state: ConfigLoadState = readable ? .notUTF8 : .unreadable("")
        return Messages.text(for: state) ?? ""
    }

    private func snapshotConflict() {
        conflictDiskText = Self.diskText(store)
        conflictDiff = LineDiff.hunks(old: conflictDiskText ?? "", new: store.document.render())
    }

    private func save(overwriting: Bool) async {
        phase = .saving
        do {
            try await store.save(overwritingExternalChanges: overwriting)
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
