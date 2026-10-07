import Foundation
import Observation
import SSHConfigKit

/// Form state for one Host block. Every change is validated; drafts without blocking issues
/// are written into the store's in-memory document (the file itself changes only on Save).
@MainActor
@Observable
final class HostEditorModel {
    /// Directives with their own form field (IdentityFile is a list, everything else is "other options").
    static let fieldKeys = ["HostName", "User", "Port", "ProxyJump", "ForwardAgent"]

    let store: ConfigStore
    private(set) var item: SidebarItem
    var aliasText: String
    var fields: [String: String]
    var identityFiles: [String]
    var otherOptions: [DraftDirective]
    private(set) var issues: [DraftIssue] = []
    private(set) var editError: ConfigEditError?

    @ObservationIgnored private let validator: HostDraftValidator

    init?(item: SidebarItem, store: ConfigStore, homeDirectory: URL) {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return nil }
        self.store = store
        self.item = item
        aliasText = entry.patterns.joined(separator: " ")
        var fields: [String: String] = [:]
        for key in Self.fieldKeys { fields[key] = entry.value(for: key) ?? "" }
        self.fields = fields
        identityFiles = entry.values(for: "IdentityFile")
        let known = Set((Self.fieldKeys + ["IdentityFile"]).map { $0.lowercased() })
        otherOptions = entry.directives
            .filter { !known.contains($0.key.lowercased()) }
            .map { DraftDirective(key: $0.key, value: $0.value) }
        validator = HostDraftValidator(fileExists: { HostEditorModel.identityFileExists($0, home: homeDirectory) })
    }

    var draft: HostDraft {
        let patterns = aliasText.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
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
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else {
            editError = .hostNotFound(-1)
            return false
        }
        let draft = self.draft
        issues = validator.issues(for: draft, in: store.document, editing: entry.headerLine)
        guard !hasBlockingIssues else { return false }
        do {
            try store.apply { try $0.updateHost(at: entry.headerLine, to: draft) }
            editError = nil
            if let renamed = SidebarBuilder.item(forHeader: entry.headerLine, in: store.document) {
                item = renamed
            }
            return true
        } catch let error as ConfigEditError {
            editError = error
            return false
        } catch {
            return false
        }
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
