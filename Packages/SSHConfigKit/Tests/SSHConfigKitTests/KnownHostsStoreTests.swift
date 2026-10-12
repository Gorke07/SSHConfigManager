import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KnownHostsStoreTests {
    static let ed = KnownHostsDocumentTests.ed
    static let text = "a.example.com ssh-ed25519 \(ed)\r\n# note\r\nb.example.com ssh-ed25519 \(ed)\r\nc.example.com ssh-ed25519 \(ed)"

    func makeStore(_ tmp: TempDir, contents: String? = text, inBackground: Bool = false) throws -> KnownHostsStore {
        if let contents { try tmp.file("known_hosts", contents, permissions: 0o644) }
        return KnownHostsStore(
            fileURL: tmp.url.appending(path: "known_hosts"),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            watchForChanges: false,
            loadsInBackground: inBackground)
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

    @Test(.timeLimit(.minutes(1))) func watcherFollowsSymlinkRetargetedToAnotherDirectory() async throws {
        let tmp = try TempDir()
        try tmp.file("a/known_hosts", Self.text, permissions: 0o644)
        try tmp.file("b/known_hosts", Self.text, permissions: 0o644)
        try FileManager.default.createDirectory(at: tmp.url.appending(path: "ssh"), withIntermediateDirectories: true)
        let link = tmp.url.appending(path: "ssh/known_hosts")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tmp.url.appending(path: "a/known_hosts"))
        let store = KnownHostsStore(fileURL: link, writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))), watchForChanges: true)
        #expect(store.isWatching)
        try await Task.sleep(for: .milliseconds(300))

        let newLink = tmp.url.appending(path: "ssh/known_hosts.new")
        try FileManager.default.createSymbolicLink(at: newLink, withDestinationURL: tmp.url.appending(path: "b/known_hosts"))
        #expect(rename(newLink.path, link.path) == 0)
        let bDirectory = tmp.url.appending(path: "b").resolvingSymlinksInPath().path
        var waited = 0
        while !store.watchedDirectories.contains(bDirectory) && waited < 50 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        #expect(store.watchedDirectories.contains(bDirectory))

        try Data("z.example.com ssh-ed25519 \(Self.ed)\n".utf8).write(to: tmp.url.appending(path: "b/known_hosts"))
        var attempts = 0
        while store.document.entries.count != 1 && attempts < 50 {
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        #expect(store.document.entries.count == 1)
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

    @Test func restoreOverAFileCreatedExternallyIsAConflict() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .missing)
        try tmp.file("known_hosts", "x.example.com ssh-ed25519 \(Self.ed)\n", permissions: 0o644)   // appears after the load
        #expect(throws: KnownHostsStoreError.conflict) { try store.restore(text: "a.example.com ssh-ed25519 \(Self.ed)\n") }
        #expect(try tmp.read("known_hosts") == "x.example.com ssh-ed25519 \(Self.ed)\n")   // nothing was overwritten
        #expect(store.loadState == .loaded)   // the conflict reloaded what is on disk
        #expect(store.document.entries.count == 1)
    }

    @Test func restoreIsRefusedForANotUTF8File() throws {
        let tmp = try TempDir()
        let bytes = Data([0xFF, 0xFE, 0x00])
        try bytes.write(to: tmp.url.appending(path: "known_hosts"))
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .notUTF8)
        #expect(throws: KnownHostsStoreError.notEditable) { try store.restore(text: Self.text) }
        #expect(try Data(contentsOf: tmp.url.appending(path: "known_hosts")) == bytes)
    }

    @Test func fileDidChangeReloadsOnlyWhenTheFileChanged() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let revision = store.revision
        store.fileDidChange()   // nothing changed on disk
        #expect(store.revision == revision)
        try tmp.file("known_hosts", "only.example.com ssh-ed25519 \(Self.ed)\n", permissions: 0o644)
        store.fileDidChange()
        #expect(store.revision == revision + 1)
        #expect(store.document.entries.count == 1)
        try FileManager.default.removeItem(at: tmp.url.appending(path: "known_hosts"))
        store.fileDidChange()
        #expect(store.loadState == .missing)
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

    @Test func backgroundLoadPublishesWhenDone() async throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, inBackground: true)
        #expect(store.isLoading)
        #expect(store.revision == 0)   // nothing published yet
        #expect(throws: KnownHostsStoreError.notEditable) { try store.remove(lines: [0], ifRevision: store.revision) }
        await store.waitForLoad()
        #expect(!store.isLoading)
        #expect(store.revision == 1)
        #expect(store.loadState == .loaded)
        #expect(store.document.entries.count == 3)
        try store.remove(lines: [0], ifRevision: store.revision)
        #expect(try tmp.read("known_hosts").hasPrefix("# note"))
    }

    /// A background read that started before a newer load must not overwrite it, whichever file it read.
    @Test func aStaleBackgroundReadNeverOverwritesANewerLoad() async throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let start = store.revision
        store.reload()
        try tmp.file("known_hosts", "only.example.com ssh-ed25519 \(Self.ed)\n", permissions: 0o644)
        store.load()
        #expect(!store.isLoading)
        await store.waitForLoad()
        try await Task.sleep(for: .milliseconds(100))   // let a dropped read finish if it was still running
        #expect(store.revision == start + 1)
        #expect(store.document.entries.count == 1)
    }

    @Test func backgroundFileChangeReloadsOnlyWhenTheFileChanged() async throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, inBackground: true)
        await store.waitForLoad()
        let revision = store.revision
        store.fileDidChange()   // nothing changed on disk
        await store.waitForLoad()
        #expect(store.revision == revision)
        try tmp.file("known_hosts", "only.example.com ssh-ed25519 \(Self.ed)\n", permissions: 0o644)
        store.fileDidChange()
        await store.waitForLoad()
        #expect(store.revision == revision + 1)
        #expect(store.document.entries.count == 1)
        try FileManager.default.removeItem(at: tmp.url.appending(path: "known_hosts"))
        store.fileDidChange()
        await store.waitForLoad()
        #expect(store.loadState == .missing)
    }

    /// A watcher event during the first read must not turn it into a "publish only if changed" read.
    @Test func aFileChangeDuringTheFirstReadStillPublishes() async throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil, inBackground: true)
        store.fileDidChange()
        await store.waitForLoad()
        #expect(store.revision == 1)
        #expect(store.loadState == .missing)
    }
}
