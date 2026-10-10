import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct KnownHostsStoreTests {
    static let ed = KnownHostsDocumentTests.ed
    static let text = "a.example.com ssh-ed25519 \(ed)\r\n# note\r\nb.example.com ssh-ed25519 \(ed)\r\nc.example.com ssh-ed25519 \(ed)"

    func makeStore(_ tmp: TempDir, contents: String? = text) throws -> KnownHostsStore {
        if let contents { try tmp.file("known_hosts", contents, permissions: 0o644) }
        return KnownHostsStore(
            fileURL: tmp.url.appending(path: "known_hosts"),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            watchForChanges: false)
    }

    @Test func loadsTheFile() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.entries.count == 3)
        #expect(store.backupKind == "known_hosts")
    }

    @Test func missingFileIsAnEmptyListNotAnError() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .missing)
        #expect(store.document.entries.isEmpty)
    }

    @Test func notUTF8IsNotReloadedOnEveryDirectoryEvent() throws {
        let tmp = try TempDir()
        try Data([0xFF, 0xFE, 0x00]).write(to: tmp.url.appending(path: "known_hosts"))
        let store = try makeStore(tmp, contents: nil)
        let revision = store.revision
        store.fileDidChange()
        store.fileDidChange()
        #expect(store.revision == revision)
        try tmp.file("known_hosts", Self.text, permissions: 0o644)
        store.fileDidChange()
        #expect(store.loadState == .loaded)
    }

    @Test func notUTF8IsNeverEditable() throws {
        let tmp = try TempDir()
        try Data([0xFF, 0xFE, 0x00]).write(to: tmp.url.appending(path: "known_hosts"))
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .notUTF8)
        #expect(throws: KnownHostsStoreError.notEditable) { try store.remove(lines: [0], ifRevision: store.revision) }
    }

    @Test func removeWritesImmediatelyKeepsOtherBytesPermissionsAndBacksUp() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        try store.remove(lines: [2], ifRevision: store.revision)
        let expected = "a.example.com ssh-ed25519 \(Self.ed)\r\n# note\r\nc.example.com ssh-ed25519 \(Self.ed)"
        #expect(try tmp.read("known_hosts") == expected)
        #expect(store.document.render() == expected)
        let mode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "known_hosts").path)[.posixPermissions] as? Int
        #expect(mode == 0o644)
        let backups = try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "known_hosts")
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0].url, encoding: .utf8) == Self.text)
    }

    @Test func removingWithAnOldRevisionIsRefused() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let seen = store.revision
        store.load()   // e.g. the watcher reloaded after `ssh` appended a key
        #expect(throws: KnownHostsStoreError.staleSelection) { try store.remove(lines: [0], ifRevision: seen) }
        #expect(try tmp.read("known_hosts") == Self.text)
    }

    @Test func externalChangeBeforeRemoveIsAConflictAndReloads() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let seen = store.revision
        try tmp.file("known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.text)
        #expect(throws: KnownHostsStoreError.conflict) { try store.remove(lines: [0], ifRevision: seen) }
        #expect(try tmp.read("known_hosts").hasPrefix("new.example.com"))
        #expect(store.revision != seen)
        #expect(store.document.entries.first?.names == [.plain(KnownHostAddress(host: "new.example.com", port: 22, isPattern: false))])
    }

    @Test func restoreCreatesAMissingFileWith0600() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil)
        try store.restore(text: "a.example.com ssh-ed25519 \(Self.ed)\n")
        #expect(store.loadState == .loaded)
        #expect(store.document.entries.count == 1)
        let mode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "known_hosts").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func restoreBacksUpTheCurrentFile() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        try store.restore(text: "")
        #expect(try tmp.read("known_hosts") == "")
        #expect(try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "known_hosts").count == 1)
    }

    @Test func symlinkedFileIsReplacedThroughTheLink() throws {
        let tmp = try TempDir()
        let real = try tmp.file("real/known_hosts", Self.text)
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "known_hosts"), withDestinationURL: real)
        let store = KnownHostsStore(fileURL: tmp.url.appending(path: "known_hosts"), writer: SafeFileWriter(backups: nil), watchForChanges: false)
        try store.remove(lines: [0], ifRevision: store.revision)
        #expect(try tmp.read("real/known_hosts").hasPrefix("# note"))
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: tmp.url.appending(path: "known_hosts").path)
        #expect(link == real.path)
    }
}
