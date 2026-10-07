import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct BackupsModelTests {
    private func saveEdit(_ app: AppModel, port: String) async throws {
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives = [DraftDirective(key: "Port", value: port)]
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        try await app.store.save()
    }

    @Test func listsBackupsNewestFirst() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        try await saveEdit(app, port: "2")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.count == 2)
        #expect(try app.backupManager.contents(of: backups.backups[0]) == "Host a\n    Port 1\n")
        #expect(backups.selected == nil)
        backups.selectedURL = backups.backups[1].url
        #expect(backups.selected?.url == backups.backups[1].url)
    }

    @Test func hunksCompareCurrentDocumentToBackup() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        let hunks = backups.hunks(for: backup)
        #expect(hunks.flatMap(\.lines).contains { $0.kind == .removed && $0.text == "    Port 1" })
    }

    @Test func restoreLoadsBackupAsUnsavedChanges() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        try backups.restore(backup)
        #expect(app.store.document.render() == "Host a\n")
        #expect(app.store.hasUnsavedChanges)
        #expect(try tmp.read(".ssh/config") == "Host a\n    Port 1\n")   // disk untouched until Save
    }

    @Test func emptyWhenNoBackups() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.isEmpty)
        #expect(backups.errorMessage == nil)
    }
}
