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
    private(set) var conflictDiskText = ""
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
        let current = Self.diskText(store)
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
        LineDiff.hunks(old: diskText(store), new: store.document.render())
    }

    private static func diskText(_ store: ConfigStore) -> String {
        (try? Data(contentsOf: store.fileURL)).flatMap { String(validating: $0, as: UTF8.self) } ?? ""
    }

    private func snapshotConflict() {
        conflictDiskText = Self.diskText(store)
        conflictDiff = LineDiff.hunks(old: conflictDiskText, new: store.document.render())
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
            phase = .failed(Messages.text(for: error))
        }
    }
}
