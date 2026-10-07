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

    @Test func backupKindIsStablePerPath() throws {
        let home = URL(filePath: "/Users/x")
        let def = home.appending(path: ".ssh/config")
        #expect(AppModel.backupKind(for: def, home: home) == "config")
        let other = URL(filePath: "/opt/ssh/config")
        let kind = AppModel.backupKind(for: other, home: home)
        #expect(kind == AppModel.backupKind(for: other, home: home))
        #expect(kind.count == 19)   // "config-" + 12 hex
        #expect(kind.hasPrefix("config-"))
        #expect(kind != AppModel.backupKind(for: URL(filePath: "/opt/other/config"), home: home))
    }

    @Test func backupsAreScopedToTheCurrentFile() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        try tmp.file("other/config", "Host b\n")
        #expect(app.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(BackupsModel(model: app).backups.isEmpty)
        try await saveEdit(app, port: "2")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.count == 1)
        #expect(try app.backupManager.contents(of: backups.backups[0]) == "Host b\n")
    }

    @Test func emptyWhenNoBackups() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.isEmpty)
        #expect(backups.errorMessage == nil)
    }

    @Test func knownHostsBackupsAreListedSeparatelyAndRestoredImmediately() throws {
        let tmp = try TempDir()
        let ed = KnownHostsModelTests.ed
        _ = try tmp.file(".ssh/known_hosts", "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        let model = makeTestModel(tmp, config: "Host x\n")
        try model.knownHosts.remove(lines: [0], ifRevision: model.knownHosts.revision)   // makes one backup

        let backups = BackupsModel(model: model)
        #expect(backups.fileKind == .config)
        #expect(backups.backups.isEmpty)
        backups.fileKind = .knownHosts
        #expect(backups.backups.count == 1)

        let backup = try #require(backups.backups.first)
        #expect(!backups.hunks(for: backup).isEmpty)
        try backups.restore(backup, seen: backups.knownHostsSnapshot())
        #expect(try tmp.read(".ssh/known_hosts") == "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        backups.refresh()
        #expect(backups.backups.count == 2)   // restoring backed up the current file first
    }

    @Test func aKnownHostsBackupIsNotRestoredIntoASwitchedFile() throws {
        let tmp = try TempDir()
        let ed = KnownHostsModelTests.ed
        _ = try tmp.file(".ssh/known_hosts", "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        let model = makeTestModel(tmp, config: "Host x\n")
        try model.knownHosts.remove(lines: [0], ifRevision: model.knownHosts.revision)
        let backups = BackupsModel(model: model)
        backups.fileKind = .knownHosts
        let backup = try #require(backups.backups.first)
        let seen = backups.knownHostsSnapshot()

        let otherText = "c.example.com ssh-ed25519 \(ed)\n"
        let other = try tmp.file("other_known_hosts", otherText)
        #expect(model.switchKnownHosts(to: other.path))
        #expect(throws: KnownHostsStoreError.staleSelection) { try backups.restore(backup, seen: seen) }
        #expect(throws: KnownHostsStoreError.staleSelection) { try backups.restore(backup, seen: backups.knownHostsSnapshot()) }
        #expect(try String(contentsOf: other, encoding: .utf8) == otherText)
    }

    @Test func aKnownHostsRestoreIsRefusedWhenTheFileReloadedSinceTheConfirmationOpened() throws {
        let tmp = try TempDir()
        let ed = KnownHostsModelTests.ed
        _ = try tmp.file(".ssh/known_hosts", "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        let model = makeTestModel(tmp, config: "Host x\n")
        try model.knownHosts.remove(lines: [0], ifRevision: model.knownHosts.revision)
        let backups = BackupsModel(model: model)
        backups.fileKind = .knownHosts
        let backup = try #require(backups.backups.first)
        let seen = backups.knownHostsSnapshot()

        let appended = "b.example.com ssh-ed25519 \(ed)\nnew.example.com ssh-ed25519 \(ed)\n"
        try tmp.file(".ssh/known_hosts", appended)   // ssh added a key while the dialog was open
        model.knownHosts.load()
        #expect(throws: KnownHostsStoreError.staleSelection) { try backups.restore(backup, seen: seen) }
        #expect(try tmp.read(".ssh/known_hosts") == appended)
        #expect(throws: KnownHostsStoreError.staleSelection) { try backups.restore(backup) }   // no snapshot: refused
    }
}
