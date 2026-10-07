import Foundation
import Testing
@testable import SSHConfigKit

struct SafeFileWriterTests {
    private func permissions(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    private func writer(_ tmp: TempDir) -> SafeFileWriter {
        SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups")))
    }

    @Test func createsNewFileWith0600() throws {
        let tmp = try TempDir()
        let url = tmp.url.appending(path: "config")
        try writer(tmp).write("Host a\n", to: url, expected: nil, backupKind: "config")
        #expect(try tmp.read("config") == "Host a\n")
        #expect(try permissions(url) == 0o600)
    }

    @Test func preservesExistingPermissionsAndBacksUpOldContent() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "old", permissions: 0o644)
        let w = writer(tmp)
        try w.write("new", to: url, expected: try FileFingerprint.of(fileAt: url), backupKind: "config")
        #expect(try tmp.read("config") == "new")
        #expect(try permissions(url) == 0o644)
        let backups = try #require(w.backups).list(kind: "config")
        #expect(backups.count == 1)
        #expect(try w.backups!.contents(of: backups[0]) == "old")
    }

    @Test func writesThroughSymlinkAndKeepsTheLink() throws {
        let tmp = try TempDir()
        let target = try tmp.file("dotfiles/ssh/config", "old")
        let link = tmp.url.appending(path: "config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try writer(tmp).write("new", to: link, expected: try FileFingerprint.of(fileAt: link), backupKind: "config")

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try tmp.read("dotfiles/ssh/config") == "new")
    }

    @Test func externalChangeIsAConflict() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "v1")
        let loaded = try FileFingerprint.of(fileAt: url)
        try Data("v2 from vim".utf8).write(to: url)

        #expect(throws: SafeFileWriterError.conflict) {
            try writer(tmp).write("mine", to: url, expected: loaded, backupKind: "config")
        }
        #expect(try tmp.read("config") == "v2 from vim")
    }

    @Test func fileCreatedExternallyIsAConflict() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "appeared")
        #expect(throws: SafeFileWriterError.conflict) {
            try writer(tmp).write("mine", to: url, expected: nil, backupKind: "config")
        }
    }

    @Test func ignoreConflictOverwrites() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "theirs")
        try writer(tmp).write("mine", to: url, expected: nil, ignoreConflict: true, backupKind: "config")
        #expect(try tmp.read("config") == "mine")
    }

    @Test func backupFailureLeavesFileUntouched() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "old")
        let blocker = try tmp.file("NotADirectory", "x")
        let w = SafeFileWriter(backups: BackupManager(rootDirectory: blocker))
        let expected = try FileFingerprint.of(fileAt: url)
        let error = #expect(throws: SafeFileWriterError.self) {
            try w.write("new", to: url, expected: expected, backupKind: "config")
        }
        guard case .backupFailed? = error else {
            Issue.record("backupFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("config") == "old")
    }

    @Test func writeFailureLeavesFileUntouchedAndNoTempFiles() throws {
        let tmp = try TempDir()
        let url = try tmp.file("ro/config", "old")
        let directory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let expected = try FileFingerprint.of(fileAt: url)
        let error = #expect(throws: SafeFileWriterError.self) {
            try SafeFileWriter(backups: nil).write("new", to: url, expected: expected, backupKind: "config")
        }
        guard case .writeFailed? = error else {
            Issue.record("writeFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("ro/config") == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["config"])
    }
}
