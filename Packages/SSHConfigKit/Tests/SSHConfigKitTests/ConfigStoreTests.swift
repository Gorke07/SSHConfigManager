import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct ConfigStoreTests {
    private func makeStore(_ tmp: TempDir, name: String = "config", watch: Bool = false, validator: ConfigValidator = ConfigValidator()) -> ConfigStore {
        ConfigStore(
            fileURL: tmp.url.appending(path: name),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            validator: validator,
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: watch)
    }

    private func addPort(_ store: ConfigStore) throws {
        try store.apply { doc in
            let entry = doc.hosts[0]
            var draft = HostDraft(entry)
            draft.directives.append(DraftDirective(key: "Port", value: "2222"))
            try doc.updateHost(at: entry.headerLine, to: draft)
        }
    }

    @Test func backupKindSelectsBackupDirectory() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = ConfigStore(
            fileURL: tmp.url.appending(path: "config"),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            validator: ConfigValidator(runner: FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: false,
            backupKind: "x")
        #expect(store.backupKind == "x")
        try addPort(store)
        try await store.save()
        let dir = tmp.url.appending(path: "Backups/x")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "Backups/config").path))
    }

    @Test func loadsExistingFile() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.hosts.map(\.alias) == ["a"])
        #expect(!store.hasUnsavedChanges)
    }

    @Test func missingFileCanBeCreated() throws {
        let tmp = try TempDir()
        let store = makeStore(tmp, name: "sub/.ssh/config")
        #expect(store.loadState == .missing)
        #expect(throws: ConfigStoreError.notEditable) { try store.apply { _ in } }

        try store.createFile()

        #expect(store.loadState == .loaded)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let dirAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
        #expect(dirAttributes[.posixPermissions] as? Int == 0o700)
    }

    @Test func nonUTF8FileIsReadOnly() async throws {
        let tmp = try TempDir()
        try Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF]).write(to: tmp.url.appending(path: "config"))
        let store = makeStore(tmp)
        #expect(store.loadState == .notUTF8)
        await #expect(throws: ConfigStoreError.notEditable) { try await store.save() }
        #expect(try Data(contentsOf: tmp.url.appending(path: "config")) == Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF]))
    }

    @Test func bomFileIsReportedNotSilentlyChangedAndCanBeFixed() async throws {
        let tmp = try TempDir()
        let original = "\u{FEFF}Host bom\r\n  HostName x\r\n"
        try tmp.file("config", original)
        let store = makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.hasByteOrderMark)
        #expect(store.document.hosts.isEmpty)   // ssh does not see this Host line either

        try store.apply { try $0.addHost(HostDraft(patterns: ["added"])) }
        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validationFailed? = error else {
            Issue.record("validationFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try Data(contentsOf: store.fileURL) == Data(original.utf8))

        try store.apply { $0.removeByteOrderMark() }
        try await store.save()
        let written = try tmp.read("config")
        #expect(written.hasPrefix("Host bom\r\n  HostName x\r\n"))
        #expect(!written.hasPrefix("\u{FEFF}"))
        #expect(written == store.document.render())
        #expect(store.document.hosts.map(\.alias) == ["bom", "added"])
    }

    @Test func editPrepareAndSave() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        try addPort(store)
        #expect(store.hasUnsavedChanges)

        let preparation = await store.prepareSave()
        #expect(preparation.validation == .valid)
        #expect(preparation.hunks.count == 1)
        #expect(preparation.hunks[0].lines.filter { $0.kind == .added }.map(\.text) == ["  Port 2222"])

        try await store.save()
        #expect(!store.hasUnsavedChanges)
        #expect(try tmp.read("config") == "Host a\n  User u\n  Port 2222\n")
        #expect(try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "config").count == 1)
    }

    @Test func invalidConfigIsNotWritten() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "Bogus", value: "yes"))
            try doc.updateHost(at: 0, to: draft)
        }
        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validationFailed(let message)? = error else {
            Issue.record("validationFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(message.contains("Bad configuration option: bogus"))
        #expect(try tmp.read("config") == "Host a\n")
    }

    @Test func externalChangeWithoutLocalEditsReloads() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try tmp.file("config", "Host b\n")
        store.fileDidChange()
        #expect(store.document.hosts.map(\.alias) == ["b"])
        #expect(!store.externalChangePending)
    }

    @Test func externalChangeWithLocalEditsBecomesAConflict() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        try addPort(store)
        try tmp.file("config", "Host a\n  User changed-in-vim\n")

        store.fileDidChange()

        #expect(store.externalChangePending)
        #expect(store.hasUnsavedChanges)
        await #expect(throws: ConfigStoreError.conflict) { try await store.save() }
        #expect(try tmp.read("config") == "Host a\n  User changed-in-vim\n")

        try await store.save(overwritingExternalChanges: true)
        #expect(try tmp.read("config") == "Host a\n  User u\n  Port 2222\n")
        #expect(!store.externalChangePending)
    }

    @Test func ownSaveDoesNotTriggerReload() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        try await store.save()
        store.fileDidChange()
        #expect(!store.externalChangePending)
        #expect(!store.hasUnsavedChanges)

        try store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "User", value: "x"))
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        store.fileDidChange()
        #expect(store.hasUnsavedChanges)
        #expect(store.document.render().contains("User x"))
        #expect(!store.externalChangePending)
    }

    @Test func externalEditDuringValidationIsAConflict() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let runner = GatedRunner()
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        try addPort(store)
        let task = Task { try await store.save() }
        await runner.waitUntilEntered()
        try tmp.file("config", "Host external\n")
        store.fileDidChange()
        #expect(store.externalChangePending)
        runner.release()

        let result = await task.result
        guard case .failure(let error) = result, error as? ConfigStoreError == .conflict else {
            Issue.record("conflict bekleniyordu: \(result)")
            return
        }
        #expect(try tmp.read("config") == "Host external\n")
    }

    @Test func discardDuringValidationCancelsSave() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let runner = GatedRunner()
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        try addPort(store)
        let task = Task { try await store.save() }
        await runner.waitUntilEntered()
        store.discardChanges()
        runner.release()

        let result = await task.result
        guard case .failure(let error) = result, error as? ConfigStoreError == .saveCancelled else {
            Issue.record("saveCancelled bekleniyordu: \(result)")
            return
        }
        #expect(try tmp.read("config") == "Host a\n  User u\n")
        #expect(store.document.render() == store.diskText)
        #expect(!store.hasUnsavedChanges)
        #expect(!store.isSaving)
    }

    @Test func secondConcurrentSaveIsRejected() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let runner = GatedRunner()
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        try addPort(store)
        let first = Task { try await store.save() }
        await runner.waitUntilEntered()
        #expect(store.isSaving)

        await #expect(throws: ConfigStoreError.saveInProgress) { try await store.save() }
        #expect(store.isSaving)   // the rejected call must not touch the flag
        #expect(try tmp.read("config") == "Host a\n  User u\n")

        runner.release()
        try await first.value
        #expect(!store.isSaving)
        #expect(try tmp.read("config") == "Host a\n  User u\n  Port 2222\n")
        #expect(runner.arguments.count == 1)
    }

    @Test func saveWithoutChangesDoesNothing() async throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "Host a\n  User u\n")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let runner = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        for _ in 0..<3 { try await store.save() }
        #expect(try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "config").isEmpty)
        #expect(try tmp.read("config") == "Host a\n  User u\n")
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
        #expect(runner.calls.isEmpty)
    }

    @Test func unavailableValidatorIsDistinctAndNothingIsWritten() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp, validator: ConfigValidator(runner: ThrowingRunner()))
        try addPort(store)

        let preparation = await store.prepareSave()
        guard case .validatorUnavailable = preparation.validation else {
            Issue.record("validatorUnavailable bekleniyordu: \(preparation.validation)")
            return
        }
        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validatorUnavailable? = error else {
            Issue.record("validatorUnavailable bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("config") == "Host a\n  User u\n")
    }

    @Test func backupFailureIsATypedWriteFailure() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let backupRoot = try tmp.file("NotADirectory", "x")
        let store = ConfigStore(
            fileURL: tmp.url.appending(path: "config"),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: backupRoot)),
            validator: ConfigValidator(runner: FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: false)
        try addPort(store)
        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .writeFailed(.backupFailed)? = error else {
            Issue.record("writeFailed(.backupFailed) bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("config") == "Host a\n  User u\n")
    }

    @Test func saveForwardsProbeAlias() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let runner = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        try addPort(store)
        try await store.save(probeAlias: "probe-me")
        #expect(runner.calls.first?.last == "probe-me")
    }

    @Test func savedDocumentFollowsDiskNotEdits() async throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/extra", "Host inc\n")
        try tmp.file("config", "Host a\n")
        let runner = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let store = makeStore(tmp, validator: ConfigValidator(runner: runner))
        var notified = 0
        store.onDiskStateChange = { notified += 1 }

        try store.apply { $0 = ConfigDocument(parsing: "Include extra\nHost a\nHost b\n") }
        #expect(store.savedDocument.hosts.map(\.alias) == ["a"])
        #expect(store.savedIncludedHosts.isEmpty)
        #expect(store.includedHosts.map(\.entry.alias) == ["inc"])
        #expect(notified == 0)

        try await store.save()
        #expect(store.savedDocument.hosts.map(\.alias) == ["a", "b"])
        #expect(store.savedIncludedHosts.map(\.entry.alias) == ["inc"])
        #expect(notified == 1)

        try tmp.file("config", "Host c\n")
        store.discardChanges()
        #expect(store.savedDocument.hosts.map(\.alias) == ["c"])
        #expect(store.savedIncludedHosts.isEmpty)
        #expect(notified == 2)
    }

    @Test func isWatchingReflectsWatcherCreation() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        #expect(!makeStore(tmp, watch: false).isWatching)
        #expect(makeStore(tmp, watch: true).isWatching)
    }

    @Test func applyRefreshesIncludedHosts() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/extra", "Host inc\n")
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        #expect(store.includedHosts.isEmpty)
        try store.apply { $0 = ConfigDocument(parsing: "Include extra\nHost a\n") }
        #expect(store.includedHosts.map(\.entry.alias) == ["inc"])
    }

    @Test func discardClearsPendingExternalChange() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        try addPort(store)
        try tmp.file("config", "Host new\n")
        store.fileDidChange()
        #expect(store.externalChangePending)
        store.discardChanges()
        #expect(!store.externalChangePending)
        #expect(store.document.render() == "Host new\n")
    }

    @Test func discardChangesRestoresDiskVersion() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        store.discardChanges()
        #expect(!store.hasUnsavedChanges)
    }

    @Test func includedHostsAreListed() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/extra", "Host inc\n")
        try tmp.file("config", "Include extra\nHost a\n")
        #expect(makeStore(tmp).includedHosts.map(\.entry.alias) == ["inc"])
    }

    @Test func watcherReloadsAfterExternalEdit() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp, watch: true)
        try await Task.sleep(for: .milliseconds(300))
        try Data("Host z\n".utf8).write(to: store.fileURL, options: .atomic)

        var attempts = 0
        while store.document.hosts.first?.alias != "z" && attempts < 50 {
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        #expect(store.document.hosts.first?.alias == "z")
    }

    @Test func externalChangeWithLocalEditsRefreshesWhatSshReads() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\nHost gone\n  User x\n")
        let store = makeStore(tmp)
        var notified = 0
        store.onDiskStateChange = { notified += 1 }
        try addPort(store)
        try tmp.file("config", "Host a\n  User u\nHost added\n  User y\n")

        store.fileDidChange()

        #expect(store.externalChangePending)
        #expect(store.savedDocument.hosts.map(\.alias) == ["a", "added"])
        #expect(notified == 1)
        // The edit and the conflict guard are untouched.
        #expect(store.document.hosts.map(\.alias) == ["a", "gone"])
        #expect(store.diskText == "Host a\n  User u\nHost gone\n  User x\n")
        await #expect(throws: ConfigStoreError.conflict) { try await store.save() }
        #expect(try tmp.read("config") == "Host a\n  User u\nHost added\n  User y\n")
    }

    @Test func externalChangeToInvalidUTF8KeepsTheOldSavedView() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        try Data([0xFF, 0xFE]).write(to: tmp.url.appending(path: "config"))
        store.fileDidChange()
        #expect(store.externalChangePending)
        #expect(store.savedDocument.hosts.map(\.alias) == ["a"])
    }
}
