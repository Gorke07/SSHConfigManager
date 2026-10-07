import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct ConfigStoreTests {
    private func makeStore(_ tmp: TempDir, name: String = "config", watch: Bool = false) -> ConfigStore {
        ConfigStore(
            fileURL: tmp.url.appending(path: name),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
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

        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validationFailed? = error else {
            Issue.record("validationFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try Data(contentsOf: store.fileURL) == Data(original.utf8))

        try store.apply { $0.removeByteOrderMark() }
        try await store.save()
        #expect(try Data(contentsOf: store.fileURL) == Data("Host bom\r\n  HostName x\r\n".utf8))
        #expect(store.document.hosts.map(\.alias) == ["bom"])
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
}
