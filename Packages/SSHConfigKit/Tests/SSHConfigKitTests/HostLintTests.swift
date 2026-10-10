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
        let issues = lint(existing: ["/h/.ssh/here"]).issues(for: doc.hosts[0], duplicates: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func unencryptedKeysAreReported() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/plain\n")
        let issues = lint(existing: ["/h/.ssh/plain"], unencrypted: ["/h/.ssh/plain"]).issues(for: doc.hosts[0], duplicates: [:])
        #expect(issues == [.unencryptedKey("~/.ssh/plain")])
    }

    @Test func duplicateAliasesAcrossFileAndIncludesCaseInsensitively() {
        let doc = ConfigDocument(parsing: "Host web\n  User a\nHost WEB other\n  User b\nHost *\n")
        let included = [IncludedHost(file: URL(filePath: "/h/.ssh/inc"), entry: ConfigDocument(parsing: "Host web\n").hosts[0])]
        let counts = HostLint.duplicateCounts(document: doc, included: included)
        #expect(counts["web"] == 3)
        #expect(counts["other"] == nil)
        #expect(counts["*"] == nil)
        let first = lint().issues(for: doc.hosts[0], duplicates: counts, isFirstOccurrence: true)
        #expect(first == [.duplicateAlias(alias: "web", isFirst: true)])
        let second = lint().issues(for: doc.hosts[1], duplicates: counts, isFirstOccurrence: false)
        #expect(second == [.duplicateAlias(alias: "WEB", isFirst: false)])
    }
}
