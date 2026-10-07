import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct AppSupportAPITests {
    private func store(_ tmp: TempDir, name: String = "config", watch: Bool = false, keep: Int = 10) -> ConfigStore {
        ConfigStore(
            fileURL: tmp.url.appending(path: name),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), keep: keep)),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: watch)
    }

    @Test func publicInitializersBuildValues() {
        let entry = HostEntry(headerLine: 0, patterns: ["web"], directives: [HostDirective(line: 1, key: "User", value: "u")])
        #expect(entry.value(for: "user") == "u")
        #expect(MatchEntry(headerLine: 3, criteria: "all", text: "Match all").criteria == "all")
        #expect(IncludedHost(file: URL(filePath: "/x"), entry: entry).id == "/x#0")
        let line = DiffLine(kind: .added, text: "a", oldNumber: nil, newNumber: 1, missingNewline: false)
        #expect(DiffHunk(oldStart: 0, oldCount: 0, newStart: 1, newCount: 1, lines: [line]).header == "@@ -0,0 +1,1 @@")
    }

    @Test func setBackupKeepLimitsBackups() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = store(tmp)
        #expect(store.backupKeep == 10)
        store.setBackupKeep(2)
        #expect(store.backupKeep == 2)
        for port in ["1", "2", "3"] {
            try store.apply { doc in
                var draft = HostDraft(doc.hosts[0])
                draft.directives = [DraftDirective(key: "Port", value: port)]
                try doc.updateHost(at: 0, to: draft)
            }
            try await store.save()
        }
        let backups = try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "config")
        #expect(backups.count == 2)
    }

    @Test func setBackupKeepClampsToOne() throws {
        let tmp = try TempDir()
        let store = store(tmp)
        store.setBackupKeep(0)
        #expect(store.backupKeep == 1)
    }

    @Test func applyRecomputesIncludedHostsOnlyWhenIncludesChange() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Include extra\nHost a\n")
        let store = store(tmp)
        #expect(store.includedHosts.isEmpty)
        try tmp.file(".ssh/extra", "Host inc\n")

        try store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives = [DraftDirective(key: "Port", value: "22")]
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        #expect(store.includedHosts.isEmpty)   // include list unchanged → not re-resolved

        try store.apply { $0 = ConfigDocument(parsing: "Include extra other\nHost a\n") }
        #expect(store.includedHosts.map(\.entry.alias) == ["inc"])
    }

    @Test func createFileStartsWatching() throws {
        let tmp = try TempDir()
        let store = store(tmp, name: "new/.ssh/config", watch: true)
        try store.createFile()
        #expect(store.isWatching)
    }

    @Test func hugeDiffFallsBackToReplaceAll() {
        let old = (0..<2100).map { "old \($0)" }.joined(separator: "\n") + "\n"
        let new = (0..<2100).map { "new \($0)" }.joined(separator: "\n") + "\n"
        let lines = LineDiff.lines(old: old, new: new)
        #expect(lines.count == 4200)
        #expect(lines.prefix(2100).allSatisfy { $0.kind == .removed })
        #expect(lines.suffix(2100).allSatisfy { $0.kind == .added })
    }
}
