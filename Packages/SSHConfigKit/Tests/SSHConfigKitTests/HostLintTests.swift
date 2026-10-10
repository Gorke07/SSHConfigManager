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
        let issues = lint(existing: ["/h/.ssh/here"]).issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func unencryptedKeysAreReported() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/plain\n")
        let issues = lint(existing: ["/h/.ssh/plain"], unencrypted: ["/h/.ssh/plain"]).issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:])
        #expect(issues == [.unencryptedKey("~/.ssh/plain")])
    }

    private func lintIssues(_ text: String, included: [IncludedHost] = []) -> [[HostIssue]] {
        let doc = ConfigDocument(parsing: text)
        let counts = HostLint.duplicateCounts(document: doc, included: included)
        let exact = HostLint.exactDuplicateCounts(document: doc, included: included)
        let firsts = HostLint.firstBlocks(document: doc)
        return doc.hosts.map { lint().issues(for: $0, duplicates: counts, exactDuplicates: exact, firstBlocks: firsts) }
    }

    @Test func exactDuplicatesAreFirstAndLaterEvenAcrossIncludes() {
        let included = [IncludedHost(file: URL(filePath: "/h/.ssh/inc"), entry: ConfigDocument(parsing: "Host web\n").hosts[0])]
        let result = lintIssues("Host web\n  User a\nHost web other\n  User b\nHost *\n", included: included)
        #expect(result[0] == [.duplicateAlias(alias: "web", isFirst: true)])
        #expect(result[1] == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(result[2].isEmpty)
    }

    @Test func caseOnlyVariantsGetTheCaseOnlyIssueForBoth() {
        let result = lintIssues("Host web\nHost Web\n")
        #expect(result[0] == [.duplicateAliasCaseOnly(alias: "web")])
        #expect(result[1] == [.duplicateAliasCaseOnly(alias: "Web")])
    }

    @Test func includedCaseVariantIsCaseOnly() {
        let included = [IncludedHost(file: URL(filePath: "/h/.ssh/inc"), entry: ConfigDocument(parsing: "Host Web\n").hosts[0])]
        #expect(lintIssues("Host web\n", included: included) == [[.duplicateAliasCaseOnly(alias: "web")]])
    }

    @Test func everyDuplicatedNameOnTheHostLineIsFlagged() {
        let doc = ConfigDocument(parsing: "Host web\nHost other web\nHost web *\n")
        let counts = HostLint.duplicateCounts(document: doc, included: [])
        #expect(counts == ["web": 3])
        let result = lintIssues("Host web\nHost other web\nHost web *\n")
        #expect(result[0] == [.duplicateAlias(alias: "web", isFirst: true)])
        #expect(result[1] == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(result[2] == [.duplicateAlias(alias: "web", isFirst: false)])
    }

    @Test func firstBlocksMapsExactNamesToFirstHeaderLine() {
        let doc = ConfigDocument(parsing: "Host A b\nHost a *\nHost !x\n")
        let firsts = HostLint.firstBlocks(document: doc)
        #expect(firsts == ["A": doc.hosts[0].headerLine, "b": doc.hosts[0].headerLine, "a": doc.hosts[1].headerLine])
    }

    @Test func patternBlocksStillReportMissingIdentityFiles() {
        let doc = ConfigDocument(parsing: "Host *\n  IdentityFile ~/.ssh/gone\n")
        #expect(lint().issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:]) == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func nonexistentUnencryptedKeyIsOnlyMissing() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/k\n")
        let issues = lint(unencrypted: ["/h/.ssh/k"]).issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/k")])
    }

    @Test func unknownEncryptionIsNotFlagged() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/k\n")
        let unknown = HostLint(home: home, fileExists: { _ in true }, encryption: { _ in .unknown })
        #expect(unknown.issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:]).isEmpty)
    }

    @Test func identityFileNoneIsSkipped() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile None\n")
        #expect(lint().issues(for: doc.hosts[0], duplicates: [:], exactDuplicates: [:], firstBlocks: [:]).isEmpty)
    }
}
