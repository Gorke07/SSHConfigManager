import Foundation
import Testing
@testable import SSHConfigKit

struct BackupManagerTests {
    let start = Date(timeIntervalSince1970: 1_791_000_000)

    private func permissions(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    @Test func backupCopiesContentWithPrivatePermissions() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "Host a\n", permissions: 0o644)
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), now: { clock.now })

        let backup = try manager.backup(fileAt: source, kind: "config")

        #expect(try String(contentsOf: backup, encoding: .utf8) == "Host a\n")
        #expect(try permissions(backup) == 0o600)
        #expect(try permissions(backup.deletingLastPathComponent()) == 0o700)
        #expect(backup.lastPathComponent.hasSuffix("-config"))
        #expect(backup.lastPathComponent.count == "yyyyMMdd-HHmmss-config".count)
    }

    @Test func listIsNewestFirstAndParsesDates() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "1")
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), now: { clock.now })
        try manager.backup(fileAt: source, kind: "config")
        clock.advance(60)
        try Data("2".utf8).write(to: source, options: .atomic)
        try manager.backup(fileAt: source, kind: "config")

        let list = try manager.list(kind: "config")
        #expect(list.count == 2)
        #expect(try manager.contents(of: list[0]) == "2")
        #expect(list[0].date == start.addingTimeInterval(60))
        #expect(list[1].originalName == "config")
    }

    @Test func sameSecondBackupsDoNotCollide() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let fixed = start
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), now: { fixed })
        let first = try manager.backup(fileAt: source, kind: "config")
        let second = try manager.backup(fileAt: source, kind: "config")
        #expect(first != second)
        let list = try manager.list(kind: "config")
        #expect(list.count == 2)
        #expect(list.first?.url.lastPathComponent.contains("_2-") == true)
        #expect(list.last?.url.lastPathComponent.contains("_") == false)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func manyBackupsInSameSecondHandleHighCounters() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let fixed = start
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), keep: 20, now: { fixed })
        for _ in 0..<11 {
            try manager.backup(fileAt: source, kind: "config")
        }
        let list = try manager.list(kind: "config")
        #expect(list.count == 11)
        #expect(list.first?.url.lastPathComponent.contains("_11-") == true)
        #expect(list.last?.url.lastPathComponent.contains("_") == false)
    }

    @Test func pruneKeepsNewestN() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), keep: 3, now: { clock.now })
        for _ in 0..<5 {
            try manager.backup(fileAt: source, kind: "config")
            clock.advance(1)
        }
        let list = try manager.list(kind: "config")
        #expect(list.count == 3)
        #expect(list.first?.date == start.addingTimeInterval(4))
    }

    @Test func pruneKeepsNewestAcrossHighCounters() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let fixed = start
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), keep: 3, now: { fixed })
        var backupURLs: [URL] = []
        for _ in 0..<12 {
            let url = try manager.backup(fileAt: source, kind: "config")
            backupURLs.append(url)
        }
        let list = try manager.list(kind: "config")
        #expect(list.count == 3)
        // Verify that the backup files were actually created (at least the last 3)
        #expect(FileManager.default.fileExists(atPath: backupURLs[9].path))
        #expect(FileManager.default.fileExists(atPath: backupURLs[10].path))
        #expect(FileManager.default.fileExists(atPath: backupURLs[11].path))
    }

    @Test func symlinkSourceBacksUpTargetContent() throws {
        let tmp = try TempDir()
        let target = try tmp.file("dotfiles/config", "real")
        let link = tmp.url.appending(path: "config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let backup = try BackupManager(rootDirectory: tmp.url.appending(path: "B")).backup(fileAt: link, kind: "config")
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect(attributes[.type] as? FileAttributeType == .typeRegular)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "real")
    }

    @Test func unrelatedFilesAreIgnored() throws {
        let tmp = try TempDir()
        try tmp.file("config/.DS_Store", "")
        try tmp.file("config/notes.txt", "")
        #expect(try BackupManager(rootDirectory: tmp.url).list(kind: "config").isEmpty)
    }

    @Test func fingerprint() throws {
        let tmp = try TempDir()
        let file = try tmp.file("f", "abc")
        #expect(try FileFingerprint.of(fileAt: file) == FileFingerprint(data: Data("abc".utf8)))
        #expect(try FileFingerprint.of(fileAt: tmp.url.appending(path: "missing")) == nil)
    }
}
