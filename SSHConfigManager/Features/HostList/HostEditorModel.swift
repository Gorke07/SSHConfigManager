import Foundation
import Observation
import SSHConfigKit

/// Form state for one Host block. Every change is validated; drafts without blocking issues
/// are written into the store's in-memory document (the file itself changes only on Save).
@MainActor
@Observable
final class HostEditorModel {
    /// Directives with their own form field (IdentityFile is a list, everything else is "other options").
    static let fieldKeys = HostDraftValidator.singleValueKeys

    let store: ConfigStore
    private(set) var item: SidebarItem
    var aliasText: String
    var fields: [String: String]
    var identityFiles: [String]
    var otherOptions: [DraftDirective]
    private(set) var issues: [DraftIssue] = []
    private(set) var failure: (any Error)?
    /// True when the document's block changed underneath the form; nothing is written until the editor is reopened.
    private(set) var isStale = false
    /// True when the last commit was blocked (by validation or a failed write) and the draft still differs from the document.
    private(set) var hasPendingChanges = false
    /// Called synchronously from `commit()` when the edit changed the item's identity (a rename).
    @ObservationIgnored var onItemChange: ((SidebarItem) -> Void)?

    @ObservationIgnored private var baseline: HostDraft

    @ObservationIgnored private let validator: HostDraftValidator

    init?(item: SidebarItem, store: ConfigStore, homeDirectory: URL) {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return nil }
        self.store = store
        self.item = item
        baseline = HostDraft(entry)
        // Quoted like the file, so a `Host "my host"` pattern survives unrelated edits.
        aliasText = HostDraft.aliasText(for: entry.patterns)
        var fields: [String: String] = [:]
        for key in Self.fieldKeys { fields[key] = entry.value(for: key) ?? "" }
        self.fields = fields
        identityFiles = entry.values(for: "IdentityFile")
        // Everything the form fields and the identity list do not show stays in "Other options": unknown keys, and
        // repeats of a single-value key (the field shows the first; ssh ignores the rest, but they remain in the file).
        let fieldKeys = Set(Self.fieldKeys.map(\.asciiLowercased))
        var seen = Set<String>()
        var others: [DraftDirective] = []
        for directive in entry.directives {
            let key = directive.key.asciiLowercased
            if key == "identityfile" { continue }
            if fieldKeys.contains(key), seen.insert(key).inserted { continue }
            others.append(DraftDirective(key: directive.key, value: directive.value))
        }
        otherOptions = others
        let validator = HostDraftValidator(fileExists: { HostEditorModel.identityFileExists($0, home: homeDirectory) })
        self.validator = validator
        // Repeated values already in the file are explained as soon as the form opens.
        issues = validator.issues(for: HostDraft(entry), in: store.document, editing: entry.headerLine)
            .filter { if case .duplicateFieldKey = $0 { true } else { false } }
    }

    var draft: HostDraft {
        let patterns = HostDraft.patterns(fromAliasText: aliasText)
        var directives: [DraftDirective] = []
        for key in Self.fieldKeys {
            let value = (fields[key] ?? "").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { directives.append(DraftDirective(key: key, value: value)) }
        }
        for file in identityFiles {
            let value = file.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { directives.append(DraftDirective(key: "IdentityFile", value: value)) }
        }
        for option in otherOptions where !(option.key.isEmpty && option.value.isEmpty) {
            directives.append(option)
        }
        return HostDraft(patterns: patterns, directives: directives)
    }

    var hasBlockingIssues: Bool { issues.contains(where: \.isBlocking) }

    /// Validates the draft and, when nothing blocks it, applies it to the document.
    /// Returns true when the document reflects the draft afterwards.
    @discardableResult
    func commit() -> Bool {
        failure = nil
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else {
            failure = ConfigEditError.hostNotFound(-1)
            issues = []
            hasPendingChanges = draft != baseline
            return false
        }
        guard HostDraft(entry) == baseline else {
            isStale = true
            hasPendingChanges = draft != baseline
            return false
        }
        let draft = self.draft
        issues = validator.issues(for: draft, in: store.document, editing: entry.headerLine)
        guard !hasBlockingIssues else {
            hasPendingChanges = draft != baseline
            return false
        }
        do {
            try store.apply { try $0.updateHost(at: entry.headerLine, to: draft) }
            if let renamed = SidebarBuilder.item(forHeader: entry.headerLine, in: store.document) {
                let changed = renamed != item
                item = renamed
                if let updated = SidebarBuilder.hostEntry(for: renamed, in: store.document) {
                    baseline = HostDraft(updated)
                }
                if changed { onItemChange?(renamed) }
            }
            hasPendingChanges = false
            return true
        } catch {
            failure = error
            hasPendingChanges = draft != baseline
            return false
        }
    }

    /// The block moved to another occurrence index (an earlier block of the same alias was deleted); its content is unchanged.
    func follow(to newItem: SidebarItem) {
        item = newItem
    }

    /// `~/…` and absolute paths are checked; relative paths and `%` tokens are not.
    nonisolated static func identityFileExists(_ value: String, home: URL) -> Bool {
        let path: String
        if value.hasPrefix("~/") {
            path = home.appending(path: String(value.dropFirst(2))).path
        } else if value.hasPrefix("/") {
            path = value
        } else {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }
}
