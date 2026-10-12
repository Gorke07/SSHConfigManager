import CryptoKit
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

    @Test func hunksAreCachedPerBackupAndInvalidatedWhenTheDocumentChanges() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        let first = backups.hunks(for: backup)
        _ = backups.hunks(for: backup)
        #expect(backups.hunksComputationCount == 1)
        #expect(backups.hunks(for: backup) == first)
        // A draft edit changes the current text: the diff is recomputed.
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives = [DraftDirective(key: "Port", value: "9")]
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        _ = backups.hunks(for: backup)
        #expect(backups.hunksComputationCount == 2)
    }

    @Test func unreadableBackupIsNotCached() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        try FileManager.default.removeItem(at: backup.url)
        _ = backups.hunks(for: backup)
        _ = backups.hunks(for: backup)
        #expect(backups.hunksComputationCount == 2)
    }

    @Test func refreshClearsTheHunksCache() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        _ = backups.hunks(for: backup)
        backups.refresh()
        _ = backups.hunks(for: backup)
        #expect(backups.hunksComputationCount == 2)
    }

    @Test func anotherBackupMissesTheHunksCache() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        try await saveEdit(app, port: "2")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.count == 2)
        _ = backups.hunks(for: backups.backups[0])
        _ = backups.hunks(for: backups.backups[1])
        #expect(backups.hunksComputationCount == 2)
        _ = backups.hunks(for: backups.backups[1])
        #expect(backups.hunksComputationCount == 2)
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
        app.select(.host(alias: "a", occurrence: 0))
        app.groupDraft = "Prod"   // typed, not applied; the restore confirmation discards it
        try backups.restore(backup)
        #expect(app.groupDraft == nil)
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

    // MARK: symlink-aware backupKind (2A-13)

    @Test func symlinkToTheDefaultFileUsesTheDefaultKind() throws {
        let tmp = try TempDir()
        let home = tmp.url
        try tmp.file("dotfiles/ssh_config", "Host a\n")
        let ssh = home.appending(path: ".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: ssh.appending(path: "config"), withDestinationURL: home.appending(path: "dotfiles/ssh_config"))
        #expect(AppModel.backupKind(for: ssh.appending(path: "config"), home: home) == "config")
        // The real target of the symlinked default is the same file.
        #expect(AppModel.backupKind(for: home.appending(path: "dotfiles/ssh_config"), home: home) == "config")
        // Another file keeps its hashed key.
        #expect(AppModel.backupKind(for: home.appending(path: "dotfiles/other"), home: home).hasPrefix("config-"))
    }

    @Test func backupsKeyedByTheOldHashedKindAreMigrated() async throws {
        let tmp = try TempDir()
        let home = tmp.url
        try tmp.file("dotfiles/ssh_config", "Host a\n")
        let ssh = home.appending(path: ".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: ssh.appending(path: "config"), withDestinationURL: home.appending(path: "dotfiles/ssh_config"))
        let real = home.appending(path: "dotfiles/ssh_config")
        // A backup written when the real file's path still had its own hashed folder, and one under "config".
        let manager = BackupManager(rootDirectory: home.appending(path: "Backups"), keep: 10)
        let legacy = try legacyKind(for: real)
        try manager.backup(fileAt: real, kind: legacy)
        #expect(try manager.list(kind: "config").isEmpty)

        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: home)
        settings.setConfigPath(real.path)
        let app = AppModel(settings: settings, backupRoot: home.appending(path: "Backups"),
                           processRunner: FixedRunner.valid,
                           makeStore: { url, backups, kind in
                               ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups), validator: ConfigValidator(runner: FixedRunner.valid),
                                           includeResolver: IncludeResolver(homeDirectory: home), watchForChanges: false, backupKind: kind)
                           })
        #expect(app.store.backupKind == "config")
        #expect(try app.backupManager.list(kind: "config").count == 1)
        #expect(try app.backupManager.list(kind: legacy).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Backups/\(legacy)").path))
        #expect(BackupsModel(model: app).backups.count == 1)
    }

    /// The pre-symlink key: the hash of the standardized path (what the app used before).
    private func legacyKind(for url: URL) throws -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return "config-" + digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    }

    // MARK: restore errors and a missing file (2A-4a, 2A-7)

    @Test func restoreWorksWhenTheConfigFileIsMissing() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        let url = tmp.url.appending(path: ".ssh/config")
        try FileManager.default.removeItem(at: url)
        app.store.discardChanges()
        #expect(app.store.loadState == .missing)

        try backups.restore(backup)
        #expect(app.store.loadState == .loaded)
        #expect(app.store.document.render() == "Host a\n")
        #expect(app.store.hasUnsavedChanges)
    }

    @Test func failedRestoreShowsOnceAndClearsOnDismiss() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        try FileManager.default.removeItem(at: backup.url)   // the real restore path now fails reading it
        #expect(backups.alertMessage == nil)
        backups.performRestore(backup)
        #expect(backups.restoreFailure != nil)
        #expect(backups.alertMessage == backups.restoreFailure)
        backups.alertMessage = nil
        #expect(backups.alertMessage == nil)
        #expect(!app.store.hasUnsavedChanges)
    }

    @Test func aPersistentListErrorIsNotShownAgainOnRefresh() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        // A file where the kind's folder should be makes listing throw.
        let root = tmp.url.appending(path: "Backups")
        let kindDir = root.appending(path: app.store.backupKind)
        try FileManager.default.removeItem(at: kindDir)
        try FileManager.default.createDirectory(at: kindDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: kindDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: kindDir.path) }
        let backups = BackupsModel(model: app)
        #expect(backups.alertMessage != nil)
        backups.alertMessage = nil
        backups.refresh()
        #expect(backups.alertMessage == nil)
    }
}
