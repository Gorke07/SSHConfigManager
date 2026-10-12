import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

/// Tests run in the development language (English); Turkish completeness is covered by LocalizationTests.
struct MessagesTests {
    static let issues: [DraftIssue] = [
        .controlCharacter("User"), .emptyAlias, .aliasHasWhitespace, .duplicateAlias("web"), .duplicateAliasCaseOnly("Web"),
        .invalidPort("99999"), .invalidDirectiveKey("Bad Key"), .forbiddenDirectiveKey("Host"),
        .emptyDirectiveValue("User"), .identityFileMissing("~/.ssh/x"), .valueStartsComment("LocalCommand"),
    ]

    static let storeErrors: [ConfigStoreError] = [
        .notEditable, .conflict, .validationFailed("line 2: Bad configuration option: bogus"),
        .validationTimedOut, .writeFailed(.backupFailed("disk full")), .writeFailed(.writeFailed("EACCES")),
        .writeFailed(.conflict), .saveCancelled, .saveInProgress, .validatorUnavailable("no ssh"),
    ]

    @Test(arguments: issues)
    func everyIssueHasText(issue: DraftIssue) {
        let text = Messages.text(for: issue)
        #expect(!text.isEmpty)
        #expect(!text.hasPrefix("issue."), "anahtar katalogda bulunamadı: \(text)")
    }

    @Test(arguments: storeErrors)
    func everyStoreErrorHasText(error: ConfigStoreError) {
        let text = Messages.text(for: error)
        #expect(!text.isEmpty)
        #expect(!text.hasPrefix("store."))
    }

    @Test func payloadsAreIncluded() {
        #expect(Messages.text(for: DraftIssue.duplicateAlias("web")).contains("web"))
        #expect(Messages.text(for: ConfigStoreError.validationFailed("Bad port 'abc'")).contains("Bad port 'abc'"))
        #expect(Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("disk full"))).contains("disk full"))
        #expect(Messages.text(for: ConfigEditError.invalidAlias("a b")).contains("a b"))
    }

    @Test func backupAndWriteFailuresAreDistinct() {
        let backup = Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("x")))
        let write = Messages.text(for: ConfigStoreError.writeFailed(.writeFailed("x")))
        #expect(backup != write)
    }

    @Test func loadStatesAndOutcomes() {
        #expect(Messages.text(for: ConfigLoadState.loaded) == nil)
        #expect(Messages.text(for: ConfigLoadState.missing) != nil)
        #expect(Messages.text(for: ConfigLoadState.notUTF8) != nil)
        #expect(Messages.text(for: ConfigLoadState.unreadable("EPERM"))?.contains("EPERM") == true)
        #expect(Messages.text(for: ValidationOutcome.valid) != Messages.text(for: ValidationOutcome.timedOut))
        #expect(Messages.text(for: ValidationOutcome.invalid(message: "boom")).contains("boom"))
        #expect(Messages.text(for: ValidationOutcome.validatorUnavailable("nope")).contains("nope"))
    }

    @Test func editErrors() {
        for error: ConfigEditError in [.hostNotFound(0), .controlCharacter, .invalidDirectiveKey("a b"), .forbiddenDirectiveKey("Host"), .invalidAlias("x y")] {
            let text = Messages.text(for: error)
            #expect(!text.isEmpty && !text.hasPrefix("edit.") && !text.hasPrefix("issue."))
        }
    }

    @Test func genericErrorsRouteToSpecificTexts() {
        #expect(Messages.text(for: ConfigStoreError.conflict as any Error) == Messages.text(for: ConfigStoreError.conflict))
        struct Other: Error {}
        #expect(!Messages.text(for: Other() as any Error).isEmpty)
    }
}
