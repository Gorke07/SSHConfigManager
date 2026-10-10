import Foundation
import Testing
@testable import SSHConfigKit

struct HostLintTests {
    let home = URL(filePath: "/h")

    func lint(existing: Set<String> = [], unencrypted: Set<String> = []) -> HostLint {
        HostLint(home: home,
                 fileExists: { existing.contains($0.path) },
                 encryption: { unencrypted.contains($0.path) ? .unencrypted : .encrypted })
    }

    @Test func missingIdentityFilesAreReportedButUnresolvableOnesAreNot() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/gone\n  IdentityFile ~/.ssh/here\n  IdentityFile ~/.ssh/id_%h\n")
        let issues = lint(existing: ["/h/.ssh/here"]).issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func unencryptedKeysAreReported() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/plain\n")
        let issues = lint(existing: ["/h/.ssh/plain"], unencrypted: ["/h/.ssh/plain"]).issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:])
        #expect(issues == [.unencryptedKey("~/.ssh/plain")])
    }

    @Test func duplicateAliasesAcrossFileAndIncludesCaseInsensitively() {
        let doc = ConfigDocument(parsing: "Host web\n  User a\nHost WEB other\n  User b\nHost *\n")
        let included = [IncludedHost(file: URL(filePath: "/h/.ssh/inc"), entry: ConfigDocument(parsing: "Host web\n").hosts[0])]
        let counts = HostLint.duplicateCounts(document: doc, included: included)
        #expect(counts["web"] == 3)
        #expect(counts["other"] == nil)
        #expect(counts["*"] == nil)
        let firsts = HostLint.firstBlocks(document: doc)
        let first = lint().issues(for: doc.hosts[0], duplicates: counts, firstBlocks: firsts)
        #expect(first == [.duplicateAlias(alias: "web", isFirst: true)])
        let second = lint().issues(for: doc.hosts[1], duplicates: counts, firstBlocks: firsts)
        #expect(second == [.duplicateAlias(alias: "WEB", isFirst: false)])
    }

    @Test func everyDuplicatedNameOnTheHostLineIsFlagged() {
        let doc = ConfigDocument(parsing: "Host web\nHost other web\nHost web *\n")
        let counts = HostLint.duplicateCounts(document: doc, included: [])
        let firsts = HostLint.firstBlocks(document: doc)
        #expect(counts == ["web": 3])
        #expect(lint().issues(for: doc.hosts[1], duplicates: counts, firstBlocks: firsts) == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(lint().issues(for: doc.hosts[2], duplicates: counts, firstBlocks: firsts) == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(lint().issues(for: doc.hosts[0], duplicates: counts, firstBlocks: firsts) == [.duplicateAlias(alias: "web", isFirst: true)])
    }

    @Test func firstBlocksMapsLowercasedNamesToFirstHeaderLine() {
        let doc = ConfigDocument(parsing: "Host A b\nHost a *\nHost !x\n")
        let firsts = HostLint.firstBlocks(document: doc)
        #expect(firsts == ["a": doc.hosts[0].headerLine, "b": doc.hosts[0].headerLine])
    }

    @Test func patternBlocksStillReportMissingIdentityFiles() {
        let doc = ConfigDocument(parsing: "Host *\n  IdentityFile ~/.ssh/gone\n")
        #expect(lint().issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:]) == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func nonexistentUnencryptedKeyIsOnlyMissing() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/k\n")
        let issues = lint(unencrypted: ["/h/.ssh/k"]).issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/k")])
    }

    @Test func unknownEncryptionIsNotFlagged() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/k\n")
        let unknown = HostLint(home: home, fileExists: { _ in true }, encryption: { _ in .unknown })
        #expect(unknown.issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:]).isEmpty)
    }

    @Test func identityFileNoneIsSkipped() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile None\n")
        #expect(lint().issues(for: doc.hosts[0], duplicates: [:], firstBlocks: [:]).isEmpty)
    }
}
